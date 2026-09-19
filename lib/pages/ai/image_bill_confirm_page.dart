import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/core/bill_info.dart';
import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../utils/category_utils.dart';
import '../../widgets/biz/account_picker.dart';
import '../../widgets/biz/category_selector_dialog.dart';

/// 图片记账「确认页」—— 让用户在入库前核对/修改 AI 识别结果。
///
/// 背景：BeeCount 原生走 [ImageBillingHelper] 时是「识别 → 直接入库」，
/// 没有任何确认环节（见 lib/utils/image_billing_helper.dart）。
/// 本页把这个缺口补上：**提取与落库拆成两步**，中间插入人工确认。
///
/// 设计原则（便于与上游同步）：
/// - 不改 AI 底座、不改 BillCreationService、不走数据库迁移；
/// - 只消费已经拿到的 `List<BillInfo>`，最后调 `AiBookkeeper.persistAll` 落库；
/// - UI 复用项目自带的 CategorySelectorDialog / AccountPicker。
class ImageBillConfirmPage extends ConsumerStatefulWidget {
  const ImageBillConfirmPage({
    super.key,
    required this.bills,
    required this.ledgerId,
    required this.billingTypes,
    this.onSaved,
  });

  /// AI 提取出的账单草稿（尚未入库）
  final List<BillInfo> bills;

  final int ledgerId;

  /// 落库时要挂的 billingTypes（图片记账传 [image, ai] / [camera, ai]）
  final List<String> billingTypes;

  /// 每成功落库一笔的回调（用于挂图片附件）
  final Future<void> Function(int txId, int index)? onSaved;

  @override
  ConsumerState<ImageBillConfirmPage> createState() =>
      _ImageBillConfirmPageState();
}

class _ImageBillConfirmPageState extends ConsumerState<ImageBillConfirmPage> {
  late List<BillInfo> _bills;

  /// 勾选状态（默认全选）
  late List<bool> _checked;

  /// 每笔已解析到的分类 id（null = AI 给的名字没匹配上，需用户手动选）
  late List<int?> _categoryIds;

  /// 每笔选择的账户 id
  late List<int?> _accountIds;

  /// 分类 id → 名称
  Map<int, String> _categoryNames = {};

