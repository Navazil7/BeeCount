#!/usr/bin/env node
/**
 * verify_consistency.js —— 校验 skill_data.dart 用到的命名参数在 skill_definition.dart 里都存在
 *
 * 为什么需要：若两个文件不同步（例如数据先推、定义后推），CI 会报
 * "No named parameter with the name 'x'"。本脚本在本地提前发现。
 *
 * 实现：用**括号配平扫描**定位所有 Ctor(...) 调用，避免正则转义/跨类匹配的坑。
 *
 * 用法: node verify_consistency.js [skill_dart 目录]
 */
const fs=require('fs'),path=require('path');
const dir=process.argv[2]||__dirname;
const defSrc=fs.readFileSync(path.join(dir,'skill_definition.dart'),'utf8');
const dataSrc=fs.readFileSync(path.join(dir,'skill_data.dart'),'utf8');

/** 取某个类体的文本（从 class X 到配平的 } ） */
function classBody(src, cls){
  const i=src.indexOf('class '+cls);
  if(i<0) return null;
  const b=src.indexOf('{', i);
  let d=0;
  for(let k=b;k<src.length;k++){
    if(src[k]==='{')d++;
    else if(src[k]==='}'){ d--; if(d===0) return src.slice(i,k+1); }
  }
  return null;
}
/** 扫描 Ctor( ... ) 调用的参数体 */
function ctorBodies(src, ctor){
  const out=[]; const needle=ctor+'('; let idx=0;
  while(true){
    const i=src.indexOf(needle, idx);
    if(i<0) break;
    let k=i+needle.length, depth=1, inStr=false, esc=false;
    for(;k<src.length;k++){
      const c=src[k];
      if(inStr){ if(esc)esc=false; else if(c==='\\')esc=true; else if(c==='"')inStr=false; continue; }
      if(c==='"'){ inStr=true; continue; }
      if(c==='(')depth++;
      else if(c===')'){ depth--; if(depth===0) break; }
    }
    out.push(src.slice(i+needle.length,k));
    idx=k+1;
  }
  return out;
}
/** 类里构造函数声明的参数名集合 */
function declaredParams(body){
  const names=new Set();
  // 只取第一个 const Xxx( ... ) 构造
  const i=body.search(/const\s+\w+\s*\(/);
  if(i<0) return names;
  const b=body.indexOf('(', i);
  let d=0, e=b;
  for(let k=b;k<body.length;k++){
    if(body[k]==='(')d++;
    else if(body[k]===')'){ d--; if(d===0){ e=k; break; } }
  }
  const decl=body.slice(b+1,e);
  for(const m of decl.matchAll(/(?:this\.(\w+))|(?:required\s+[\w<>?,\s]*?\s(\w+))\s*[,)]/g)){
    if(m[1]) names.add(m[1]);
    else if(m[2]) names.add(m[2]);
  }
  // 兜底：把 this.xxx 与 "类型 xxx," 都抓一遍
  for(const m of decl.matchAll(/this\.(\w+)/g)) names.add(m[1]);
  for(const m of decl.matchAll(/^\s*(?:required\s+)?[\w<>?]+(?:<[^>]*>)?\s+(\w+)\s*[,)]/gm)) names.add(m[1]);
  return names;
}

let bad=0;
for(const cls of ['MerchantRule','NeedConfirmRule','ManualSplitRule','SpecialRules']){
  const body=classBody(defSrc, cls);
  if(!body){ console.log('❌ skill_definition.dart 缺 class '+cls); bad++; continue; }
  const params=declaredParams(body);
  const used=new Set();
  for(const b of ctorBodies(dataSrc, cls)){
    for(const m of b.matchAll(/(\w+)\s*:/g)) used.add(m[1]);
  }
  const missing=[...used].filter(p=>!params.has(p));
  if(missing.length){
    console.log('❌ '+cls+' 用到但定义里没有: '+missing.join(', '));
    bad++;
  } else {
    console.log('  ✅ '+cls+': 用到 ['+[...used].sort().join(', ')+'] 全部存在于定义 ['+[...params].sort().join(', ')+']');
  }
}
if(bad){ console.log('\n⚠️ '+bad+' 处不一致 —— 会导致 CI 编译失败'); process.exit(1); }
console.log('\n🎉 skill_data.dart 与 skill_definition.dart 参数完全一致');
