/**
 * patch_skill_engine.js —— 接入「可移植 skill」引擎（方案 C：硬编码为真相源）
 *
 *  1. 新增 lib/services/skill/{skill_definition,skill_data,skill_matcher}.dart
 *     - skill_data.dart 是 skill 的**唯一真相源**（编译期检查、无 IO、无加载失败路径）
 *     - skill_matcher.dart 是纯执行器
 *  2. 在 bill_creation_service 的分类匹配链里插入 skill 匹配
 *  3. pubspec.yaml：修正版本号（上游是 0.0.1，会被系统判降级）
 *
 * 导出：node tools/skill/extract_from_dart.js（Dart → skill.json → markdown）
 * 用法: node patch_skill_engine.js <BeeCount源码根目录>
 */
const fs=require('fs'),path=require('path');
const SRC=process.argv[2], HERE=__dirname;
if(!SRC){console.error('用法: node patch_skill_engine.js <源码根目录>');process.exit(2);}

// ---------- 1. 复制解释器与真相源 ----------
const skillDir=path.join(SRC,'lib/services/skill');
fs.mkdirSync(skillDir,{recursive:true});
for(const f of ['skill_definition.dart','skill_data.dart','skill_matcher.dart']){
  fs.copyFileSync(path.join(HERE,'skill_dart',f), path.join(skillDir,f));
}
// 一致性自检：skill_data.dart 用到的命名参数必须在 skill_definition.dart 里存在
{
  const { execFileSync } = require('child_process');
  execFileSync(process.execPath, [path.join(HERE,'skill_dart','verify_consistency.js'), path.join(HERE,'skill_dart')], { stdio: 'inherit' });
}
console.log('✅ 新增 lib/services/skill/ 三个文件（含真相源 skill_data.dart）');