  /// 账户 id → 名称
  Map<int, String> _accountNames = {};

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bills = List<BillInfo>.from(widget.bills);
    _checked = List<bool>.filled(_bills.length, true);
    _categoryIds = List<int?>.filled(_bills.length, null);
    _accountIds = List<int?>.filled(_bills.length, null);
    _resolveDefaults();
  }

  /// 预解析：把 AI 给的分类名/账户名解析成 id，尽量让用户少点几下
  Future<void> _resolveDefaults() async {
    final repo = ref.read(repositoryProvider);
    try {
      final categories = await repo.getAllCategoriesIncludingShared();
      final accounts = await repo.getAvailableAccountsForLedger(widget.ledgerId);

      final catByName = <String, Category>{};
      for (final c in categories) {
        catByName.putIfAbsent(c.name, () => c);
        _categoryNames[c.id] = c.name;
      }
      final accByName = <String, Account>{};
      for (final a in accounts) {
        accByName.putIfAbsent(a.name, () => a);
        _accountNames[a.id] = a.name;
      }

      for (var i = 0; i < _bills.length; i++) {
        final b = _bills[i];
        final catName = b.category?.trim();
        if (catName != null && catName.isNotEmpty) {
          _categoryIds[i] = catByName[catName]?.id;
        }
        final accName = b.account?.trim();
        if (accName != null && accName.isNotEmpty) {
          _accountIds[i] = accByName[accName]?.id;
        }
      }
    } catch (_) {
      // 解析失败不阻塞确认流程，用户手动选即可
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 勾选项里还有几笔没定分类
  int get _missingCategoryCount {
    var n = 0;
    for (var i = 0; i < _bills.length; i++) {
      if (_checked[i] && _categoryIds[i] == null) n++;
    }
    return n;
  }

  int get _selectedCount => _checked.where((e) => e).length;

  double get _selectedTotal {
    var sum = 0.0;
    for (var i = 0; i < _bills.length; i++) {
      if (_checked[i]) sum += (_bills[i].amount ?? 0).abs();
    }
    return sum;
  }

  Future<void> _pickCategory(int index) async {
    final bill = _bills[index];
    final type = bill.type == BillType.income ? 'income' : 'expense';
    final picked = await showCategorySelector(
      context,
      type: type,
      ledgerId: widget.ledgerId,
      currentCategoryId: _categoryIds[index],
    );
    if (picked != null && mounted) {
      setState(() {
        _categoryIds[index] = picked.id;
        _categoryNames[picked.id] = picked.name;
        _bills[index] = bill.copyWith(category: picked.name);
      });
    }
  }

  Future<void> _pickAccount(int index) async {
    final id = await AccountPicker.show(
      context,
      selectedAccountId: _accountIds[index],
    );
    if (id != null && mounted) {
      setState(() => _accountIds[index] = id);
    }
  }

  void _toggleType(int index) {
    final bill = _bills[index];
    final next = bill.type == BillType.income
        ? BillType.expense
        : BillType.income;
    // 类型切换后原来的分类可能不合法（收入分类 ≠ 支出分类），清掉让用户重选
    setState(() {
      _bills[index] = bill.copyWith(type: next);
      _categoryIds[index] = null;
    });
  }

  Future<void> _onConfirm() async {
    final selected = <BillInfo>[];
    for (var i = 0; i < _bills.length; i++) {
      if (!_checked[i]) continue;
      selected.add(_bills[i].copyWith(
        ledgerId: widget.ledgerId,
      ));
    }
    if (selected.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await ref.read(aiBookkeeperProvider).persistAll(
            bills: selected,
            ledgerId: widget.ledgerId,
            billingTypes: widget.billingTypes,
            l10n: AppLocalizations.of(context),
            onSaved: widget.onSaved,
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = !_saving && !_loading && _missingCategoryCount == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('确认账单（${_bills.length} 笔）'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildBanner(theme),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: _bills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildBillCard(theme, i),
                  ),
                ),
                _buildBottomBar(theme, canSave),
              ],
            ),
    );
  }

  Widget _buildBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'AI 识别结果，请核对后再保存。取消勾选可丢弃某笔。',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillCard(ThemeData theme, int i) {
    final bill = _bills[i];
    final isIncome = bill.type == BillType.income;
    final amount = (bill.amount ?? 0).abs();
    final catId = _categoryIds[i];
    final catName = catId == null
        ? (bill.category?.trim().isNotEmpty == true
            ? '⚠ ${bill.category}（未匹配）'
            : '⚠ 请选择分类')
        : (CategoryUtils.getDisplayName(_categoryNames[catId], context,
            kind: isIncome ? 'income' : 'expense'));
    final accId = _accountIds[i];
    final accName = accId == null ? '未选择账户' : (_accountNames[accId] ?? '未选择账户');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _checked[i],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _checked[i] = v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：类型（可点切换） + 金额
                  Row(
                    children: [
                      InkWell(
                        onTap: _saving ? null : () => _toggleType(i),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isIncome
                                ? Colors.green.withOpacity(0.12)
                                : Colors.red.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isIncome ? '收入' : '支出',
                            style: TextStyle(
                              fontSize: 11,
                              color: isIncome ? Colors.green[700] : Colors.red[700],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${isIncome ? '+' : '-'}${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isIncome ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // 第二行：时间 + 备注
                  Text(
                    _fmtTime(bill.time),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if ((bill.note ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        bill.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  const SizedBox(height: 6),
                  // 第三行：分类 / 账户 可点编辑
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _editableChip(
                        icon: Icons.local_offer_outlined,
                        label: catName,
                        warn: catId == null,
                        onTap: _saving ? null : () => _pickCategory(i),
                      ),
                      _editableChip(
                        icon: Icons.account_balance_wallet_outlined,
                        label: accName,
                        warn: accId == null,
                        onTap: _saving ? null : () => _pickAccount(i),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editableChip({
    required IconData icon,
    required String label,
    required bool warn,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: warn ? Colors.orange[800] : Colors.grey[700]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: warn ? Colors.orange[900] : Colors.grey[800],
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.edit, size: 12, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, bool canSave) {
    final missing = _missingCategoryCount;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 15, color: Colors.orange[800]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '还有 $missing 笔未选择分类，请先补全',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已选 $_selectedCount / ${_bills.length} 笔 · 合计 ${_selectedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(null),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: canSave ? _onConfirm : null,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存所选'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}/${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
  }
}
