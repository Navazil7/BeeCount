import 'package:drift/drift.dart';

import 'category_service.dart';

/// 二开专用：为「钱迹 → 蜜蜂记账」迁移过来的分类补齐图标。
///
/// ## 为什么需要这个文件
///
/// 上游 [CategoryService.resolveIconNameByName] 只有约 40 条**通用中文关键字**，
/// 且是**顺序 if 链**，存在两类问题：
///
/// 1. **覆盖不足**：拿本项目真实的 89 个分类实测，有 32 个（36%）落到 `'circle'`
///    兜底，视觉上与占位图无异。
/// 2. **顺序误判**：`'水'/'电'` 规则排在 `'电子'` 之前，导致
///    `电子产品 / 电器 / 电瓶车 / 充电` 全被判成 **水费** 图标；
///    `'房'` 排在 `'运动'` 之前导致 `健身房` 被判成 **房子**；
///    `'衣'` 排在洗衣之前导致 `洗衣房` 被判成 **衣柜**。
///
/// ## 为什么不去改上游函数
///
/// `category_service.dart` 顶部注释写明该函数与服务端
/// `src/services/category_icon.py::resolve_icon_by_name` **1:1 对应**，两边改动要
/// 同步。改它会破坏两端一致性，且会影响「新建分类」的通用推导行为。
///
/// 因此这里采用**精确名覆盖 + 回退上游**的策略：只对已知的分类名做精确匹配，
/// 未命中的名字仍走上游逻辑。既修好本项目的数据，又不污染通用路径。
///
/// ## 生效方式
///
/// 由 `db.dart` 的 v34 迁移在升级时回填（只处理 icon 为空的分类，幂等、可重跑）。
class ForkCategoryIcons {
  ForkCategoryIcons._();

  /// 分类名 → Material 图标名（**必须**是 [CategoryService.getCategoryIcon] 的
  /// switch 里存在的名字，否则会落到 `Icons.category` 占位图）。
  ///
  /// 覆盖本项目钱迹迁移后的全部 89 个分类。
  static const Map<String, String> byName = <String, String>{
    // ── 餐饮 ──
    '三餐': 'restaurant',
    '外卖': 'restaurant',
    '下馆子': 'restaurant',
    '买菜': 'local_grocery_store',
    '水果': 'local_grocery_store',
    '零食': 'bakery_dining',
    '咖啡': 'local_cafe',
    '奶茶': 'local_cafe',
    '饮料': 'local_bar',

    // ── 交通 ──
    '交通': 'directions_transit',
    '地铁': 'subway',
    '打车': 'local_taxi',
    '顺风车': 'directions_car',
    '火车': 'train',
    '汽车': 'directions_car',
    '25汉dmi': 'directions_car',
    '电瓶车': 'electric_scooter',
    '电瓶车充电': 'electric_scooter',
    '充电': 'electric_bolt',
    '油费': 'local_gas_station',
    '停车费': 'local_parking',
    '车位租金': 'local_parking',
    '过路费': 'alt_route',
    '洗车': 'cleaning_services',
    '汽车罚款': 'receipt_long',
    '车险': 'verified',
    '维修保养': 'handyman',
    '配件': 'handyman',

    // ── 居住 / 家庭 ──
    '住房': 'home',
    '房租': 'home',
    '窝': 'house',
    '物业费': 'apartment',
    '水费': 'water_drop',
    '矿泉水': 'water_drop',
    '燃气': 'oil_barrel',
    '电器': 'electrical_services',
    '家具': 'chair',
    '日用品': 'shopping_basket',
    '清洁': 'dry_cleaning',
    '洗衣房': 'local_laundry_service',
    '搬家': 'local_shipping',
    '家人': 'family_restroom',
    '宠物': 'pets',
    '猫粮': 'pets',
    '猫砂': 'pets',
    '猫咪玩具': 'pets',

    // ── 购物 ──
    '衣饰': 'checkroom',
    '鞋子': 'checkroom',
    '二手置换': 'storefront',
    '眼镜': 'face',
    '耳机': 'headphones',
    '手机配件': 'devices_other',
    '电子产品': 'devices_other',

    // ── 健康 ──
    '医疗': 'medical_services',
    '疫苗': 'vaccines',
    '核酸': 'coronavirus',
    '安全套': 'health_and_safety',
    '运动': 'fitness_center',
    '健身房': 'fitness_center',
    '游泳': 'pool',

    // ── 娱乐 / 学习 ──
    '娱乐': 'sports_esports',
    '游戏': 'sports_esports',
    '电影': 'movie',
    '演出': 'theater_comedy',
    '麻将': 'casino',
    '练唱': 'music_video',
    'QQ音乐': 'music_note',
    '学习': 'menu_book',
    '照相': 'photo_camera',

    // ── 人情 / 收入 ──
    '人情': 'card_giftcard',
    '发红包': 'card_giftcard',
    '收红包': 'card_giftcard',
    '礼金': 'card_giftcard',
    '请客送礼': 'card_giftcard',
    '工资': 'attach_money',
    '奖金': 'attach_money',
    '外快': 'paid',
    '股票基金': 'savings',
    '退税': 'currency_exchange',

    // ── 其他 ──
    '日常': 'schedule',
    '聚会': 'groups',
    '恋爱': 'favorite',
    '旅行': 'card_travel',
    '快递': 'local_shipping',
    '话费': 'network_cell',
    '理发': 'content_cut',
    '党费': 'military_tech',
    '梯子': 'security',
    '其它': 'category',
  };

  /// 解析分类图标名：**精确名优先**，未命中回退上游通用推导。
  static String resolve(String name) {
    final exact = byName[name];
    if (exact != null) return exact;
    return CategoryService.resolveIconNameByName(name);
  }

  /// 该名字是否被本二开表精确覆盖（用于统计/自检）。
  static bool hasExact(String name) => byName.containsKey(name);

  /// 回填所有 `icon` 为 NULL/'' 的分类图标，返回更新条数。
  ///
  /// 幂等、可重复调用；**只碰空图标**，绝不覆盖用户手动选过的图标。
  ///
  /// 两个调用点：
  /// 1. `db.dart` 的 v34 迁移 —— 修好历史数据（钱迹导入的那批分类）；
  /// 2. `import_confirm_page.dart` 导入完成后 —— 让**将来**的导入也不再丢图标
  ///    （导入器本身没有 category_icon 的字段映射，见 v34 迁移里的说明）。
  static Future<int> backfillMissing(GeneratedDatabase db) async {
    final rows = await db
        .customSelect("SELECT id, name FROM categories WHERE icon IS NULL OR icon = ''")
        .get();
    var updated = 0;
    for (final row in rows) {
      final id = row.data['id'] as int;
      final name = row.data['name'] as String? ?? '';
      await db.customStatement(
        'UPDATE categories SET icon = ? WHERE id = ?',
        [resolve(name), id],
      );
      updated++;
    }
    return updated;
  }
}