// ---------- 2. 接入匹配链 ----------
const bcs=path.join(SRC,'lib/services/billing/bill_creation_service.dart');
let s=fs.readFileSync(bcs,'utf8');
if(s.includes('SkillData.definition')){
  console.log('⏭  bill_creation_service 已接入 skill，跳过');
} else {
  const impAnchor="import 'category_matcher.dart';";
  if(s.includes(impAnchor)){
    s=s.replace(impAnchor, impAnchor+"\nimport '../skill/skill_data.dart';\nimport '../skill/skill_matcher.dart';");
  } else {
    const m=s.match(/^import [^\n]+\n/m);
    if(m) s=s.replace(m[0], m[0]+"import '../skill/skill_data.dart';\nimport '../skill/skill_matcher.dart';\n");
    else { console.error('❌ 找不到 import 锚点'); process.exit(1); }
  }
  console.log('✅ 已加 import');

  // 用「整体替换 _matchCategory 方法」的方式，保证 skill 规则【优先于】AI 猜测。
  // skill 的设计：规则是权威、首个命中即止；AI 只在规则未命中时补充。
  const origMethod = `  Future<int?> _matchCategory(
    String? aiCategoryName,
    String note,
    List<Category> categories,
  ) async {`;
  const mi = s.indexOf(origMethod);
  if (mi < 0) {
    console.error('❌ 找不到 _matchCategory 方法');
    process.exit(1);
  }
  // 找到方法结束（行首两个空格的右花括号）
  const endRe = /\n  \}\n/;
  const rest = s.slice(mi);
  const em = endRe.exec(rest);
  if (!em) { console.error('❌ 找不到方法结束'); process.exit(1); }
  const methodEnd = mi + em.index + em[0].length;

  const newMethod = [
    '  Future<int?> _matchCategory(',
    '    String? aiCategoryName,',
    '    String note,',
    '    List<Category> categories,',
    '  ) async {',
    '    if (categories.isEmpty) return null;',
    '',
    '    // ===== 【skill 引擎 · 规则优先】=====',
    '    // skill 的设计：规则是权威（有序、首个命中即止），AI 只在规则未命中时补充。',
    '    // 规则数据在 lib/services/skill/skill_data.dart —— 本文件只是解释器。',
    '    final skill = SkillData.definition;',
    '',
    '    // ① merchantRules',
    '    final byRule = SkillMatcher.matchRule(skill.merchantRules, note);',
    '    if (byRule != null && !byRule.manual) {',
    '      final id =',
    '          SkillMatcher.resolveCategoryId(byRule.category, byRule.sub, categories);',
    '      if (id != null) {',
    '        logger.debug(_tag,',
    '            \'[分类匹配-skill规则] "$note" → ${byRule.category}/${byRule.sub ?? \'\'}\');',
    '        return id;',
    '      }',
    '    }',
    '',
    '    // ② platformDefaults',
    '    final byPlatform = SkillMatcher.matchRule(skill.platformDefaults, note);',
    '    if (byPlatform != null) {',
    '      final id = SkillMatcher.resolveCategoryId(',
    '          byPlatform.category, byPlatform.sub, categories);',
    '      if (id != null) {',
    '        logger.debug(_tag, \'[分类匹配-skill平台] "$note" → ${byPlatform.category}\');',
    '        return id;',
    '      }',
    '    }',
    '',
    '    // ③ keywordHints',
    '    final byKeyword = SkillMatcher.matchKeywordHint(skill, note, categories);',
    '    if (byKeyword != null) {',
    '      logger.debug(_tag, \'[分类匹配-skill关键词] "$note" → ID:$byKeyword\');',
    '      return byKeyword;',
    '    }',
    '',
    '    // ===== 以下为规则未命中时的补充路径 =====',
    '    if (aiCategoryName != null && aiCategoryName.isNotEmpty) {',
    '      final exact =',
    '          categories.firstWhereOrNull((c) => c.name == aiCategoryName);',
    '      if (exact != null) {',
    '        logger.debug(_tag,',
    '            \'[分类匹配-完全] AI 分类"$aiCategoryName" → ${exact.name}\');',
    '        return exact.id;',
    '      }',
    '      Category? best;',
    '      var bestScore = 0;',
    '      for (final c in categories) {',
    '        var score = 0;',
    '        if (c.name.contains(aiCategoryName)) {',
    '          score = aiCategoryName.length;',
    '        } else if (aiCategoryName.contains(c.name)) {',
    '          score = c.name.length;',
    '        }',
    '        if (score > bestScore) {',
    '          bestScore = score;',
    '          best = c;',
    '        }',
    '      }',
    '      if (best != null) {',
    '        logger.debug(_tag,',
    '            \'[分类匹配-模糊] AI 分类"$aiCategoryName" → ${best.name}\');',
    '        return best.id;',
    '      }',
    '    }',
    '',
    '    return CategoryMatcher.smartMatch(',
    '      merchant: note,',
    '      fullText: note,',
    '      categories: categories,',
    '    );',
    '  }',
    '',
  ].join('\n');

  s = s.slice(0, mi) + newMethod + s.slice(methodEnd);
  console.log('✅ 已重排匹配链：skill 规则优先于 AI 猜测');
  fs.writeFileSync(bcs,s);
  console.log('✅ 已把 skill 匹配链插入分类匹配（无 IO，直接读常量）');
}

// ---------- 3. 版本号修正 ----------
const VERSION_LINE='version: 3.8.1+218';
{
  const pubPath=path.join(SRC,'pubspec.yaml');
  let y=fs.readFileSync(pubPath,'utf8');
  if(!y.includes(VERSION_LINE)){
    y=y.replace(/^version: .*$/m, VERSION_LINE);
    fs.writeFileSync(pubPath,y);
    console.log('✅ pubspec.yaml 版本号修正 → '+VERSION_LINE);
  } else {
    console.log('⏭  pubspec.yaml 版本号已正确');
  }
}
console.log('\n🎉 skill 引擎接入完成（方案 C：Dart 常量为真相源）');
