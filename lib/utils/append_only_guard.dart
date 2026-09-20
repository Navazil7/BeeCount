import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../pages/settings/data_management_page.dart';
import '../providers/theme_providers.dart';
import '../widgets/ui/ui.dart';

/// ⭐ 二开：「只能新增」（追加式 / append-only）守卫。
///
/// 背景：本项目要把蜜蜂记账的账单同步进钱迹，而钱迹**没有任何修改/删除接口**
/// （只有 `publicapi/addbill` 新增 + 模板 CSV 导入，两者都只能追加）。
/// 因此一旦在蜜蜂里改了金额/备注，或删掉一笔，钱迹侧就会与蜜蜂永久不一致。
///
/// 结论：与其做「改/删同步」（物理上做不到），不如**在源头禁止改删**——
/// 两边都是追加式，一致性自然成立。
///
/// 开关：[allowEditHistoryProvider]，默认 **false**（关闭 = 禁止改删）。
/// 入口：「我的 → 数据管理 → 防误改」。
///
/// 注意：本守卫只在 **UI 层**生效，**刻意不动数据层**——因为云同步引擎
/// （`sync_engine_apply` / `sync_diff_service`）内部也会调用
/// `updateTransaction` / `deleteTransaction`，在数据层一刀切会把云同步搞坏。
class AppendOnlyGuard {
  const AppendOnlyGuard._();

  /// 是否已解锁（允许编辑/删除）。
  static bool isUnlocked(WidgetRef ref) => ref.read(allowEditHistoryProvider);

  /// 编辑已有账单/分类前的守卫。返回 `true` 表示放行。
  static Future<bool> guardEdit(BuildContext context, WidgetRef ref) async {
    if (isUnlocked(ref)) return true;
    await _promptBlocked(context, isDelete: false);
    return false;
  }

  /// 删除前的守卫。返回 `true` 表示放行。
  ///
  /// 注意：**不含**二次确认——放行后调用方仍应走原有的删除确认流程。
  static Future<bool> guardDelete(BuildContext context, WidgetRef ref) async {
    if (isUnlocked(ref)) return true;
    await _promptBlocked(context, isDelete: true);
    return false;
  }

  /// 弹「被拦截」提示，并提供「去设置」直达。
  static Future<void> _promptBlocked(
    BuildContext context, {
    required bool isDelete,
  }) async {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final go = await AppDialog.confirm<bool>(
          context,
          title: l10n.appendOnlyBlockedTitle,
          message: isDelete
              ? l10n.appendOnlyDeleteBlocked
              : l10n.appendOnlyEditBlocked,
          cancelLabel: l10n.commonCancel,
          okLabel: l10n.appendOnlyGoSettings,
        ) ??
        false;
    if (go && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DataManagementPage()),
      );
    }
  }
}
