/// skill 定义的数据模型 —— 与 assets/skill/skill.json 一一对应。
///
/// 设计目标：**业务规则只存在于 JSON 里**，Dart 侧只负责解析与执行。
/// 这样 skill 可以整体导出、被 AI 阅读、移植到其他平台。
library;

/// 商户规则（有序，首个命中即止）
class MerchantRule {
  final String pattern;
  final String? category;
  final String? sub;
  final bool manual;
  final String? reason;

  const MerchantRule({
    required this.pattern,
    this.category,
    this.sub,
    this.manual = false,
    this.reason,
  });

  factory MerchantRule.fromJson(Map<String, dynamic> j) => MerchantRule(
        pattern: j['pattern'] as String? ?? '',
        category: j['category'] as String?,
        sub: j['sub'] as String?,
        manual: j['manual'] as bool? ?? false,
        reason: j['reason'] as String?,
      );

  bool get isValid => pattern.isNotEmpty;
}

/// 需确认规则
class NeedConfirmRule {
  final String pattern;
  final String type; // question | screenshot
  final String? hint;

  const NeedConfirmRule({required this.pattern, required this.type, this.hint});

  factory NeedConfirmRule.fromJson(Map<String, dynamic> j) => NeedConfirmRule(
        pattern: j['pattern'] as String? ?? '',
        type: j['type'] as String? ?? 'question',
        hint: j['hint'] as String?,
      );
}

/// MANUAL 金额拆分规则
class ManualSplitRule {
  final String pattern;
  final double fixedAmount;
  final String fixedCategory;
  final String? fixedSub;
  final String restCategory;
  final String? restSub;
  final String? note;

  const ManualSplitRule({
    required this.pattern,
    required this.fixedAmount,
    required this.fixedCategory,
    this.fixedSub,
    required this.restCategory,
    this.restSub,
    this.note,
  });

  factory ManualSplitRule.fromJson(Map<String, dynamic> j) {
    final fixed = (j['fixed'] as Map?)?.cast<String, dynamic>() ?? {};
    final rest = (j['rest'] as Map?)?.cast<String, dynamic>() ?? {};
    return ManualSplitRule(
      pattern: j['pattern'] as String? ?? '',
      fixedAmount: (fixed['amount'] as num?)?.toDouble() ?? 0,
      fixedCategory: fixed['category'] as String? ?? '',
      fixedSub: fixed['sub'] as String?,
      restCategory: rest['category'] as String? ?? '',
      restSub: rest['sub'] as String?,
      note: j['note'] as String?,
    );
  }
}

/// 特殊规则
class SpecialRules {
  final List<String> refundKeywords;
  final bool negativeAmountIsIncome;
  final bool refundKeepsOriginalCategory;
  final bool fullRefundOffsetEnabled;
  final int fullRefundOffsetWindowDays;

  const SpecialRules({
    this.refundKeywords = const [],
    this.negativeAmountIsIncome = true,
    this.refundKeepsOriginalCategory = true,
    this.fullRefundOffsetEnabled = false,
    this.fullRefundOffsetWindowDays = 3,
  });

  factory SpecialRules.fromJson(Map<String, dynamic> j) {
    final off = (j['fullRefundOffset'] as Map?)?.cast<String, dynamic>() ?? {};
    return SpecialRules(
      refundKeywords:
          (j['refundKeywords'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      negativeAmountIsIncome: j['negativeAmountIsIncome'] as bool? ?? true,
      refundKeepsOriginalCategory:
          j['refundKeepsOriginalCategory'] as bool? ?? true,
      fullRefundOffsetEnabled: off['enabled'] as bool? ?? false,
      fullRefundOffsetWindowDays: (off['windowDays'] as num?)?.toInt() ?? 3,
    );
  }
}

/// skill 全量定义
class SkillDefinition {
  final int schemaVersion;
  final String name;
  final Map<String, List<String>> categories;
  final List<MerchantRule> merchantRules;
  final List<MerchantRule> platformDefaults;
  final List<NeedConfirmRule> needConfirm;
  final List<String> needConfirmExceptions;
  final List<ManualSplitRule> manualSplits;
  final Map<String, List<String>> keywordHints;
  final SpecialRules specialRules;
  final Map<String, dynamic> flow;
  final String defaultAccount;

  const SkillDefinition({
    required this.schemaVersion,
    required this.name,
    required this.categories,
    required this.merchantRules,
    required this.platformDefaults,
    required this.needConfirm,
    required this.needConfirmExceptions,
    required this.manualSplits,
    required this.keywordHints,
    required this.specialRules,
    required this.flow,
    required this.defaultAccount,
  });

  factory SkillDefinition.fromJson(Map<String, dynamic> j) {
    Map<String, List<String>> strListMap(dynamic v) {
      final out = <String, List<String>>{};
      if (v is Map) {
        v.forEach((k, val) {
          out[k.toString()] =
              (val as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        });
      }
      return out;
    }

    List<MerchantRule> rules(dynamic v) =>
        (v as List?)?.map((e) => MerchantRule.fromJson((e as Map).cast<String, dynamic>())).toList() ??
        <MerchantRule>[];

    final accounts = (j['accounts'] as Map?)?.cast<String, dynamic>() ?? {};

    return SkillDefinition(
      schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
      name: j['name'] as String? ?? 'skill',
      categories: strListMap(j['categories']),
      merchantRules: rules(j['merchantRules']),
      platformDefaults: rules(j['platformDefaults']),
      needConfirm: (j['needConfirm'] as List?)
              ?.map((e) => NeedConfirmRule.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          <NeedConfirmRule>[],
      needConfirmExceptions: (j['needConfirmExceptions'] as List?)
              ?.map((e) {
                if (e is Map) return e['pattern']?.toString() ?? '';
                return e.toString();
              })
              .where((e) => e.isNotEmpty)
              .toList() ??
          <String>[],
      manualSplits: (j['manualSplits'] as List?)
              ?.map((e) => ManualSplitRule.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          <ManualSplitRule>[],
      keywordHints: strListMap(j['keywordHints']),
      specialRules: SpecialRules.fromJson(
          (j['specialRules'] as Map?)?.cast<String, dynamic>() ?? {}),
      flow: (j['flow'] as Map?)?.cast<String, dynamic>() ?? {},
      defaultAccount: accounts['default']?.toString() ?? '',
    );
  }

  /// 该 skill 声明的合法分类组合是否包含 (category, sub)
  bool isLegal(String category, String? sub) {
    final subs = categories[category];
    if (subs == null) return false;
    return subs.contains(sub ?? '');
  }
}
