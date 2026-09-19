/**
 * patch_skill_engine.js —— 把"可移植 skill"引擎接入 App
 *
 * 做三件事：
 *  1. 新增 lib/services/skill/{skill_definition,skill_repository,skill_matcher}.dart
 *     （纯解释器，不含业务规则）
 *  2. 在 bill_creation_service 的分类匹配链里插入 skill 匹配（在旧 CategoryMatcher 之前）
 *  3. pubspec.yaml 注册 assets/skill/
 *
 * 规则本身在 assets/skill/skill.json —— 改规则不用改代码。
 * 用法: node patch_skill_engine.js <BeeCount源码根目录>
 */
const fs=require('fs'),path=require('path');
const SRC=process.argv[2], HERE=__dirname;
if(!SRC){console.error('用法: node patch_skill_engine.js <源码根目录>');process.exit(2);}

// ---------- 1. 复制解释器 ----------
const skillDir=path.join(SRC,'lib/services/skill');
fs.mkdirSync(skillDir,{recursive:true});
for(const f of ['skill_definition.dart','skill_repository.dart','skill_matcher.dart']){
  fs.copyFileSync(path.join(HERE,'skill_dart',f), path.join(skillDir,f));
}
console.log('✅ 新增 lib/services/skill/ 三个解释器文件');

// ---------- 2. 放置 skill.json ----------
const assetDir=path.join(SRC,'assets/skill');
fs.mkdirSync(assetDir,{recursive:true});
fs.copyFileSync(path.join(HERE,'..','skill','skill.json'), path.join(assetDir,'skill.json'));
console.log('✅ 新增 assets/skill/skill.json（规则真相源）');

// ---------- 3. 接入匹配链 ----------
const bcs=path.join(SRC,'lib/services/billing/bill_creation_service.dart');
let s=fs.readFileSync(bcs,'utf8');
if(s.includes('SkillRepository')){
  console.log('⏭  bill_creation_service 已接入 skill 引擎，跳过');
} else {
  // 3a. 加 import
  const impAnchor="import 'category_matcher.dart';";
  if(s.includes(impAnchor)){
    s=s.replace(impAnchor, impAnchor+"\nimport '../skill/skill_matcher.dart';\nimport '../skill/skill_repository.dart';");
    console.log('✅ 已加 import');
  } else {
    // 回退：加在文件第一段 import 之后
    const m=s.match(/^import [^\n]+\n/m);
    if(m){ s=s.replace(m[0], m[0]+"import '../skill/skill_matcher.dart';\nimport '../skill/skill_repository.dart';\n"); console.log('✅ 已加 import（回退锚点）'); }
    else { console.error('❌ 找不到 import 锚点'); process.exit(1); }
  }

  // 3b. 在 CategoryMatcher 兜底之前插入 skill 匹配
  const fallback=`    return CategoryMatcher.smartMatch(
      merchant: note,
      fullText: note,
      categories: categories,
    );`;
  if(!s.includes(fallback)){ console.error('❌ 找不到 CategoryMatcher 兜底锚点'); process.exit(1); }
  s=s.replace(fallback, `    // ===== 【skill 引擎】规则来自 assets/skill/skill.json，Dart 侧无业务规则 =====
    final skill = await SkillRepository.load();
    if (skill != null) {
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
    }

${fallback}`);
  fs.writeFileSync(bcs,s);
  console.log('✅ 已把 skill 匹配链插入分类匹配（优先级高于旧 CategoryMatcher）');
}

// ---------- 4. pubspec 注册 asset ----------
const pub=path.join(SRC,'pubspec.yaml');
let y=fs.readFileSync(pub,'utf8');
if(y.includes('assets/skill/')){
  console.log('⏭  pubspec 已注册 assets/skill/');
} else {
  if(!y.includes('    - assets/images/')){
    console.error('❌ 找不到 assets 声明锚点');
    process.exit(1);
  }
  y=y.replace('    - assets/images/','    - assets/images/\n    - assets/skill/');
  fs.writeFileSync(pub,y);
  console.log('✅ pubspec.yaml 已注册 assets/skill/');
}
console.log('\n🎉 skill 引擎接入完成');
