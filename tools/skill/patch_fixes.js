/**
 * patch_fixes.js —— 修复上游会把账目静默归错分类的兜底逻辑
 *
 * 问题：bill_creation_service._fallbackCategoryId 在找不到「其它」类分类时
 * 会 return categories.last。若某类（如收入）没有「其它」分类，所有匹配失败的
 * 账目都会被归到该类的【最后一个】分类上 —— 实测把「京东退款」错归成「二手置换」。
 *
 * 修复：找不到就返回 null，让账目留空（用户可见、可修正），而不是写错数据。
 */
const fs=require('fs'),path=require('path');
const SRC=process.argv[2];
if(!SRC){console.error('用法: node patch_fixes.js <源码根目录>');process.exit(2);}

const f=path.join(SRC,'lib/services/billing/bill_creation_service.dart');
let s=fs.readFileSync(f,'utf8');
if(s.includes('【fork 修复】兜底不再取最后一个分类')){
  console.log('⏭  _fallbackCategoryId 已修复');
  process.exit(0);
}
const old=`    final last = categories.last;
    logger.debug(_tag, '[分类兜底] 使用"\${last.name}"(ID:\${last.id})');
    return last.id;`;
if(!s.includes(old)){
  console.error('❌ 找不到 _fallbackCategoryId 的兜底锚点');
  process.exit(1);
}
s=s.replace(old, `    // 【fork 修复】兜底不再取最后一个分类。
    // 原逻辑若该类没有「其它」分类，会把所有未匹配账目归到 categories.last 上
    // （实测把「京东退款」静默错归成「二手置换」）。宁可留空，也不写错数据。
    logger.warning(_tag, '[分类兜底] 未找到「其它」类分类,留空等待用户指定');
    return null;`);
fs.writeFileSync(f,s);
console.log('✅ bill_creation_service._fallbackCategoryId 已修复（不再取最后一个）');
