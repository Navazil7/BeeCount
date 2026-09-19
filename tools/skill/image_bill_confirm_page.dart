import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/core/bill_info.dart';
import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/category_matcher.dart';
import '../../data/repositories/base_repository.dart';
import '../../services/skill/skill_data.dart';
import '../../services/skill/skill_matcher.dart';
import '../../providers/ai_chat_providers.dart';
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

  /// 每笔分类的来源：ai / rule / manual / none（用于界面提示）
  late List<String> _categorySource;

  /// 每笔的特殊标记（来自 skill 的特殊规则）：需确认 / 可抵消 / 可能重复 / 退款
  late List<Set<String>> _flags;

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
    _categorySource = List<String>.filled(_bills.length, 'none');
    _flags = List<Set<String>>.generate(_bills.length, (_) => <String>{});
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

      // 叶子分类（规则字典按叶子名做键）
      final leaves = categories
          .where((c) => !categories.any((x) => x.parentId == c.id))
          .toList();

      for (var i = 0; i < _bills.length; i++) {
        final b = _bills[i];

        // ① 先按 AI 给的分类名找（完全匹配）
        final catName = b.category?.trim();
        if (catName != null && catName.isNotEmpty) {
          final hit = catByName[catName];
          if (hit != null) {
            _categoryIds[i] = hit.id;
            _categorySource[i] = 'ai';
          }
        }

        // ② AI 没匹配上 → 跑用户规则字典（商户→分类，patch_rules.js 装入）
        if (_categoryIds[i] == null) {
          final merchant = (b.note ?? '').trim();
          if (merchant.isNotEmpty) {
            final ruleId = CategoryMatcher.smartMatch(
              merchant: merchant,
              fullText: merchant,
              categories: leaves,
            );
            if (ruleId != null) {
              _categoryIds[i] = ruleId;
              _categorySource[i] = 'rule';
            }
          }
        }

        // 账户
        final accName = b.account?.trim();
        if (accName != null && accName.isNotEmpty) {
          _accountIds[i] = accByName[accName]?.id;
        }
      }
    } catch (_) {
      // 解析失败不阻塞确认流程，用户手动选即可
    }
    await _applySpecialRules(repo);
    if (mounted) setState(() => _loading = false);
  }

  /// 应用 skill 的特殊规则（参数全部来自 skill_data.dart，代码只是解释器）：
  ///  ① 退款/退货 → 类型改「收入」（分类保持）
  ///  ② 需确认清单（question 型）→ 打标记，保存前一次性询问
  ///  ③ 全额退款配对 → 同商户且金额一致的一出一入，两笔都标「可抵消」并默认不记
  ///  ④ 去重 → 与库中已有交易比对（±N 天、同金额、同类型），标「可能重复」并默认不记
  Future<void> _applySpecialRules(BaseRepository repo) async {
    final skill = SkillData.definition;
    final sr = skill.specialRules;

    // ① 退款/退货 → 收入；② 需确认清单
    for (var i = 0; i < _bills.length; i++) {
      final note = (_bills[i].note ?? '').trim();
      if (note.isEmpty) continue;
      if (sr.refundKeywords.any((k) => note.contains(k))) {
        if (_bills[i].type != BillType.income) {
          _bills[i] = _bills[i].copyWith(type: BillType.income);
        }
        _flags[i].add('退款');
      }
      if (SkillMatcher.matchNeedConfirm(skill, note) != null) {
        _flags[i].add('需确认');
      }
    }

    // ③ 退款配对（skill：退款应与前面那笔正向记录互相抵消）
    //    条件：金额一致 + 一出一入 + 时间在窗口内；同名商户优先，其次取时间最近的。
    //    找不到对应正向记录 → 【必须明确问用户】（不猜、不乱归分类）。
    final win = (skill.flow['dedupeWindowDays'] as int?) ?? 3;
    bool isRefundRow(int i) {
      final note = _bills[i].note ?? '';
      return _bills[i].type == BillType.income &&
          sr.refundKeywords.any((k) => note.contains(k));
    }

    String baseName(String x) => x
        .replaceAll(RegExp(r'[-—]?(退款|退货|refund)', caseSensitive: false), '')
        .replaceAll(RegExp(r'[-—\s]+$'), '')
        .trim();

    for (var i = 0; i < _bills.length; i++) {
      if (!isRefundRow(i)) continue;
      final amt = (_bills[i].amount ?? 0).abs();
      if (amt == 0) continue;
      final ti = _bills[i].time;
      final ni = baseName(_bills[i].note ?? '');

      int? bestJ;
      var bestName = false;
      var bestGap = 1 << 30;
      for (var j = 0; j < _bills.length; j++) {
        if (j == i) continue;
        if (_bills[j].type != BillType.expense) continue;
        if (((_bills[j].amount ?? 0).abs() - amt).abs() > 0.001) continue;
        final tj = _bills[j].time;
        final gap = (ti != null && tj != null)
            ? ti.difference(tj).inMinutes.abs()
            : 0;
        if (gap > win * 24 * 60) continue;
        final nameHit = ni.isNotEmpty && ni == baseName(_bills[j].note ?? '');
        // 同名优先；否则取时间最近
        final better = bestJ == null ||
            (nameHit && !bestName) ||
            (nameHit == bestName && gap < bestGap);
        if (better) {
          bestJ = j;
          bestName = nameHit;
          bestGap = gap;
        }
      }

      if (bestJ != null) {
        _flags[i].add('可抵消');
        _flags[bestJ].add('可抵消');
        _checked[i] = false; // skill：两笔均不记录（可手动勾回）
        _checked[bestJ] = false;
      } else {
        // 配不上正向记录 → 必须让用户明确处理
        _flags[i].add('需确认');
      }
    }
    // ④ 去重：与已有交易比对
    try {
      for (var i = 0; i < _bills.length; i++) {
        final t = _bills[i].time;
        final amt = (_bills[i].amount ?? 0).abs();
        if (t == null || amt == 0) continue;
        final rows = await repo.getTransactionsByLedgerInRange(
          ledgerId: widget.ledgerId,
          start: t.subtract(Duration(days: win)),
          end: t.add(Duration(days: win)),
        );
        final wantType =
            _bills[i].type == BillType.income ? 'income' : 'expense';
        final dup = (rows as List).any((tx) =>
            (tx.amount as num).abs().toDouble() == amt && tx.type == wantType);
        if (dup) {
          _flags[i].add('可能重复');
          _checked[i] = false; // 默认不重复入账（可勾回）
        }
      }
    } catch (_) {
      // 去重失败不影响主流程
    }
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
        _categorySource[index] = 'manual';
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
    // 【skill 需确认清单】保存前把待确认项一次性列出
    final toConfirm = <int>[];
    for (var i = 0; i < _bills.length; i++) {
      if (_checked[i] && _flags[i].contains('需确认')) toConfirm.add(i);
    }
    if (toConfirm.isNotEmpty) {
      final shown = toConfirm.take(3).map((i) {
        final b = _bills[i];
        final amt = b.amount?.toStringAsFixed(2) ?? '';
        return '· ' + (b.note ?? '') + '  ' + amt;
      }).join('\n');
      final more = toConfirm.length > 3
          ? '…共 ' + toConfirm.length.toString() + ' 笔\n\n'
          : '';
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('以下账单需要你确认用途'),
          content: Text(shown +
              '\n\n' +
              more +
              '这些商户（如亲属卡/群红包）无法自动判断分类。\n'
              '可返回逐笔选择分类，或直接保存（将记为「其它」）。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('返回逐笔处理'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('继续保存'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }

    // 有未选分类时先确认一次（这些会按兜底"其它"入账）
    if (_missingCategoryCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('还有未选分类的账单'),
          content: Text('有 ${_missingCategoryCount} 笔没有选择分类，保存后将按兜底分类「其它」入账。\n\n是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('返回修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('仍然保存'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }

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
    final canSave = !_saving && !_loading;

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
    final src = _categorySource[i];
    final catName = catId == null
        ? (bill.category?.trim().isNotEmpty == true
            ? '⚠ ${bill.category}（未匹配，请选择）'
            : '⚠ 请选择分类')
        : (CategoryUtils.getDisplayName(_categoryNames[catId], context,
                kind: isIncome ? 'income' : 'expense') +
            (src == 'rule' ? '  · 规则' : src == 'ai' ? '  · AI' : ''));
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
                  if (_flags[i].isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        children: _flags[i].map((f) {
                          final isConfirm = f == '需确认';
                          final isOffset = f == '可抵消';
                          final isDup = f == '可能重复';
                          final color = isConfirm
                              ? Colors.orange
                              : isOffset
                                  ? Colors.purple
                                  : isDup
                                      ? Colors.red
                                      : Colors.blue;
                          final label = isConfirm
                              ? '❓需确认'
                              : isOffset
                                  ? '⇄可抵消'
                                  : isDup
                                      ? '⚠可能重复'
                                      : f;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(label,
                                style: const TextStyle(fontSize: 11)),
                          );
                        }).toList(),
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
                        '还有 $missing 笔未选分类，保存将记为「其它」（可直接保存）',
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
