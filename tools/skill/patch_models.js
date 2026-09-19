/**
 * patch_models.js —— 修正过期的智谱默认模型 + 让用户能一键选常用模型
 *   文本: glm-4-flash  → glm-4.7-flash  (免费, 200K, 支持 JSON/FC)
 *   视觉: glm-4v-flash → glm-4.6v-flash (免费, 128K, 支持 JSON/FC)
 * 背景: 旧的 glm-4v-flash 上下文只有 4K，长账单截图极易超限。
 * 用法: node patch_models.js <BeeCount源码根目录>
 */
const fs=require('fs'),path=require('path');
const SRC=process.argv[2];
if(!SRC){console.error('用法: node patch_models.js <源码根目录>');process.exit(2);}
let n=0;
const edit=(rel,fn)=>{
  const p=path.join(SRC,rel);
  if(!fs.existsSync(p)){ console.log('⚠️ 文件不存在: '+rel); return; }
  const before=fs.readFileSync(p,'utf8');
  const after=fn(before);
  if(after!==before){ fs.writeFileSync(p,after); n++; console.log('✅ '+rel); }
  else console.log('⏭  '+rel+' 无变化（可能已改过）');
};

// ---------- 1. ai_provider_config.dart：默认配置 ----------
edit('lib/ai/providers/ai_provider_config.dart', s=>s
  .replace("textModel: 'glm-4-flash',","textModel: 'glm-4.7-flash',")
  .replace("visionModel: 'glm-4v-flash',","visionModel: 'glm-4.6v-flash',")
);

// ---------- 2. ai_constants.dart：默认常量 + 模型清单 + 显示名 ----------
edit('lib/ai/providers/ai_constants.dart', s=>{
  s=s.replace("static const String defaultGlmModel = 'glm-4-flash';",
              "static const String defaultGlmModel = 'glm-4.7-flash';");
  s=s.replace("static const String defaultGlmVisionModel = 'glm-4v-flash';",
              "static const String defaultGlmVisionModel = 'glm-4.6v-flash';");
  s=s.replace(`  static const List<String> glmTextModels = [
    'glm-4-flash',
    'glm-4.6',`,
`  static const List<String> glmTextModels = [
    'glm-4.7-flash',
    'glm-4.7',
    'glm-4.6',
    'glm-4-flash',`);
  s=s.replace(`  static const List<String> glmVisionModels = [
    'glm-4v-flash',
    'glm-4.6v',`,
`  static const List<String> glmVisionModels = [
    'glm-4.6v-flash',
    'glm-4.6v',
    'glm-4v-flash',`);
  s=s.replace(`      case 'glm-4-flash':
        return 'GLM-4-Flash（$fast）';`,
`      case 'glm-4.7-flash':
        return 'GLM-4.7-Flash（免费·200K）';
      case 'glm-4.7':
        return 'GLM-4.7（$accurate）';
      case 'glm-4-flash':
        return 'GLM-4-Flash（旧·128K）';`);
  s=s.replace(`      case 'glm-4v-flash':
        return 'GLM-4V-Flash（$fast）';`,
`      case 'glm-4.6v-flash':
        return 'GLM-4.6V-Flash（免费·128K）';
      case 'glm-4v-flash':
        return 'GLM-4V-Flash（旧·仅4K）';`);
  return s;
});

// ---------- 3. ai_provider_manage_page.dart：给模型输入框加"常用模型"快捷选择 ----------
edit('lib/pages/ai/ai_provider_manage_page.dart', s=>{
  // 3a. 函数签名加 suggestions
  s=s.replace(`    required TestStatus testStatus,
    String? testError,
    required VoidCallback onTest,
  }) {
    final primaryColor = ref.watch(primaryColorProvider);`,
`    required TestStatus testStatus,
    String? testError,
    required VoidCallback onTest,
    List<String> suggestions = const [],
  }) {
    final primaryColor = ref.watch(primaryColorProvider);`);

  // 3b. 输入框下方渲染建议 chips
  s=s.replace(`          onChanged: (_) => setState(() {}),
        ),
        // 错误信息
        if (testStatus == TestStatus.failed && testError != null) ...[`,
`          onChanged: (_) => setState(() {}),
        ),
        // 常用模型快捷选择（点一下就填进输入框）
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final sug = suggestions[i];
                return ActionChip(
                  label: Text(sug, style: const TextStyle(fontSize: 11.5)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => controller.text = sug),
                );
              },
            ),
          ),
        ],
        // 错误信息
        if (testStatus == TestStatus.failed && testError != null) ...[`);

  // 3c. 三个调用点传建议列表
  s=s.replace(`                          hintText: _isBuiltIn ? AIConstants.defaultGlmModel : 'gpt-4o-mini',
                          testStatus: _textTestStatus,
                          testError: _textTestError,
                          onTest: _testTextCapability,
                        ),`,
`                          hintText: _isBuiltIn ? AIConstants.defaultGlmModel : 'gpt-4o-mini',
                          testStatus: _textTestStatus,
                          testError: _textTestError,
                          onTest: _testTextCapability,
                          suggestions: _isBuiltIn
                              ? const ['glm-4.7-flash', 'glm-4.7', 'glm-4.6']
                              : const ['deepseek-flash', 'gpt-4o-mini', 'qwen-plus'],
                        ),`);
  s=s.replace(`                          hintText: _isBuiltIn ? AIConstants.defaultGlmVisionModel : 'gpt-4o',
                          testStatus: _visionTestStatus,
                          testError: _visionTestError,
                          onTest: _testVisionCapability,
                        ),`,
`                          hintText: _isBuiltIn ? AIConstants.defaultGlmVisionModel : 'gpt-4o',
                          testStatus: _visionTestStatus,
                          testError: _visionTestError,
                          onTest: _testVisionCapability,
                          suggestions: _isBuiltIn
                              ? const ['glm-4.6v-flash', 'glm-4.6v']
                              : const ['deepseek-flash', 'gpt-4o'],
                        ),`);
  return s;
});

// ---------- 4. ai_provider_manager.dart：迁移函数里的硬编码兜底值 ----------
// 这是最隐蔽的一处：每次全新安装都会跑 migrateFromOldConfig()，
// 它用 ?? 'glm-4-flash' / 'glm-4v-flash' 兜底，会绕过 zhipuDefault 的默认值。
// 改成引用 AIConstants 常量，避免以后再次漂移。
edit('lib/ai/providers/ai_provider_manager.dart', s=>s
  .replace("prefs.getString('ai_glm_model') ?? 'glm-4-flash'",
           "prefs.getString('ai_glm_model') ?? AIConstants.defaultGlmModel")
  .replace("prefs.getString('ai_glm_vision_model') ?? 'glm-4v-flash'",
           "prefs.getString('ai_glm_vision_model') ?? AIConstants.defaultGlmVisionModel")
  .replace("prefs.getString('ai_glm_audio_model') ?? 'glm-4-voice'",
           "prefs.getString('ai_glm_audio_model') ?? AIConstants.defaultGlmAudioModel")
);

console.log(n?`\n🎉 共修改 ${n} 个文件`:'\n⚠️ 没有文件被修改');
