import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/core/prompt_builder.dart';
import '../ai/providers/ai_provider_config.dart';
import '../ai/providers/ai_provider_manager.dart';
import '../l10n/app_localizations.dart';
import '../pages/ai/image_bill_confirm_page.dart';
import '../providers.dart';
import '../providers/ai_chat_providers.dart';
import '../services/attachment_service.dart';
import '../services/ai/bookkeeping_result.dart';
import '../services/billing/post_processor.dart';
import '../services/data/tag_seed_service.dart';
import '../widgets/ui/ui.dart';

/// 图片记账入口(相册/相机)。瘦身后:UI 流程 + 兜底,业务调 [AiBookkeeper]。
///
/// 【二开改动】识别结果不再直接入库,而是先弹出确认页让用户核对/修改,
/// 用户点「保存所选」后才落库。原直连入库逻辑保留在
/// [AiBookkeeper.persistAll] 中,便于与上游合并。
class ImageBillingHelper {
  /// 从相册选择图片并自动记账
  static Future<void> pickImageForBilling(
    BuildContext context,
    WidgetRef ref,
  ) =>
      _processImageBilling(context, ref, ImageSource.gallery);

  /// 打开相机拍照并自动记账
  static Future<void> openCameraForBilling(
    BuildContext context,
    WidgetRef ref,
  ) =>
      _processImageBilling(context, ref, ImageSource.camera);

  static Future<void> _processImageBilling(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final l10n = AppLocalizations.of(context);

    try {
      // 1. 选图
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (pickedFile == null) return;
      if (!context.mounted) return;

      // 2. 显示 loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.aiOcrRecognizing),
                ],
              ),
            ),
          ),
        ),
      );

      final imageFile = File(pickedFile.path);

      // 3. AI vision 兜底
      if (!await AIProviderManager.isCapabilityConfigured(
          AICapabilityType.vision)) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        showToast(context, l10n.aiNotConfiguredHint);
        return;
      }

      // 4. 当前账本
      final currentLedger = await ref.read(currentLedgerProvider.future);
      if (currentLedger == null) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
        showToast(context, l10n.aiOcrNoLedger);
        return;
      }

      final autoAddAttachment = ref.read(smartBillingAutoAttachmentProvider);
      final billingTypes = <String>[
        source == ImageSource.gallery
            ? TagSeedService.billingTypeImage
            : TagSeedService.billingTypeCamera,
        TagSeedService.billingTypeAi,
      ];

      final bookkeeper = ref.read(aiBookkeeperProvider);

      // 5. 【二开】只提取，不入库
      final extracted = await bookkeeper.extractFromImage(
        image: imageFile,
        ledgerId: currentLedger.id,
        billGuard: PromptBuilder.billGuardForImage,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关掉 loading

      // 6. 【二开】没有识别到账单 → 与原生一致的提示
      if (extracted.bills.isEmpty) {
        showToast(context, l10n.aiOcrNoBill);
        return;
      }

      // 7. 【二开】弹确认页，用户核对/修改后才落库
      final attachmentService = ref.read(attachmentServiceProvider);
      final result = await Navigator.of(context).push<BookkeepingResult>(
        MaterialPageRoute(
          builder: (_) => ImageBillConfirmPage(
            bills: extracted.bills,
            ledgerId: currentLedger.id,
            billingTypes: billingTypes,
            // 多笔时每笔都挂同一张原图,方便后续从任意一笔溯源
            onSaved: autoAddAttachment
                ? (txId, _) => attachmentService.saveAttachment(
                      transactionId: txId,
                      sourceFile: imageFile,
                      index: 0,
                    )
                : null,
          ),
        ),
      );

      // 用户取消（或全部取消勾选）→ 不入库
      if (result == null) return;
      if (!context.mounted) return;

      // 8. 提示用户
      if (!result.success) {
        showToast(context,
            result.failedCount > 0 ? l10n.aiOcrCheckLog : l10n.aiOcrNoBill);
        return;
      }

      await PostProcessor.run(
        ref,
        ledgerId: currentLedger.id,
        tags: true,
        attachments: autoAddAttachment,
      );
      if (!context.mounted) return;

      final firstBill = result.firstBill!;
      final typeText = firstBill.type?.name == 'income'
          ? l10n.aiTypeIncome
          : l10n.aiTypeExpense;
      final amountStr = result.totalAbsAmount.toStringAsFixed(2);
      final toastText = result.isMulti
          ? '${l10n.aiOcrSuccess(typeText, amountStr)} × ${result.savedCount}'
          : l10n.aiOcrSuccess(typeText, amountStr);
      // 多币种降级提示(A5):缺汇率已按 1:1 暂记,指路统计页补折算
      showToast(
        context,
        result.unconvertedCurrencies.isEmpty
            ? toastText
            : '$toastText\n${l10n.aiBillingRateMissingHint(result.unconvertedCurrencies.join('、'))}',
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      showToast(context, l10n.aiOcrFailed(e.toString()));
    }
  }
}
