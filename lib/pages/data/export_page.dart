import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/db.dart';
import '../../widgets/ui/ui.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../utils/ui_scale_extensions.dart';

/// ⭐ 二开：导出页改为**按年 / 按月**选择范围。
///
/// 动机：这份 CSV 是要导入钱迹的，而钱迹的导入去重是**文件级**
/// （「目前不允许同一个文件导入多次」），所以「一个月一个文件」
/// 天然等于「钱迹里一个导入批次」，可以按批整批回滚。
///
/// 同时刻意**不做任何「已导出」标记**：重复导出是无害的
/// （同步侧还会用钱迹自己的导出做行级去重兜底），
/// 而标记一旦落到明细列表上就会污染界面——不值得。
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});
  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  bool exporting = false;
  double progress = 0;
  String? savedPath;

  /// 是否已加载完按月统计
  bool _countsLoaded = false;
  /// 'yyyy-MM' -> 该月账单条数
  Map<String, int> _counts = <String, int>{};
  /// 有数据的年份，倒序
  List<int> _years = <int>[];
  int? _selectedYear;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  String _ymKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  int _countOf(int year, int month) => _counts[_ymKey(year, month)] ?? 0;

  Future<void> _loadCounts() async {
    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final list =
          await repo.transactionsWithCategoryAll(ledgerId: ledgerId).first;
      final counts = <String, int>{};
      final years = <int>{};
      for (final x in list) {
        final local = x.t.happenedAt.toLocal();
        final key = _ymKey(local.year, local.month);
        counts[key] = (counts[key] ?? 0) + 1;
        years.add(local.year);
      }
      if (!mounted) return;
      final now = DateTime.now();
      final yearList = years.toList()..sort((a, b) => b.compareTo(a));
      // 默认选中「当前月」；若当前月所在年份没有数据，退到最新有数据的年份
      var year = now.year;
      if (!years.contains(year)) {
        year = yearList.isNotEmpty ? yearList.first : now.year;
      }
      if (!yearList.contains(year)) yearList.insert(0, year);
      setState(() {
        _counts = counts;
        _years = yearList;
        _selectedYear = year;
        _selectedMonth = now.month;
        _countsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _countsLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(repositoryProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final year = _selectedYear;
    final month = _selectedMonth;
    final monthCount =
        (year == null || month == null) ? 0 : _countOf(year, month);
    final canExport = monthCount > 0 && !exporting;

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(title: l10n.exportTitle, showBack: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.exportDescription),
                  SizedBox(height: 12.0.scaled(context, ref)),

                  // ---- 年份 ----
                  Text(
                    l10n.exportRangeYear,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_countsLoaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final y in _years)
                          ChoiceChip(
                            label: Text('$y'),
                            selected: y == year,
                            onSelected: (_) => setState(() {
                              _selectedYear = y;
                            }),
                          ),
                      ],
                    ),

                  SizedBox(height: 16.0.scaled(context, ref)),

                  // ---- 月份 ----
                  Text(
                    l10n.exportRangeMonth,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_countsLoaded && year != null)
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.9,
                      children: [
                        for (var m = 1; m <= 12; m++)
                          _MonthCell(
                            month: m,
                            count: _countOf(year, m),
                            selected: m == month,
                            onTap: () => setState(() => _selectedMonth = m),
                          ),
                      ],
                    ),

                  SizedBox(height: 16.0.scaled(context, ref)),

                  // ---- 当前选择摘要 ----
                  Text(
                    (year == null || month == null)
                        ? ''
                        : (monthCount > 0
                            ? l10n.exportMonthSummary(
                                '$year', '$month', '$monthCount')
                            : l10n.exportNoBillsInMonth),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: monthCount > 0
                          ? BeeTokens.textPrimary(context)
                          : BeeTokens.textTertiary(context),
                    ),
                  ),

                  SizedBox(height: 12.0.scaled(context, ref)),

                  FilledButton.icon(
                    onPressed: canExport
                        ? () => _export(repo, ledgerId, year!, month!)
                        : null,
                    icon: const Icon(Icons.save_alt_outlined),
                    label: Text(Platform.isIOS
                        ? l10n.exportButtonIOS
                        : l10n.exportButtonAndroid),
                  ),

                  const SizedBox(height: 16),
                  if (exporting)
                    Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LinearProgressIndicator(
                              value: progress == 0 ? null : progress),
                        ),
                      ],
                    ),
                  if (savedPath != null) ...[
                    const SizedBox(height: 12),
                    Text(l10n.exportSavedTo(savedPath!)),
                  ],
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _export(
    BaseRepository repo,
    int ledgerId,
    int year,
    int month,
  ) async {
    try {
      setState(() {
        exporting = true;
        progress = 0;
        savedPath = null;
      });
      String directory;
      bool shareAfter = false;
      if (Platform.isIOS) {
        // iOS: 写入应用文档目录，然后使用系统分享
        final docDir = await getApplicationDocumentsDirectory();
        directory = docDir.path;
        shareAfter = true;
      } else {
        // Android: 直接保存到公共 Download/BeeCount 目录
        const downloadPath = '/storage/emulated/0/Download/BeeCount';
        final dir = Directory(downloadPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        directory = downloadPath;
      }

      // 获取交易和分类数据（本次只导出所选年月）
      final allWithCategory =
          await repo.transactionsWithCategoryAll(ledgerId: ledgerId).first;
      final transactionsWithCategory = allWithCategory.where((x) {
        final local = x.t.happenedAt.toLocal();
        return local.year == year && local.month == month;
      }).toList();
      final total = transactionsWithCategory.length;
      final rows = <List<dynamic>>[];
      final l10n = AppLocalizations.of(context);
      rows.add([
        l10n.exportCsvHeaderType,
        l10n.exportCsvHeaderCategory,
        l10n.exportCsvHeaderSubCategory, // 二级分类名称
        l10n.exportCsvHeaderAmount,
        l10n.exportCsvHeaderCurrency, // v30 多币种:交易原币种(反馈10)
        l10n.exportCsvHeaderAccount,
        l10n.exportCsvHeaderFromAccount, // 转出账户
        l10n.exportCsvHeaderToAccount,   // 转入账户
        l10n.exportCsvHeaderNote,
        l10n.exportCsvHeaderTime,
        l10n.exportCsvHeaderTags,
        l10n.exportCsvHeaderAttachments, // 附件文件名（逗号分隔）
      ]);

      // 批量获取所有交易的标签
      final transactionIds =
          transactionsWithCategory.map((tx) => tx.t.id).toList();
      final tagsMap = await repo.getTagsForTransactions(transactionIds);

      // 批量获取所有交易的附件
      final attachmentsMap =
          await repo.getAttachmentsForTransactions(transactionIds);

      // 缓存所有账户信息，避免重复查询
      final allAccounts = await repo.getAllAccounts();
      final accountMap = {for (var acc in allAccounts) acc.id: acc};

      // v30 多币种:账本本位币(currencyCode 为 NULL 的历史行按账户/本位币兜底,
      // 与统计读取端同语义 —— 导出自包含,回导不丢币种)
      final ledgerData = await repo.getLedgerById(ledgerId);
      final ledgerBase =
          ((ledgerData?.currency.isNotEmpty ?? false) ? ledgerData!.currency : 'CNY')
              .toUpperCase();

      // 缓存所有分类信息（包括父分类）
      final incomeCategories = await repo.getTopLevelCategories('income');
      final expenseCategories = await repo.getTopLevelCategories('expense');
      final allCategories = <int, Category>{};
      for (final cat in [...incomeCategories, ...expenseCategories]) {
        allCategories[cat.id] = cat;
        // 获取子分类
        final subCategories = await repo.getSubCategories(cat.id);
        for (final subCat in subCategories) {
          allCategories[subCat.id] = subCat;
        }
      }

      for (int i = 0; i < transactionsWithCategory.length; i++) {
        final txWithCat = transactionsWithCategory[i];
        final t = txWithCat.t;
        final c = txWithCat.category;
        final a = t.accountId != null ? accountMap[t.accountId] : null;
        // 使用完整的时间格式，包含年份和秒，添加前导空格增加列宽
        final timeStr = () {
          try {
            final localTime = t.happenedAt.toLocal();
            // 完整时间格式: YYYY-MM-DD HH:mm:ss，前面添加空格增加列宽
            return '  ${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}  ';
          } catch (e) {
            return '';
          }
        }();
        final typeStr = _getTypeDisplayName(t.type);

        // 对于转账类型，需要特殊处理账户信息
        String accountName;
        String fromAccountName;
        String toAccountName;
        String categoryName;
        String subCategoryName;

        if (t.type == 'transfer') {
          // 转账记录：账户列留空，填充转出账户和转入账户
          accountName = '';
          final fromAccount = accountMap[t.accountId];
          final toAccount = accountMap[t.toAccountId];
          fromAccountName = fromAccount?.name ?? '';
          toAccountName = toAccount?.name ?? '';
          categoryName = ''; // 转账没有分类
          subCategoryName = '';
        } else {
          // 收入或支出：正常填充账户列，转出转入账户留空
          accountName = a?.name ?? '';
          fromAccountName = '';
          toAccountName = '';

          // 处理分类信息
          if (c != null) {
            if (c.level == 2 && c.parentId != null) {
              // 二级分类：分类列填一级分类名称，二级分类列填当前分类名称
              final parentCategory = allCategories[c.parentId];
              categoryName =
                  CategoryUtils.getDisplayName(parentCategory?.name, context);
              subCategoryName = CategoryUtils.getDisplayName(c.name, context);
            } else {
              // 一级分类：分类列填当前分类，二级分类列留空
              categoryName = CategoryUtils.getDisplayName(c.name, context);
              subCategoryName = '';
            }
          } else {
            categoryName = '';
            subCategoryName = '';
          }
        }

        // 获取该交易的标签，用逗号分隔
        final transactionTags = tagsMap[t.id] ?? [];
        final tagsStr = transactionTags.map((tag) => tag.name).join(',');

        // 获取该交易的附件，用逗号分隔文件名
        final transactionAttachments = attachmentsMap[t.id] ?? [];
        final attachmentsStr =
            transactionAttachments.map((a) => a.fileName).join(',');

        final currencyStr = (t.currencyCode ??
                (a?.currency.isNotEmpty ?? false ? a!.currency : null) ??
                ledgerBase)
            .toUpperCase();

        rows.add([
          typeStr,
          categoryName,
          subCategoryName,
          t.amount.toStringAsFixed(2),
          currencyStr,
          accountName,
          fromAccountName,
          toAccountName,
          t.note ?? '',
          timeStr,
          tagsStr,
          attachmentsStr,
        ]);
        if (i % 50 == 0) {
          setState(() => progress = (i + 1) / (total == 0 ? 1 : total));
        }
      }

      final csvStr = const ListToCsvConverter(eol: '\n').convert(rows);
      // ⭐ 二开：按月命名 —— 一个月一个文件 == 钱迹里一个导入批次（可整批回滚）
      final mm = month.toString().padLeft(2, '0');
      final path = p.join(directory, 'beecount_$year-$mm.csv');

      // 添加UTF-8 BOM标记，确保Excel正确识别中文编码
      const utf8Bom = '\uFEFF';
      await File(path).writeAsString(utf8Bom + csvStr,
          encoding: Encoding.getByName('utf-8')!);
      setState(() {
        savedPath = path;
        exporting = false;
        progress = 1;
      });
      if (!mounted) return;
      final l10nDialog = AppLocalizations.of(context);
      if (shareAfter) {
        // 触发分享面板
        await Share.shareXFiles([XFile(path)], text: l10nDialog.exportShareText);
        await AppDialog.info(context,
            title: l10nDialog.exportSuccessTitle,
            message: l10nDialog.exportSuccessMessageIOS(path));
      } else {
        await AppDialog.info(context,
            title: l10nDialog.exportSuccessTitle,
            message: l10nDialog.exportSuccessMessageAndroid(path));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => exporting = false);
      final l10nError = AppLocalizations.of(context);
      await AppDialog.error(context,
          title: l10nError.exportFailedTitle, message: e.toString());
    }
  }

  /// 将英文类型转换为中文显示名称
  String _getTypeDisplayName(String type) {
    final l10nType = AppLocalizations.of(context);
    switch (type) {
      case 'income':
        return l10nType.exportTypeIncome;
      case 'expense':
        return l10nType.exportTypeExpense;
      case 'transfer':
        return l10nType.exportTypeTransfer;
      default:
        return type; // 兜底返回原始值
    }
  }
}

/// 月份格子：显示月份 + 该月条数；无数据时淡显但仍可选中。
class _MonthCell extends ConsumerWidget {
  const _MonthCell({
    required this.month,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int month;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = ref.watch(primaryColorProvider);
    final empty = count == 0;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.16)
              : BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? primary : BeeTokens.divider(context),
            width: selected ? 1.4 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$month 月',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: empty
                    ? BeeTokens.textTertiary(context)
                    : BeeTokens.textPrimary(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: empty
                    ? BeeTokens.textTertiary(context)
                    : BeeTokens.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
