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

  const fallback=`    return CategoryMatcher.smartMatch(
      merchant: note,
      fullText: note,
      categories: categories,
    );`;
  if(!s.includes(fallback)){ console.error('❌ 找不到 CategoryMatcher 兜底锚点'); process.exit(1); }
  s=s.replace(fallback, `    // ===== 【skill 引擎】规则来自 lib/services/skill/skill_data.dart =====
    // 真相源是 Dart 常量（编译期检查、无 IO、无加载失败路径）。
    // 导出：tools/skill/extract_from_dart.js（单向序列化，不会漂移）。
    final skill = SkillData.definition;

    // ① merchantRules：有序正则，首个命中即止
    final byRule = SkillMatcher.matchRule(skill.merchantRules, note);
    if (byRule != null && !byRule.manual) {
      final id = SkillMatcher.resolveCategoryId(
          byRule.category, byRule.sub, categories);
      if (id != null) {
        logger.debug(_tag,
            '[分类匹配-skill规则] "$note" → \${byRule.category}/\${byRule.sub ?? ''} (ID:\$id)');
        return id;
      }
    }

    // ② platformDefaults：平台默认推测
    final byPlatform = SkillMatcher.matchRule(skill.platformDefaults, note);
    if (byPlatform != null) {
      final id = SkillMatcher.resolveCategoryId(
          byPlatform.category, byPlatform.sub, categories);
      if (id != null) {
        logger.debug(_tag, '[分类匹配-skill平台] "$note" → \${byPlatform.category}(ID:\$id)');
        return id;
      }
    }

    // ③ keywordHints：关键词兜底
    final byKeyword = SkillMatcher.matchKeywordHint(skill, note, categories);
    if (byKeyword != null) {
      logger.debug(_tag, '[分类匹配-skill关键词] "$note" → ID:\$byKeyword');
      return byKeyword;
    }

${fallback}`);
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
