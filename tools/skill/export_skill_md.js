#!/usr/bin/env node
/**
 * export_skill_md.js —— 把平台无关的 skill.json 导出成 Trae 风格的 markdown skill
 *
 * 用途：skill.json 是单一真相源；本脚本把它还原成可直接放进 Trae 云端模式的
 * 文件结构（SKILL.md + references/*.md）。这样你随时能把 skill 从 App 里"拔出来"。
 *
 * 用法: node export_skill_md.js [skill.json] [输出目录]
 *   默认: ./skill.json  →  ./exported/
 */
const fs=require('fs'),path=require('path');

const skillPath=process.argv[2]||path.join(__dirname,'skill.json');
const outDir=process.argv[3]||path.join(__dirname,'exported');
const skill=JSON.parse(fs.readFileSync(skillPath,'utf8'));

fs.mkdirSync(path.join(outDir,'references'),{recursive:true});
const W=(rel,txt)=>fs.writeFileSync(path.join(outDir,rel),txt);

const catLines=Object.entries(skill.categories)
  .map(([k,v])=>`- ${k}: ${v.map(s=>s===''?'(空)':s).join(',')}`).join('\n');

const ruleLines=(rules,title)=>{
  let out=`### ${title}\n\n`;
  for(const r of rules){
    if(r.manual){
      out+=`- \`${r.pattern}\`: MANUAL # ${r.reason||'需手工处理'}\n`;
    } else {
      out+=`- \`${r.pattern}\`: ${r.category}${r.sub!==null&&r.sub!==undefined?`, ${r.sub===''?'(空)':r.sub}`:''}\n`;
    }
  }
  return out;
};

// ---------- references/rule.md ----------
W('references/rule.md',`# 记账规则文件

> ⚠️ 本文件由 \`skill.json\` 自动导出（export_skill_md.js）。
> **不要直接改本文件** —— 改动应写回 skill.json 后重新导出，否则会丢失。

## 一、分类-二级分类合法性（从历史账单中归纳）

以下是允许的分类和二级分类组合，当规则匹配到的组合不在此列时，应视为规则错误或需要用户确认。

${catLines}

## 二、商户名 → 分类/二级分类 映射规则（正则匹配，从上到下依次匹配，首个命中即止）

> 优先级 = 数组顺序。前若干条为「优先规则」，其余为「默认规则」。

${ruleLines(skill.merchantRules,'规则（按顺序，含 MANUAL）')}
## 三、平台默认推测

当账单只显示平台名、看不到具体商品时，按平台给默认分类：

${skill.platformDefaults.map(r=>`- \`${r.pattern}\`: ${r.category}${r.sub?`, ${r.sub}`:''}${r.note?` # ${r.note}`:''}`).join('\n')}

## 四、MANUAL 金额拆分

${skill.manualSplits.map(r=>`- \`${r.pattern}\`: 固定 ${r.fixed.category}/${r.fixed.sub||'(空)'} = ${r.fixed.amount}，余额 → ${r.rest.category}/${r.rest.sub||'(空)'}\n  # ${r.note||''}`).join('\n')}

## 五、特殊规则

- 若商户名包含「${skill.specialRules.refundKeywords.join('」「')}」，则类型为「收入」，分类与原始支出保持一致（需用户确认）。
${skill.specialRules.negativeAmountIsIncome?'- 如果金额为负数（截图显示"-¥xx"），则类型为「收入」。':''}
- 收入类账单若无商户规则命中，由 AI 在第一节合法性清单中选择最贴切的分类，经用户确认后输出。
${(skill.specialRules.fullRefundOffset&&skill.specialRules.fullRefundOffset.enabled)?`- 若某笔支出存在对应的全额退款（同商户、金额一致、退款在 ${(skill.specialRules.fullRefundOffset&&skill.specialRules.fullRefundOffset.windowDays)||3} 天内），则该支出与退款两笔均不记录，视为净流水为 0。`:''}
`);

// ---------- references/need_confirm.md ----------
W('references/need_confirm.md',`# 需用户进一步确认的商户清单

> ⚠️ 本文件由 \`skill.json\` 自动导出，请勿直接编辑。

## 一、处理类型说明

| 类型 | 含义 | 处理子流程 |
|------|------|-----------|
| \`question\` | 提问确认型：不引导补截图，直接梳理账单并以提问形式向用户确认 | \`flow-question.md\` |
| \`screenshot\` | 补充截图型：引导用户提供对应平台账单截图，推测分类后提问确认 | \`flow-screenshot.md\` |

## 二、清单（正则匹配，从上到下依次匹配，首个命中即止）

${skill.needConfirm.map(r=>`- \`${r.pattern}\`: ${r.type}${r.hint?`, ${r.hint}`:''}`).join('\n')}

## 三、例外（优先于本清单，命中即放行）

${skill.needConfirmExceptions.length?skill.needConfirmExceptions.map(p=>`- \`${p}\``).join('\n'):'（无）'}

## 四、治理规则

- 清单内商户**一律优先走子流程**，不直接使用 \`rule.md\` 结果。
- **例外**：若该商户同时命中 \`rule.md\` 的例外规则，则跳过本清单直接输出。
- 新增/删除条目须由 AI 起草、经用户确认后写入 \`skill.json\` 再导出。
`);

