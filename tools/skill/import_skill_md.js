#!/usr/bin/env node
/**
 * import_skill_md.js —— 把 Trae 风格的 markdown skill 解析回平台无关的 skill.json
 *
 * 这是"逆向导出"的反向操作：让你可以在任何平台/环境里编辑 markdown，
 * 再转回 App 能直接使用的 skill.json。
 *
 * 用法: node import_skill_md.js [skill根目录] [输出skill.json]
 *   默认: ./exported  →  ./skill.json
 */
const fs=require('fs'),path=require('path');
const srcDir=process.argv[2]||path.join(__dirname,'exported');
const outPath=process.argv[3]||path.join(__dirname,'skill.json');

const ruleMd=fs.readFileSync(path.join(srcDir,'references/rule.md'),'utf8');
const ncMd=fs.readFileSync(path.join(srcDir,'references/need_confirm.md'),'utf8');

// 已有 skill.json 作为基底（保留 import 不覆盖的字段）
// 基准永远读 __dirname/skill.json（当前真相源），而不是输出路径 ——
// 否则输出到新文件时 base 为空，会丢掉 markdown 里没有对应位置的纯文档字段。
let base={};
try{ base=JSON.parse(fs.readFileSync(path.join(__dirname,'skill.json'),'utf8')); }catch(e){}

const out=Object.assign({},base);

