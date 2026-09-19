import '../../data/db.dart';
import 'skill_definition.dart';

/// skill 的**执行器** —— 只负责解释 [SkillDefinition]，不含任何业务规则。
///
/// 匹配顺序（与 skill 的语义一致）：
///   1. merchantRules（有序正则，首个命中即止）
///   2. platformDefaults（平台默认推测）
///   3. keywordHints（按分类归集的关键词，覆盖面广但优先级低）
class SkillMatcher {
  /// 按规则表匹配（有序，首个命中即止）
  static MerchantRule? matchRule(
    List<MerchantRule> rules,
    String text, {
    List<String> exceptions = const [],
  }) {
    if (text.isEmpty) return null;
    for (final r in rules) {
      if (!r.isValid) continue;
      if (exceptions.isNotEmpty && _anyMatch(exceptions, text)) continue;
      if (_matches(r.pattern, text)) return r;
    }
    return null;
  }

  /// 需确认判定：返回命中的 needConfirm 规则
  static NeedConfirmRule? matchNeedConfirm(
    SkillDefinition skill,
    String text,
  ) {
    if (text.isEmpty) return null;
    for (final r in skill.needConfirm) {
      if (r.pattern.isEmpty) continue;
      if (_anyMatch(skill.needConfirmExceptions, text)) continue;
      if (_matches(r.pattern, text)) return r;
    }
    return null;
  }

  /// MANUAL 拆分判定
  static ManualSplitRule? matchManualSplit(SkillDefinition skill, String text) {
    if (text.isEmpty) return null;
    for (final r in skill.manualSplits) {
      if (_matches(r.pattern, text)) return r;
    }
    return null;
  }

  /// 关键词兜底：在 [categories]（传叶子分类）里找得分最高的一个
  static int? matchKeywordHint(
    SkillDefinition skill,
    String text,
    List<Category> categories,
  ) {
    if (text.isEmpty || categories.isEmpty) return null;
    final lower = text.toLowerCase();
    int? bestId;
    var bestScore = 0;
    for (final c in categories) {
      final keywords = skill.keywordHints[c.name];
      if (keywords == null || keywords.isEmpty) continue;
      var score = 0;
      for (final k in keywords) {
        if (k.isEmpty) continue;
        if (lower.contains(k.toLowerCase())) {
          score += lower == k.toLowerCase() ? 2 : 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestId = c.id;
      }
    }
    return bestId;
  }

  /// 把 (category, sub) 解析为分类 ID。
  ///
  /// 优先用 sub（叶子名），其次 category（一级名）。因为抽查发现
  /// App 侧传入的候选通常是叶子分类列表，而 skill 的规则大多给到二级。
  static int? resolveCategoryId(
    String? category,
    String? sub,
    List<Category> categories,
  ) {
    final names = <String>[
      if (sub != null && sub.trim().isNotEmpty) sub.trim(),
      if (category != null && category.trim().isNotEmpty) category.trim(),
    ];
    for (final n in names) {
      final hit = categories.where((c) => c.name == n);
      if (hit.isNotEmpty) return hit.first.id;
    }
    // 退一步：子串匹配（兜住"下馆子"vs"下馆子(聚餐)"这类差异）
    for (final n in names) {
      for (final c in categories) {
        if (c.name.contains(n) || n.contains(c.name)) return c.id;
      }
    }
    return null;
  }

  static bool _matches(String pattern, String text) {
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(text);
    } catch (_) {
      // 正则非法时降级为包含判断
      return text.toLowerCase().contains(pattern.toLowerCase());
    }
  }

  static bool _anyMatch(List<String> patterns, String text) =>
      patterns.any((p) => p.isNotEmpty && _matches(p, text));
}
