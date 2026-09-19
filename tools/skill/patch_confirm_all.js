/**
 * patch_confirm_all.js —— 所有图片识别路径都必须走 skill 确认流程
 *
 * 背景：原先只有「手动相册/拍照」走 ImageBillConfirmPage，
 * 「分享图片 / 截图自动记账」走 AutoBillingService.fromImage → 直接落库。
 * 用户要求：只要是根据图片识别的，一律先弹确认页，不允许直接落库。
 *
 * 做法：把 processScreenshot 里的 fromImage（提取+落库）换成
 *   extractFromImage（仅提取）→ globalNavigatorKey 推确认页 → 由确认页落库。
 */
const fs=require('fs'),path=require('path');
const SRC=process.argv[2];
if(!SRC){console.error('用法: node patch_confirm_all.js <源码根目录>');process.exit(2);}

const f=path.join(SRC,'lib/services/automation/auto_billing_service.dart');
let s=fs.readFileSync(f,'utf8');
if(s.includes('ImageBillConfirmPage')){
  console.log('⏭  auto_billing_service 已接入确认页');
  process.exit(0);
}

// ---------- 1) 加 import ----------
s=s.replace("import 'package:flutter_riverpod/flutter_riverpod.dart';",
  "import 'package:flutter/material.dart';\nimport 'package:flutter_riverpod/flutter_riverpod.dart';");
s=s.replace("import '../billing/post_processor.dart';",
  "import '../../main.dart' show globalNavigatorKey;\n" +
  "import '../../pages/ai/image_bill_confirm_page.dart';\n" +
  "import '../billing/post_processor.dart';");

// ---------- 2) 替换 fromImage 调用块 ----------
const lines=s.split('\n');
const start=lines.findIndex(l=>/final result = await _container.read\(aiBookkeeperProvider\).fromImage\(/.test(l));
if(start<0){ console.error('❌ 找不到 fromImage 调用'); process.exit(1); }
let depth=0,started=false,end=start;
for(let k=start;k<lines.length;k++){
  for(const ch of lines[k]){ if(ch==='('){depth++;started=true;} else if(ch===')'){depth--;} }
  if(started&&depth===0){ end=k; break; }
}

const newBlock = [
"      // 【fork 改造】所有图片识别都必须走 skill 的确认流程 —— 不再直接落库。",
"      // 1) 只提取，不入库",
"      final extracted =",
"          await _container.read(aiBookkeeperProvider).extractFromImage(",
"        image: file,",
"        ledgerId: ledgerId,",
"        billGuard: PromptBuilder.billGuardForImage,",
"      );",
"",
"      if (extracted.bills.isEmpty) {",
"        logger.info('AutoBilling', 'AI 未识别到账单，不入库');",
"        await _markAsProcessed(imagePath);",
"        if (showNotification) {",
"          final l10n =",
"              lookupAppLocalizations(PlatformDispatcher.instance.locale);",
"          await _showFinalNotification(",
"            progressId: notificationId,",
"            finalId: resultNotificationId,",
"            title: l10n.autoBillingNotifyNoBillTitle,",
"            body: l10n.autoBillingNotifyNoBillBody,",
"          );",
"        }",
"        return null;",
"      }",
"",
"      // 2) 弹确认页（识别结果必须经用户核对后才落库）",
"      final nav = globalNavigatorKey.currentState;",
"      if (nav == null) {",
"        // App 不在前台：不落库，通知引导用户打开 App 再确认",
"        logger.warning('AutoBilling', '无可用 Navigator，暂不落库（等待用户确认）');",
"        if (showNotification) {",
"          final l10n =",
"              lookupAppLocalizations(PlatformDispatcher.instance.locale);",
"          await _showFinalNotification(",
"            progressId: notificationId,",
"            finalId: resultNotificationId,",
"            title: l10n.autoBillingNotifyNoBillTitle,",
"            body: l10n.autoBillingNotifyNoBillBody,",
"          );",
"        }",
"        return null;",
"      }",
"",
"      final confirmResult = await nav.push<BookkeepingResult>(",
"        MaterialPageRoute(",
"          builder: (_) => ImageBillConfirmPage(",
"            bills: extracted.bills,",
"            ledgerId: ledgerId,",
"            billingTypes: const [",
"              TagSeedService.billingTypeImage,",
"              TagSeedService.billingTypeAi,",
"            ],",
"            onSaved: autoAddAttachment",
"                ? (txId, _) async {",
"                    try {",
"                      final attachmentService =",
"                          _container.read(attachmentServiceProvider);",
"                      await attachmentService.saveAttachment(",
"                        transactionId: txId,",
"                        sourceFile: file,",
"                        index: 0,",
"                        urgent: true,",
"                      );",
"                      _container",
"                          .read(attachmentListRefreshProvider.notifier)",
"                          .state++;",
"                    } catch (e, st) {",
"                      logger.error('AutoBilling', '保存截图附件失败', e, st);",
"                    }",
"                  }",
"                : null,",
"          ),",
"        ),",
"      );",
"",
"      await _markAsProcessed(imagePath);",
"",
"      // 用户取消 → 不入库",
"      if (confirmResult == null) {",
"        logger.info('AutoBilling', '用户在确认页取消，未落库');",
"        return null;",
"      }",
"      final result = confirmResult;",
].join('\n');

lines.splice(start, end-start+1, newBlock);
s=lines.join('\n');
fs.writeFileSync(f,s);
console.log('✅ auto_billing_service：fromImage → extractFromImage + 确认页');