// ---------- 分类合法性 ----------
const categories={};
let sec=null;
for(const line of ruleMd.split('\n')){
  if(/^## 一、/.test(line)) { sec='cat'; continue; }
  if(/^## /.test(line)) { sec=null; continue; }
  if(sec!=='cat') continue;
  const m=line.match(/^- (.+?): (.*)$/);
  if(!m) continue;
  const name=m[1].trim();
  const subs=m[2].trim()==='' ? [] :
    m[2].split(',').map(s=>s.trim()).map(s=>s==='(空)'?'':s);
  categories[name]=subs;
}
if(Object.keys(categories).length) out.categories=categories;

// ---------- 商户规则 / 平台默认 / MANUAL（按章节切分，严格可逆） ----------
function sectionOf(md, title){
  const lines=md.split('\n');
  const i=lines.findIndex(l=>l.startsWith('## ') && l.includes(title));
  if(i<0) return '';
  let out=[];
  for(let k=i+1;k<lines.length;k++){
    if(/^## /.test(lines[k])) break;
    out.push(lines[k]);
  }
  return out.join('\n');
}
function parseRules(text){
  const rules=[];
  for(const line of text.split('\n')){
    const m=line.match(/^- \`([^\`]+)\`: (.+)$/);
    if(!m) continue;
    const pattern=m[1].trim();
    const rest=m[2].trim();
    if(/^MANUAL/i.test(rest)){
      const reason=rest.replace(/^MANUAL\s*#?\s*/i,'').trim();
      rules.push({pattern,category:null,sub:null,manual:true,reason});
    } else {
      const hashIdx=rest.indexOf('#');
      const note=hashIdx>=0?rest.slice(hashIdx+1).trim():null;
      const body=hashIdx>=0?rest.slice(0,hashIdx).trim():rest;
      const parts=body.split(',').map(x=>x.trim());
      let sub=parts[1]!==undefined?parts[1].trim():null;
      if(sub==='(空)') sub='';
      const rule={pattern, category:parts[0].trim(), sub};
      if(note) rule.note=note;
      rules.push(rule);
    }
  }
  return rules;
}
const merchantRules=parseRules(sectionOf(ruleMd,'商户名 → 分类/二级分类'));
const platformRules=parseRules(sectionOf(ruleMd,'平台默认推测'));
if(merchantRules.length) out.merchantRules=merchantRules;
if(platformRules.length) out.platformDefaults=platformRules;

// ---------- 需确认清单 ----------
const needConfirm=[];
for(const line of ncMd.split('\n')){
  const m=line.match(/^- `([^`]+)`: (question|screenshot)(?:, (.*))?$/);
  if(!m) continue;
  needConfirm.push({pattern:m[1].trim(), type:m[2], hint:m[3]?m[3].trim():undefined});
}
if(needConfirm.length) out.needConfirm=needConfirm;

// ---------- 例外 ----------
const exc=[];
let inExc=false;
for(const line of ncMd.split('\n')){
  if(/^## 三、例外/.test(line)){ inExc=true; continue; }
  if(/^## /.test(line)){ inExc=false; continue; }
  if(!inExc) continue;
  const m=line.match(/^- `([^`]+)`$/);
  if(m) exc.push(m[1].trim());
}
if(exc.length) out.needConfirmExceptions=exc;

// ---------- MANUAL 金额拆分 ----------
const splitSec=sectionOf(ruleMd,'MANUAL 金额拆分');
const manualSplits=[];
for(const line of splitSec.split('\n')){
  const m=line.match(/^- \`([^\`]+)\`: 固定 (.+?)\/(.+?) = ([\d.]+)，余额 → (.+?)\/(.+?)$/);
  if(!m) continue;
  const noteLine=splitSec.split('\n').find(l=>l.trim().startsWith('#') && splitSec.indexOf(l)>splitSec.indexOf(line));
  manualSplits.push({
    pattern:m[1].trim(),
    fixed:{ amount:parseFloat(m[4]), category:m[2].trim(), sub:(m[3].trim()==='(空)'?'':m[3].trim()) },
    rest:{ category:m[5].trim(), sub:(m[6].trim()==='(空)'?'':m[6].trim()) },
    ...(noteLine?{note:noteLine.trim().replace(/^#\s*/,'')}:{}),
  });
}
if(manualSplits.length) out.manualSplits=manualSplits;

// ---------- specialRules 解析 ----------
const spSec=sectionOf(ruleMd,'特殊规则');
if(spSec.trim()){
  const refundLine=spSec.split('\n').find(l=>l.includes('若商户名包含'))||'';
  const beforeType=refundLine.split('则类型')[0];
  const refundKeywords=[...beforeType.matchAll(/「([^」]+)」/g)].map(m=>m[1]).filter(Boolean);
  const offLine=spSec.split('\n').find(l=>l.includes('两笔均不记录'))||'';
  const winMatch=offLine.match(/退款在\s*(\d+)\s*天/);
  out.specialRules={
    refundKeywords: refundKeywords.length?refundKeywords:(out.specialRules&&out.specialRules.refundKeywords)||[],
    negativeAmountIsIncome: /金额为负数/.test(spSec),
    refundKeepsOriginalCategory: /与原始支出保持一致/.test(spSec),
    fullRefundOffset:{
      enabled: /两笔均不记录/.test(spSec),
      windowDays: winMatch?parseInt(winMatch[1],10):((out.specialRules&&out.specialRules.fullRefundOffset&&out.specialRules.fullRefundOffset.windowDays)||3),
      note:(out.specialRules&&out.specialRules.fullRefundOffset&&out.specialRules.fullRefundOffset.note)||'',
    },
    incomeWithoutRule:(base.specialRules&&base.specialRules.incomeWithoutRule)||'',
  };
  console.log('   specialRules 解析: 退款词', out.specialRules.refundKeywords.length, '个, 全额退款配对:', out.specialRules.fullRefundOffset.enabled);
}

// 保留纯文档字段（markdown 里没有对应位置，从 base 继承）
if(out.specialRules&&base.specialRules){
  const bsp=base.specialRules;
  if(!out.specialRules.incomeWithoutRule&&bsp.incomeWithoutRule)
    out.specialRules.incomeWithoutRule=bsp.incomeWithoutRule;
  if(out.specialRules.fullRefundOffset&&bsp.fullRefundOffset&&
     !out.specialRules.fullRefundOffset.note&&bsp.fullRefundOffset.note)
    out.specialRules.fullRefundOffset.note=bsp.fullRefundOffset.note;
}

out.schemaVersion=out.schemaVersion||2;
fs.writeFileSync(outPath, JSON.stringify(out,null,2));
console.log('✅ 已从 markdown 解析回:', outPath);
console.log('   分类(一级):', Object.keys(out.categories||{}).length);
console.log('   商户规则:', (out.merchantRules||[]).length);
console.log('   需确认:', (out.needConfirm||[]).length);
console.log('   平台默认:', (out.platformDefaults||[]).length);
