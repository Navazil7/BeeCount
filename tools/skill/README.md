# skill 资产与可移植性工具

本目录是记账 skill 的**单一真相源**，与任何平台无关。

## 结构

```
assets/skill/skill.json     ← App 运行时读取的规则文件（唯一真相源）
tools/skill/
├── export_skill_md.js      ← skill.json → Trae 风格 markdown
├── import_skill_md.js      ← Trae markdown → skill.json
├── apply_patch.js          ← 一键把全部改动应用到上游源码
├── patch_models.js         ← 模型名修正
└── patch_skill_engine.js   ← skill 引擎接入
```

## skill.json 包含什么

| 键 | 说明 |
|---|---|
| `categories` | 分类合法性清单（一级→二级） |
| `merchantRules` | 商户→分类规则（**有序**，首个命中即止，支持 `manual` 标记） |
| `keywordHints` | 分类名→关键词（覆盖广、优先级低） |
| `platformDefaults` | 平台默认推测（美团→外卖 等） |
| `needConfirm` | 需确认清单（`question` / `screenshot`） |
| `needConfirmExceptions` | 例外（命中即放行） |
| `manualSplits` | MANUAL 金额拆分规则 |
| `specialRules` | 退款/负数/净流水配对等特殊规则 |
| `accounts` | 账户约定 |
| `flow` | 子流程参数（提问批量、去重键、状态分区） |

## App 侧如何消费

```
lib/services/skill/skill_repository.dart   从 assets 加载
lib/services/skill/skill_definition.dart   数据模型
lib/services/skill/skill_matcher.dart      执行器（纯解释，无业务规则）
```

分类匹配链（`bill_creation_service._matchCategory`）：
```
① AI 分类名完全匹配
② AI 分类名模糊匹配
③ skill.merchantRules（有序正则）
④ skill.platformDefaults
⑤ skill.keywordHints
⑥ 上游 CategoryMatcher（兼容兜底）
⑦ 「其它」
```

## 导出 / 导入（可逆）

```bash
# 导出成 Trae 风格的 markdown skill
node tools/skill/export_skill_md.js assets/skill/skill.json ./exported

# 把 markdown 改完再转回来
node tools/skill/import_skill_md.js ./exported assets/skill/skill.json
```

**往返一致性已验证：6/6 章节逐字节一致**（categories / merchantRules /
platformDefaults / needConfirm / manualSplits / specialRules）。

## 换平台怎么办

skill.json 是平台无关的。换到任何环境只需写一个"解释器"：
读 JSON → 按 `merchantRules`（有序正则）匹配 → 落到 `platformDefaults` → `keywordHints`。
Dart 那份解释器（`lib/services/skill/`）可以直接当参考实现。
