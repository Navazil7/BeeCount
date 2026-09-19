import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'skill_definition.dart';

/// 从 assets 加载 skill.json 并提供缓存。
///
/// **单一真相源是 `assets/skill/skill.json`** —— Dart 侧不含任何业务规则。
/// 想改规则：改 JSON（或替换 asset），无需改代码逻辑。
class SkillRepository {
  SkillRepository._();

  static const String assetPath = 'assets/skill/skill.json';

  static SkillDefinition? _cached;
  static Object? _loadError;

  /// 已加载的 skill（可能为 null，表示加载失败 —— 调用方需回退）
  static SkillDefinition? get current => _cached;

  /// 加载/重新加载 skill。失败时返回 null 并记录错误（不抛异常，避免拖垮记账主流程）。
  static Future<SkillDefinition?> load({bool force = false}) async {
    if (_cached != null && !force) return _cached;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw);
      if (json is! Map) throw Exception('skill.json 顶层不是对象');
      _cached = SkillDefinition.fromJson(json.cast<String, dynamic>());
      _loadError = null;
      return _cached;
    } catch (e) {
      _loadError = e;
      return null;
    }
  }

  static Object? get lastError => _loadError;
}
