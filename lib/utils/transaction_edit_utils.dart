import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import '../pages/transaction/transaction_editor_page.dart';
import '../data/repositories/local/local_repository.dart';
import '../providers/database_providers.dart';
import '../providers.dart';
import '../providers/budget_providers.dart';
import '../services/billing/post_processor.dart';
import '../l10n/app_localizations.dart';
import '../widgets/ui/ui.dart';
import '../widgets/biz/transaction_action_sheet.dart';
import 'shared_ledger_picker_filter.dart' show syntheticIdForSyncId;
import 'append_only_guard.dart';

class TransactionEditUtils {
  /// 打开整页编辑器修改/新建一笔。
  ///
  /// [asNew] 为 true 时把这条记录当作**模板**新建一笔（即"复制"）：
  /// 预填同样的分类/金额/备注/账户/标签，但不带 `editingTransactionId`，
  /// 且日期取**当前时间**（复制通常是"再记一笔类似的"，而不是补记同一天）。
  static Future<void> editTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    Category? category, {
    bool asNew = false,
  }) async {
    // ⭐ 二开：追加式守卫 —— 编辑**已有**账单需先在「数据管理 → 防误改」解锁；
    // 「复制」（asNew=true）属于新增，不受限制。
    if (!asNew && !await AppendOnlyGuard.guardEdit(context, ref)) return;
    if (!context.mounted) return;

    // 获取交易关联的标签ID(主表 + §7 override 表)
    final repo = ref.read(repositoryProvider);
    final tags = await repo.getTagsForTransaction(transaction.id);
    final tagIds = <int>[for (final t in tags) t.id];

    // §7 共享账本:加 TransactionTagOverrides → synthetic id 加进列表,
    // picker 显示选中
    if (repo is LocalRepository && transaction.syncId != null) {
      final overrides = await (repo.db.select(repo.db.transactionTagOverrides)
            ..where((t) => t.transactionSyncId.equals(transaction.syncId!)))
          .get();
      for (final ov in overrides) {
        final synthetic = syntheticIdForSyncId(ov.tagSyncId);
        if (!tagIds.contains(synthetic)) tagIds.add(synthetic);
      }
    }

    // §7 v25 共享账本:Editor 视角下记的 tx,categoryId/accountId 为 null,
    // 真实引用在 *SyncIdOverride。编辑时用 syntheticIdForSyncId 转成 picker
    // 列表里的 synthetic id,让 editor 反查时能命中"已选"。
    final int? initialCategoryId = transaction.categorySyncIdOverride != null
        ? syntheticIdForSyncId(transaction.categorySyncIdOverride!)
        : transaction.categoryId;
    final int? initialAccountId = transaction.accountSyncIdOverride != null
        ? syntheticIdForSyncId(transaction.accountSyncIdOverride!)
        : transaction.accountId;
    final int? initialToAccountId =
        transaction.toAccountSyncIdOverride != null
            ? syntheticIdForSyncId(transaction.toAccountSyncIdOverride!)
            : transaction.toAccountId;

    if (!context.mounted) return;

    // 所有类型（收入/支出/转账）都使用交易编辑器页面
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: transaction.type, // 'expense', 'income', 或 'transfer'
          quickAdd: true,
          initialCategoryId: initialCategoryId,
          initialAmount: transaction.amount,
          initialDate: asNew ? DateTime.now() : transaction.happenedAt,
          initialNote: transaction.note,
          editingTransactionId: asNew ? null : transaction.id,
          initialAccountId: initialAccountId,
          // 转账特有的参数
          initialToAccountId: initialToAccountId,
          // 标签
          initialTagIds: tagIds,
          // 账单标记（不计入收支/预算）回显
          initialExcludeFromStats: transaction.excludeFromStats,
          initialExcludeFromBudget: transaction.excludeFromBudget,
          // v30 多币种:编辑外币交易时汇率行按隐含汇率回显
          initialCurrencyCode: transaction.currencyCode,
          initialNativeAmount: transaction.nativeAmount,
        ),
      ),
    );
  }

  /// ⭐ 二开：点击一笔账单 → 弹出**底部操作面板**（对标钱迹的账单预览浮层），
  /// 而不是（像上游那样）直接整页跳到编辑器。
  ///
  /// 面板只负责返回用户的选择，真正的导航/写库在这里用**调用方 context** 执行 ——
  /// 避免在已经关闭的 sheet context 上做 Navigator.push / showDialog。
  static Future<void> showActions(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    Category? category,
  ) async {
    final action = await TransactionActionSheet.show(
      context,
      transaction: transaction,
      category: category,
    );
    if (action == null || !context.mounted) return;

    // 用 if/else 而非 switch：不依赖 Dart 3 对 case 结尾 break 的放宽，
    // 在各 SDK 版本下都不会有 fallthrough 歧义。
    if (action == TransactionAction.edit) {
      await editTransaction(context, ref, transaction, category);
    } else if (action == TransactionAction.copy) {
      await editTransaction(context, ref, transaction, category, asNew: true);
    } else if (action == TransactionAction.delete) {
      await deleteWithConfirm(context, ref, transaction);
    }
  }

  /// 二次确认后删除一笔账单，并刷新统计/预算计数。
  ///
  /// 副作用与列表左滑删除（`transaction_list.dart` 的 Dismissible.onDismissed）
  /// **完全一致**：counts 失效 + stats/budget 刷新计数 + `PostProcessor.sync`，
  /// 保证两条删除路径结果一致，不会出现"面板删了但统计没更新"。
  static Future<void> deleteWithConfirm(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) async {
    // ⭐ 二开：追加式守卫 —— 未解锁时直接拦下（优先于二次确认）
    if (!await AppendOnlyGuard.guardDelete(context, ref)) return;
    if (!context.mounted) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: l10n.deleteConfirmTitle,
          message: l10n.deleteConfirmMessage,
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    await repo.deleteTransaction(transaction.id);

    if (!context.mounted) return;
    ref.invalidate(countsForLedgerProvider(ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    ref.read(budgetRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: ledgerId);
    if (context.mounted) showToast(context, l10n.commonDeleted);
  }
}