// ---------- SKILL.md ----------
const f=skill.flow||{};
W('SKILL.md',`---
name: ${skill.name}
description: >
  ${skill.description}
---

# 微信记账 Agent

你是一个专业的记账助手。用户会提供微信支付截图，你需要按照以下流程自动处理每一条交易记录。

## 核心流程

### 1. 接收并解析图片内容

- 提取：\`交易时间\`（转 \`YYYY/M/D H:mm\`）、\`商户名称\`、\`金额\`（绝对值）、\`类型\`（支出/收入）
- 金额为负数或含「${skill.specialRules.refundKeywords.join('」「')}」→ 类型为「收入」

### 2. 读取规则文件

读取 \`references/rule.md\`（分类合法性 + 商户映射 + 特殊规则）与 \`references/need_confirm.md\`。

### 3. 账单分流（关键决策点）

对每条账单按 \`need_confirm.md\` 清单**从上到下依次匹配，首个命中即止**：

- \`question\` → 子流程 A（\`references/flow-question.md\`）
- \`screenshot\` → 子流程 B（\`references/flow-screenshot.md\`）
- 未命中 → 继续第 4 步

### 4. 应用规则转换

按 \`rule.md\` 的规则**从上到下依次匹配，首个命中即止**：

- 值为 \`MANUAL\` → 暂停该条，提示用户手工拆分
- 未命中任何规则 → 暂停该条，提示补充规则

### 5. 校验分类合法性

与 \`rule.md\` 第一节清单比对；不在清单内视为规则错误，暂停并提示修正。

### 6. 输出

按 \`时间 分类 二级分类 类型 金额 账户\` 六列输出（Markdown 表格或 CSV 行）。

### 7. 迭代完善规则

未命中规则的商户：AI 起草 → 用户确认 → **写回 skill.json** → 重新导出。

## 子流程参数

- 提问批量：每批最多 ${(f.question&&f.question.batchSize)||3} 条；兜底选项：${((f.question&&f.question.fallbacks)||[]).join(' / ')}
- 截图型：候选数 ${(f.screenshot&&f.screenshot.candidatesPerItem)||3}，${(f.screenshot&&f.screenshot.fallbackToPlatformDefault)?'允许回退到平台默认分类':'不允许回退'}
- 去重键：${((f.dedupe&&f.dedupe.key)||['time','merchant','amount']).join('+')}，窗口 ${(f.dedupe&&f.dedupe.windowDays)||1} 天
- 状态分区：${((f.statePartitions)||['已确认','待确认','已跳过']).join(' / ')}

## 约束条件

- **禁止臆造规则**：任何不确定的映射都必须暂停，要求用户确认。
- **OCR 不确定时暂停**：商户名含乱码或疑似识别错误时，不得猜测。
- **规则自检**：每次处理前自检 rule.md 全部映射，组合不在合法性清单内即告警。
- **导入去重**：导入前提醒核对，钱迹不承诺导入去重。
`);

// ---------- flow 文件 ----------
W('references/flow-question.md',`# 子流程 A：提问确认型

> ⚠️ 由 skill.json 导出。

适用：命中 \`need_confirm.md\` 中类型为 \`question\` 的商户。

## 步骤

### A1. 汇总待确认账单
逐条列出（\`时间\`、\`商户\`、\`金额\`、\`类型\`），不遗漏、不合并。

### A2. 组织提问
- ≤ ${(f.question&&f.question.batchSize)||3} 条：一次性列出统一提问
- \\> ${(f.question&&f.question.batchSize)||3} 条：按商户分组分批，每批最多 ${(f.question&&f.question.batchSize)||3} 条

### A3. 接收回答
用户口述用途 → AI 从合法性清单匹配并复述确认；用户直接给分类 → 校验后采用。
回答不明确时提供兜底：${((f.question&&f.question.fallbacks)||[]).map((x,i)=>`${String.fromCharCode(97+i)}) ${x}`).join('；')}

### A4. 回填主表格
按主流程第 6 步格式输出该行，合并时按「时间+商户+金额」去重。

## 约束
- 禁止臆测；本子流程结果**禁止**写入 rule.md。
- 用户说"以后 X 都记成 Y"时：先查重 → 无冲突则起草并等确认 → 有冲突则请用户裁决。
`);

W('references/flow-screenshot.md',`# 子流程 B：补充截图型

> ⚠️ 由 skill.json 导出。

适用：命中 \`need_confirm.md\` 中类型为 \`screenshot\` 的商户。

## 步骤

### B1. 汇总待确认账单并引导补图
列出 \`时间\`/\`商户\`/\`金额\`/\`类型\`，说明需要对应平台的账单截图。

### B2. 解析补充截图
提取 \`订单时间\`/\`订单号\`/\`实付金额\`/\`商品名\`。

### B3. 订单对应
优先按 \`时间 + 金额\` 对应；金额不一致则**暂停**提问，不强行对应。

### B4. 推测分类候选
有商品名 → 按商品关键词推测；无商品名 → **平台默认推测**：
${skill.platformDefaults.map(r=>`- ${r.pattern} → ${r.category}${r.sub?`/${r.sub}`:''}`).join('\n')}

每条给 **${(f.screenshot&&f.screenshot.candidatesPerItem)||3} 个候选**，标注推荐项，候选只能来自合法性清单。

### B5. 提问确认
以「请回复 A/B/C 或直接告知分类」的形式提问。

### B6. 回填主表格

### B7. 用户不提供截图的兜底
${(f.screenshot&&f.screenshot.fallbackToPlatformDefault)?'截图不是记账的前置条件。用户不补图时按平台默认给推荐候选，一次确认即入表，**不得无限期停留在「待补截图」**。':'（按需处理）'}

## 约束
- 禁止臆测；本子流程结果**禁止**写入 rule.md。
`);

console.log('✅ 已导出 Trae 风格 skill 到:', outDir);
for(const f2 of ['SKILL.md','references/rule.md','references/need_confirm.md','references/flow-question.md','references/flow-screenshot.md']){
  const p2=path.join(outDir,f2);
  console.log('   '+f2.padEnd(36), fs.statSync(p2).size+' 字节');
}
