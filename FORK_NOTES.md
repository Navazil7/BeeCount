# BeeCount 二开补丁说明

本补丁给「图片记账」加入**人工确认环节**：识别结果先给用户核对/修改，点「保存所选」后才入库。

## 涉及文件（3 个）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `lib/pages/ai/image_bill_confirm_page.dart` | **新增**（确认页 UI，约 460 行） |
| 2 | `lib/utils/image_billing_helper.dart` | **替换**（识别后弹确认页，不再直接入库） |
| 3 | `lib/services/ai/ai_bookkeeper.dart` | **修改**（新增 `extractFromImage` / `persistAll` 两个公开方法） |

## 应用方式

```bash
node apply_patch.js <BeeCount源码根目录>
```

脚本是幂等的（重复跑不会重复插入），跑完会自检 5 项。

## 改动要点（便于人工复核或让其他 AI 复现）

### 1. `AiBookkeeper` 新增两个公开方法（不动原私有 `_persistAll`）

```dart
/// 只做「图片 → List<BillInfo>」提取，不落库
Future<({List<BillInfo> bills, String? errorMessage})> extractFromImage({
  required File image, required int ledgerId, String billGuard = '',
})

/// 把一批 BillInfo 落库（原 _persistAll 转公开）
Future<BookkeepingResult> persistAll({
  required List<BillInfo> bills, required int ledgerId,
  required List<String> billingTypes, AppLocalizations? l10n,
  Future<void> Function(int txId, int index)? onSaved,
})
```

### 2. `image_billing_helper.dart` 改成两步

```dart
// 原：final result = await bookkeeper.fromImage(...);  // 提取+入库一步到底
// 改：
final extracted = await bookkeeper.extractFromImage(image: imageFile, ledgerId: currentLedger.id,
    billGuard: PromptBuilder.billGuardForImage);
if (extracted.bills.isEmpty) { showToast(context, l10n.aiOcrNoBill); return; }
final result = await Navigator.of(context).push<BookkeepingResult>(MaterialPageRoute(
    builder: (_) => ImageBillConfirmPage(bills: extracted.bills, ledgerId: currentLedger.id,
        billingTypes: billingTypes, onSaved: ...)));
if (result == null) return;   // 用户取消 → 不入库
// 后续沿用原 PostProcessor.run + toast
```

### 3. 确认页 `ImageBillConfirmPage`

- 入参：`bills` / `ledgerId` / `billingTypes` / `onSaved`
- `initState` 里用 `repositoryProvider` 的 `getAllCategoriesIncludingShared()` + `getAvailableAccountsForLedger(ledgerId)`，
  把 AI 给的 `category`/`account` 名字**预解析成 id**（匹配不上的留空并标黄）
- 每笔一行：勾选框 + 类型（可点切换收/支）+ 金额 + 时间/备注 + 「分类」「账户」两个可点编辑 chip
- 分类编辑用 `showCategorySelector(context, type:, ledgerId:, currentCategoryId:)`
- 账户编辑用 `AccountPicker.show(context, selectedAccountId:)`
- 底部：已选笔数 + 合计金额 + 「取消」/「保存所选」；有未选分类时禁用保存并提示

## ⚠️ 三个坑（我踩过并已规避）

1. **不要动 `auto_billing_service.dart`** —— 那是后台自动截图路径，应保持"无确认直接入库"。
2. **保存前必须把用户选的分类名回填进 `BillInfo.category`** —— 否则 `BillCreationService._matchCategory` 会优先用 AI 原始名称匹配，用户的选择会被忽略。
3. **`BillInfo.copyWith` 是 `??` 语义，无法把字段置空** —— 所以"切了收/支后清空分类待重选"的状态要存在页面自己的状态里，不能靠 `copyWith(category: null)`。

## 不涉及的部分

- ❌ 不改数据库（无 schema 迁移）
- ❌ 不改云同步
- ❌ 不改服务端仓库 BeeCount-Cloud
---

## 追加改动（第二轮）：把你的 skill 规则引擎装进 App

### 问题
BeeCount 自带的 `category_matcher.dart` 用**它自己的分类名**（餐饮/交通/购物…）作为字典键，
而你的分类叫三餐/汽车/零食/…，导致规则字典**完全对不上、形同虚设**。
后果：AI 名字匹配不上就只能手选，且「保存」被阻塞。

### 改动
1. **`category_matcher.dart`**：字典键替换为**你的实际分类名**（叶子名优先），
   关键词来自你的 skill 规则（21 条）+ 平台默认推测 + 常用商户补充。
   覆盖 70 个分类、267 个关键词。
2. **`image_bill_confirm_page.dart`**：
   - 增加**规则预选**：AI 名字匹配不上时，自动跑规则字典 → 命中就选上（标「规则」）
   - 分类标签显示来源：`· AI` / `· 规则` / 空（手动选）
   - **解除「必须选分类才能保存」**：未选分类时弹窗确认一次，可「仍然保存」（记为「其它」）
