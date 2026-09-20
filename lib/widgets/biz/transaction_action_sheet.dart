import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import 'format_money.dart';

/// 单笔账单操作面板里可选的动作。
enum TransactionAction { edit, copy, delete }

/// ⭐ 二开：点击一笔账单后弹出的**底部操作面板**（对标钱迹的「账单预览」浮层）。
///
/// ## 为什么要改
///
/// 上游行为是点击交易行 → `TransactionEditUtils.editTransaction` →
/// **整页 push** 到 `TransactionEditorPage`。这带来两个问题：
///
/// 1. 用户只想"看一眼"或"删掉"，却被迫进入一个带键盘、带分类网格的完整编辑器；
/// 2. 编辑器里**没有任何删除入口**（`transaction_editor_page.dart` 全文无 delete），
///    删除只能靠列表左滑 —— 而左滑同时是"返回"手势的重灾区。
///
/// 钱迹的做法是：点击后拉出一个浮层，上方是操作（编辑/复制/删除），
/// 下方是这笔账的摘要信息。本组件实现同样的形态。
///
/// ## 只负责"选动作"
///
/// 面板本身**不执行**任何导航或写库：它 pop 出 [TransactionAction]，
/// 由 `TransactionEditUtils.showActions` 在**调用方 context** 上执行 ——
/// 避免在已关闭的 sheet context 上做 Navigator.pop / showDialog。
class TransactionActionSheet extends ConsumerStatefulWidget {
  final Transaction transaction;
  final Category? category;

  const TransactionActionSheet({
    super.key,
    required this.transaction,
    this.category,
  });

  static Future<TransactionAction?> show(
    BuildContext context, {
    required Transaction transaction,
    Category? category,
  }) {
    return showModalBottomSheet<TransactionAction>(
      context: context,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TransactionActionSheet(
        transaction: transaction,
        category: category,
      ),
    );
  }

  @override
  ConsumerState<TransactionActionSheet> createState() =>
      _TransactionActionSheetState();
}

class _TransactionActionSheetState
    extends ConsumerState<TransactionActionSheet> {
  List<Tag> _tags = const [];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final repo = ref.read(repositoryProvider);
      final tags = await repo.getTagsForTransaction(widget.transaction.id);
      if (mounted) setState(() => _tags = tags);
    } catch (_) {
      // 标签只是附加信息，取不到就不显示，不影响面板主要功能
    }
  }

  void _pick(TransactionAction action) => Navigator.of(context).pop(action);

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final l10n = AppLocalizations.of(context);
    final isTransfer = t.type == 'transfer';
    final isAdjustment = t.type == 'adjustment';

    final Color amountColor;
    if (t.type == 'income') {
      amountColor = BeeTokens.incomeColor(context, ref);
    } else if (t.type == 'expense') {
      amountColor = BeeTokens.expenseColor(context, ref);
    } else {
      amountColor = BeeTokens.textPrimary(context);
    }
    final sign = t.type == 'expense' ? '-' : (t.type == 'income' ? '+' : '');

    final categoryName = isAdjustment
        ? l10n.adjustmentTransaction
        : (widget.category?.name ?? '');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽条
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: BeeTokens.textTertiary(context)
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 金额
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                '$sign${formatMoneyCompact(t.amount.abs())}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                ),
              ),
            ),

            // 操作按钮行
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.edit_outlined,
                      label: l10n.commonEdit,
                      onTap: () => _pick(TransactionAction.edit),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.copy_outlined,
                      label: l10n.commonCopy,
                      onTap: () => _pick(TransactionAction.copy),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.delete_outline,
                      label: l10n.commonDelete,
                      danger: true,
                      onTap: () => _pick(TransactionAction.delete),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: BeeTokens.dividerStatic),
            const SizedBox(height: 4),

            // 详情
            if (!isTransfer && categoryName.isNotEmpty)
              _DetailRow(label: l10n.importFieldCategory, value: categoryName),
            _DetailRow(
              label: l10n.importFieldDate,
              value: DateFormat('yyyy-MM-dd HH:mm').format(t.happenedAt),
            ),
            if ((t.note ?? '').isNotEmpty)
              _DetailRow(
                label: l10n.importFieldNote,
                value: t.note!,
                multiline: true,
              ),
            if (_tags.isNotEmpty)
              _DetailRow(
                label: l10n.exportCsvHeaderTags,
                value: _tags.map((e) => '#${e.name}').join('  '),
                multiline: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = danger
        ? (BeeTokens.isDark(context)
            ? const Color(0xFFF87171)
            : const Color(0xFFEF4444))
        : BeeTokens.textPrimary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: BeeTokens.surfaceChip(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: tint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _DetailRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 14,
      color: BeeTokens.textSecondary(context),
    );
    final valueStyle = TextStyle(
      fontSize: 14,
      color: BeeTokens.textPrimary(context),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: multiline
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 4),
                Text(value, style: valueStyle),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: valueStyle,
                  ),
                ),
              ],
            ),
    );
  }
}
