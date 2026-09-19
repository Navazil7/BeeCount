/**
 * apply_patch.js —— 把「图片记账确认页」改动应用到 BeeCount 源码。
 * 用法: node apply_patch.js <BeeCount源码根目录>
 * 幂等: 重复执行不会重复插入。
 */
const fs = require('fs'), path = require('path');
const SRC = process.argv[2];
if (!SRC) { console.error('用法: node apply_patch.js <BeeCount源码根目录>'); process.exit(2); }
const HERE = __dirname;
const log = m => console.log(m);

// ---------- 1. 新增确认页 ----------
const confirmDst = path.join(SRC, 'lib/pages/ai/image_bill_confirm_page.dart');
fs.mkdirSync(path.dirname(confirmDst), { recursive: true });
fs.copyFileSync(path.join(HERE, 'image_bill_confirm_page.dart'), confirmDst);
log('✅ 新增 lib/pages/ai/image_bill_confirm_page.dart');

// ---------- 2. 替换 image_billing_helper.dart ----------
const helperDst = path.join(SRC, 'lib/utils/image_billing_helper.dart');
const helperSrc = path.join(HERE, 'image_billing_helper.dart');
if (fs.existsSync(helperDst)) {
  const old = fs.readFileSync(helperDst, 'utf8');
  if (old.includes('ImageBillConfirmPage')) {
    log('⏭  lib/utils/image_billing_helper.dart 已是改后版本，跳过');
  } else {
    fs.copyFileSync(helperDst, helperDst + '.orig');
    fs.copyFileSync(helperSrc, helperDst);
    log('✅ 已替换 lib/utils/image_billing_helper.dart（原件备份为 .orig）');
  }
} else { console.error('❌ 找不到 lib/utils/image_billing_helper.dart'); process.exit(1); }

// ---------- 3. 给 AiBookkeeper 注入两个公开方法 ----------
const bkPath = path.join(SRC, 'lib/services/ai/ai_bookkeeper.dart');
let bk = fs.readFileSync(bkPath, 'utf8');
if (bk.includes('Future<BookkeepingResult> persistAll(')) {
  log('⏭  ai_bookkeeper.dart 已含 persistAll，跳过');
} else {
  // 定位类最后一个方法 _enrichWithActualNames 的结束位置：在文件末尾的最后一个 '}' 前插入
  const anchor = "  /// 查询实际入库的分类/账户名称,回填到 BillInfo。";
  const anchorIdx = bk.indexOf(anchor);
  if (anchorIdx < 0) { console.error('❌ 未找到 _enrichWithActualNames 锚点'); process.exit(1); }
  // 从锚点往后找到该方法结束（即文件最后一个 '\n}' 之前）
  const lastBrace = bk.lastIndexOf('\n}');
  if (lastBrace < anchorIdx) { console.error('❌ 定位类结束大括号失败'); process.exit(1); }
  const additions = fs.readFileSync(path.join(HERE, 'ai_bookkeeper_additions.dart'), 'utf8');
  bk = bk.slice(0, lastBrace) + '\n' + additions + bk.slice(lastBrace);
  fs.writeFileSync(bkPath, bk);
  log('✅ 已给 AiBookkeeper 注入 extractFromImage / persistAll');
}

// ---------- 3.5 模型名修正（过期默认模型 → 当前免费主力） ----------
try {
  const { execFileSync } = require('child_process');
  execFileSync(process.execPath, [path.join(HERE, 'patch_models.js'), SRC], { stdio: 'inherit' });
} catch (e) {
  console.error('⚠️ 模型补丁执行失败:', e.message);
}

// （3.6 已移除：规则统一放在 assets/skill/skill.json，不再往 Dart 里写死）

// ---------- 3.7 可移植 skill 引擎 ----------
try {
  const { execFileSync } = require('child_process');
  execFileSync(process.execPath, [path.join(HERE, 'patch_skill_engine.js'), SRC], { stdio: 'inherit' });
} catch (e) { console.error('skill 引擎补丁失败: ' + e.message); }

// ---------- 4. 自检 ----------
const checks = [
  ['lib/pages/ai/image_bill_confirm_page.dart', 'class ImageBillConfirmPage'],
  ['lib/utils/image_billing_helper.dart', 'ImageBillConfirmPage'],
  ['lib/utils/image_billing_helper.dart', 'extractFromImage'],
  ['lib/services/ai/ai_bookkeeper.dart', 'Future<BookkeepingResult> persistAll('],
  ['lib/services/ai/ai_bookkeeper.dart', 'extractFromImage({'],
  ['lib/ai/providers/ai_provider_config.dart', "textModel: 'glm-4.7-flash'"],
  ['lib/ai/providers/ai_provider_config.dart', "visionModel: 'glm-4.6v-flash'"],
  ['assets/skill/skill.json', '"merchantRules"'],
  ['lib/services/skill/skill_matcher.dart', 'class SkillMatcher'],
  ['lib/services/billing/bill_creation_service.dart', 'SkillRepository.load()'],
  ['pubspec.yaml', 'assets/skill/'],
];
let bad = 0;
for (const [f, needle] of checks) {
  const ok = fs.readFileSync(path.join(SRC, f), 'utf8').includes(needle);
  log((ok ? '  ✅ ' : '  ❌ ') + f + '  ← ' + needle);
  if (!ok) bad++;
}
log(bad ? `\n⚠️ ${bad} 项自检未通过` : '\n🎉 改动已全部应用并通过自检');
process.exit(bad ? 1 : 0);
