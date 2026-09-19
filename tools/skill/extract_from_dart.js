#!/usr/bin/env node
/**
 * extract_from_dart.js —— 从 skill_data.dart 逆向提取出 skill.json
 *
 * 方案 C 的"导出"环节：真相源是 Dart 常量（编译期检查），
 * 本脚本把它**单向序列化**成平台无关的 skill.json（不会漂移）。
 *
 * 再配合 export_skill_md.js 就能得到 Trae 风格的 markdown skill。
 *
 * 用法: node extract_from_dart.js [skill_data.dart] [输出skill.json]
 */
const fs=require('fs'),path=require('path');
const dartPath=process.argv[2]||path.join(__dirname,'skill_data.dart');
const outPath=process.argv[3]||path.join(__dirname,'skill.json');
const src=fs.readFileSync(dartPath,'utf8');

/** 取形如 `marker ... ;` 或 `{...}` 的块（按大括号/方括号配平） */
function block(startMarker, open, close){
  const i=src.indexOf(startMarker);
  if(i<0) throw new Error('找不到标记: '+startMarker);
  const s=src.indexOf(open, i);
  if(s<0) throw new Error('找不到起始符: '+open);
  let depth=0, inStr=false, esc=false;
  for(let k=s;k<src.length;k++){
    const c=src[k];
    if(inStr){ if(esc) esc=false; else if(c==='\\') esc=true; else if(c==='"') inStr=false; continue; }
    if(c==='"'){ inStr=true; continue; }
    if(c===open) depth++;
    else if(c===close){ depth--; if(depth===0) return src.slice(s+1,k); }
  }
  throw new Error('块未闭合: '+startMarker);
}
const unq=s=>JSON.parse(s);
/** 解析 "k": [...] 形式的 const map */
function parseStringListMap(text){
  const out={};
  const re=/"((?:[^"\\]|\\.)*)"\s*:\s*\[([^\]]*)\]/g;
  let m;
  while((m=re.exec(text))!==null){
    const key=unq('"'+m[1]+'"');
    const items=[];
    const ire=/"((?:[^"\\]|\\.)*)"/g;
    let im;
    while((im=ire.exec(m[2]))!==null) items.push(unq('"'+im[1]+'"'));
    out[key]=items;
  }
  return out;
}
/** 扫描出所有 Ctor(...) 调用的参数体（括号配平 + 跳过字符串） */
function ctorBodies(text, ctor){
  const out=[]; const needle=ctor+'('; let idx=0;
  while(true){
    const i=text.indexOf(needle, idx);
    if(i<0) break;
    let j=i+needle.length, depth=1, inStr=false, esc=false;
    for(; j<text.length; j++){
      const c=text[j];
      if(inStr){ if(esc) esc=false; else if(c==='\\') esc=true; else if(c==='"') inStr=false; continue; }
      if(c==='"'){ inStr=true; continue; }
      if(c==='(') depth++;
      else if(c===')'){ depth--; if(depth===0) break; }
    }
    out.push(text.slice(i+needle.length, j));
    idx=j+1;
  }
  return out;
}
/** 解析 Ctor(...) 列表为对象数组（按 kind 做 canonical 键顺序，保证可重复） */
function parseRuleList(text, ctor, kind){
  return ctorBodies(text, ctor).map(body=>{
    const raw={};
    const kre=/(\w+)\s*:\s*("(?:[^"\\]|\\.)*"|true|false|-?\d+(?:\.\d+)?)/g;
    let km;
    while((km=kre.exec(body))!==null){
      const k=km[1]; let v=km[2];
      if(v==='true') v=true; else if(v==='false') v=false;
      else if(/^-?\d/.test(v)) v=parseFloat(v);
      else v=unq(v);
      raw[k]=v;
    }
    if(kind==='merchant'){
      const o={pattern:raw.pattern, category:raw.category??null, sub:raw.sub??null};
      if(raw.manual===true){ o.manual=true; o.reason=raw.reason; }
      if(raw.note!==undefined) o.note=raw.note;
      return o;
    }
    if(kind==='needconfirm'){
      const o={pattern:raw.pattern, type:raw.type};
      if(raw.hint!==undefined) o.hint=raw.hint;
      return o;
    }
    return raw;
  });
}
const skill={
  schemaVersion: parseInt((src.match(/schemaVersion\s*=\s*(\d+)/)||[])[1]||'2',10),
  name: unq((src.match(/skillName\s*=\s*("(?:[^"\\]|\\.)*")/)||[])[1]||'"skill"'),
  categories: parseStringListMap(block('Map<String, List<String>> categories','{','}')),
  merchantRules: parseRuleList(block('List<MerchantRule> merchantRules','[',']'),'MerchantRule','merchant'),
  platformDefaults: parseRuleList(block('List<MerchantRule> platformDefaults','[',']'),'MerchantRule','merchant'),
  needConfirm: parseRuleList(block('List<NeedConfirmRule> needConfirm','[',']'),'NeedConfirmRule','needconfirm'),
  keywordHints: parseStringListMap(block('Map<String, List<String>> keywordHints','{','}')),
};

// 例外
const excBlock=block('List<String> needConfirmExceptions','[',']');
skill.needConfirmExceptions=[...excBlock.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(m=>unq('"'+m[1]+'"'));

// MANUAL 拆分
skill.manualSplits=parseRuleList(block('List<ManualSplitRule> manualSplits','[',']'),'ManualSplitRule')
  .map(r=>({
    pattern:r.pattern,
    fixed:{amount:r.fixedAmount, category:r.fixedCategory, sub:r.fixedSub||''},
    rest:{category:r.restCategory, sub:r.restSub||''},
    ...(r.note?{note:r.note}:{}),
  }));

// 特殊规则
const spBlock=block('SpecialRules specialRules','(',')');
const sp={};
for(const m of spBlock.matchAll(/(\w+)\s*:\s*("(?:[^"\\]|\\.)*"|true|false|-?\d+)/g)){
  sp[m[1]] = m[2]==='true'?true : m[2]==='false'?false : /^-?\d/.test(m[2])?parseFloat(m[2]) : unq(m[2]);
}
const refundBlock=block('refundKeywords','[',']');
skill.specialRules={
  refundKeywords:[...refundBlock.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(m=>unq('"'+m[1]+'"')),
  negativeAmountIsIncome: sp.negativeAmountIsIncome===true,
  refundKeepsOriginalCategory: sp.refundKeepsOriginalCategory!==false,
  fullRefundOffset:{ enabled: sp.fullRefundOffsetEnabled===true, windowDays: sp.fullRefundOffsetWindowDays||3, note: sp.fullRefundOffsetNote||'' },
  incomeWithoutRule:'AI 在 categories 清单中选择最贴切分类，经用户确认',
};

// accounts / flow
skill.accounts={ default: unq((src.match(/defaultAccount\s*=\s*("(?:[^"\\]|\\.)*")/)||[])[1]||'""'),
                 hint:'', bySource:{ wechat:'微信', alipay:'支付宝', bank:'对应银行卡' } };

const flowBlock=block('Map<String, Object> flow','{','}');
const flow={};
for(const m of flowBlock.matchAll(/"([^"]+)"\s*:\s*(\[[^\]]*\]|-?\d+)/g)){
  const key=m[1], raw=m[2];
  if(raw.startsWith('[')) flow[key]=[...raw.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(x=>unq('"'+x[1]+'"'));
  else flow[key]=parseFloat(raw);
}
skill.flow={
  question:{ batchSize:flow.questionBatchSize||3, fallbacks:flow.questionFallbacks||[], askTemplate:'以下 {count} 笔需要确认用途：', allowSkip:true },
  screenshot:{ fallbackToPlatformDefault:true, candidatesPerItem:3, allowSkip:true },
  dedupe:{ key:flow.dedupeKey||['time','merchant','amount'], windowDays:flow.dedupeWindowDays||1 },
  statePartitions:flow.statePartitions||['已确认','待确认','已跳过'],
};

fs.writeFileSync(outPath, JSON.stringify(skill,null,2));
console.log('✅ 从 skill_data.dart 逆向提取 →', outPath);
console.log('   分类:', Object.keys(skill.categories).length,
            '| 商户规则:', skill.merchantRules.length,
            '| 平台默认:', skill.platformDefaults.length,
            '| 需确认:', skill.needConfirm.length,
            '| 关键词类:', Object.keys(skill.keywordHints).length,
            '| 拆分:', skill.manualSplits.length);
