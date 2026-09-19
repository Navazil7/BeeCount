import '../../data/db.dart';

/// 智能分类匹配服务 - 根据商家名称或文本内容匹配分类
class CategoryMatcher {
  // 分类关键词映射
  // === 用户规则字典（由 patch_rules.js 生成）===
  // 键 = 用户实际使用的分类名（优先叶子名，如 咖啡/打车/油费/游戏）
  // 由钱迹 skill 的 21 条商户规则 + 平台默认推测 + 常用商户补充而来。
  static const Map<String, List<String>> _categoryKeywords = {
    // 房租
    "房租": [
      '美的领贤', '租金', '领贤',
    ],
    // 住房
    "住房": [
      '美的领贤',
    ],
    // QQ音乐
    "QQ音乐": [
      '腾讯计算机系统', '腾讯计算机',
    ],
    // 娱乐
    "娱乐": [
      '腾讯计算机系统', 'Sapphire Entertainment', '腾讯天游', 'Valve',
    ],
    // 游戏
    "游戏": [
      'Sapphire Entertainment', '腾讯天游', 'Valve', 'Steam',
      'Sapphire', '网易游戏',
    ],
    // 话费
    "话费": [
      '手机充值', '中国联通', '充值', '移动',
      '联通', '电信', '中国移动',
    ],
    // 日常
    "日常": [
      '手机充值', '中国联通', '京东快递', '深圳市致远创想',
    ],
    // 快递
    "快递": [
      '京东快递', '菜鸟', '丰巢', '顺丰',
      '中通', '圆通', '申通', '韵达',
      '极兔',
    ],
    // 外卖
    "外卖": [
      '美团外卖', '饿了么', '美团', '肯德基',
      '麦当劳', '汉堡王', '真功夫',
    ],
    // 三餐
    "三餐": [
      '美团外卖', '盒马', '叮咚买菜', '饿了么',
      '摩登茶记', '白糖塘', '谢记大树烤肉', 'CHILL Pho',
      '大麦穗',
    ],
    // 咖啡
    "咖啡": [
      '星巴克', '瑞幸', 'costa', 'Manner',
      'Tims',
    ],
    // 零食
    "零食": [
      '星巴克', '瑞幸', 'costa',
    ],
    // 买菜
    "买菜": [
      '盒马', '叮咚买菜', '叮咚', '永辉',
      '华润万家', '菜市场', '美团买菜',
    ],
    // 打车
    "打车": [
      '滴滴出行', '滴滴', '高德', '曹操',
      'T3', '花小猪', '出租车',
    ],
    // 交通
    "交通": [
      '滴滴出行',
    ],
    // 油费
    "油费": [
      '中国石化', '中国石油', '加油站', '石化',
      '石油', '加油',
    ],
    // 汽车
    "汽车": [
      '中国石化', '中国石油', '加油站', '国家电网',
      '特来电', '小桔充电', 'ETC', '高速',
      '停车场', '停车费',
    ],
    // 充电
    "充电": [
      '国家电网', '特来电', '小桔充电', '小桔',
      '星星充电', '充电桩',
    ],
    // 过路费
    "过路费": [
      'ETC', '高速', '收费站',
    ],
    // 停车费
    "停车费": [
      '停车场', '停车',
    ],
    // 宠物
    "宠物": [
      '宠物猫粮', '宠物猫砂',
    ],
    // 下馆子
    "下馆子": [
      '摩登茶记', '白糖塘', '谢记大树烤肉', 'CHILL Pho',
      '大麦穗', '美团点餐', '团购', '火锅',
      '烤肉', '烧烤', '西贝', '海底捞',
      '茶记', 'Pho', '牛肉粉', '越南粉',
      '米粉', '面馆', '粉店', '快餐',
      '小炒', '川菜', '湘菜', '日料',
      '寿司',
    ],
    // 理发
    "理发": [
      '深圳市致远创想', '美发', '剪发', 'tony',
    ],
    // 日用品
    "日用品": [
      '京东', '淘宝', '拼多多', '天猫',
      '超市', '便利店', '屈臣氏',
    ],
    // 午餐
    "午餐": [
      '食堂', '工作餐',
    ],
    // 地铁
    "地铁": [
      '轨道交通',
    ],
    // 火车
    "火车": [
      '铁路', '12306', '火车票', '高铁',
    ],
    // 顺风车
    "顺风车": [
      '哈啰', '嘀嗒',
    ],
    // 电瓶车
    "电瓶车": [
      '电动车',
    ],
    // 电瓶车充电
    "电瓶车充电": [
    ],
    // 洗车
    "洗车": [
    ],
    // 车险
    "车险": [
      '保险',
    ],
    // 维修保养
    "维修保养": [
      '保养', '维修', '4S',
    ],
    // 汽车罚款
    "汽车罚款": [
      '违章', '罚款', '交警',
    ],
    // 奶茶
    "奶茶": [
      '喜茶', '奈雪', '蜜雪', '茶百道',
      '古茗', '一点点', '书亦', '茶颜悦色',
    ],
    // 饮料
    "饮料": [
      '可乐', '矿泉水', '怡宝', '农夫山泉',
    ],
    // 水果
    "水果": [
      '百果园', '鲜丰',
    ],
    // 车位租金
    "车位租金": [
      '车位',
    ],
    // 水费
    "水费": [
      '水务',
    ],
    // 物业费
    "物业费": [
      '物业',
    ],
    // 燃气
    "燃气": [
      '天然气',
    ],
    // 电费
    "电费": [
      '供电',
    ],
    // 搬家
    "搬家": [
      '货拉拉',
    ],
    // 清洁
    "清洁": [
      '保洁',
    ],
    // 家具
    "家具": [
      '宜家',
    ],
    // 电器
    "电器": [
      '苏宁', '国美',
    ],
    // 电影
    "电影": [
      '影院', '万达', 'CGV',
    ],
    // 旅行
    "旅行": [
      '携程', '飞猪', '去哪儿', '酒店',
      '民宿',
    ],
    // 麻将
    "麻将": [
      '棋牌',
    ],
    // 演出
    "演出": [
      '大麦', '话剧', '演唱会',
    ],
    // 梯子
    "梯子": [
      'VPN', '机场', 'v2ray', 'clash',
    ],
    // 游泳
    "游泳": [
      '泳池',
    ],
    // 健身房
    "健身房": [
      '健身', '瑜伽',
    ],
    // 猫粮
    "猫粮": [
      '猫罐头',
    ],
    // 猫砂
    "猫砂": [
    ],
    // 疫苗
    "疫苗": [
      '宠物医院', '驱虫',
    ],
    // 猫咪玩具
    "猫咪玩具": [
      '猫玩具', '逗猫棒',
    ],
    // 窝
    "窝": [
      '猫窝', '猫爬架',
    ],
    // 宠物零食
    "宠物零食": [
      '猫条',
    ],
    // 耳机
    "耳机": [
      'airpods', '耳麦',
    ],
    // 手机配件
    "手机配件": [
      '手机壳', '充电线', '数据线', '贴膜',
    ],
    // 学习
    "学习": [
      '课程', '培训', '考试', '买书',
      '学费', '深度求索', 'DeepSeek', 'openai',
      '订阅', 'API',
    ],
    // 练唱
    "练唱": [
      '声乐', 'KTV',
    ],
    // 安全套
    "安全套": [
      '避孕套', '冈本', '杜蕾斯',
    ],
    // 鞋子
    "鞋子": [
      '鞋', '耐克', '阿迪', '安踏',
      '李宁',
    ],
    // 眼镜
    "眼镜": [
      '镜片', '镜框',
    ],
    // 请客送礼
    "请客送礼": [
      '请客', '送礼',
    ],
    // 礼金
    "礼金": [
      '份子钱',
    ],
    // 发红包
    "发红包": [
      '红包',
    ],
    // 转账
    "转账": [
    ],
  };
  };

  /// 根据文本匹配最合适的分类
  /// 返回匹配的分类ID,如果没有匹配则返回null
  static int? matchCategory(String text, List<Category> categories) {
    if (text.isEmpty || categories.isEmpty) return null;

    final textLower = text.toLowerCase();

    // 记录每个分类的匹配分数
    final scores = <int, int>{};

    for (final category in categories) {
      final categoryName = category.name;
      int score = 0;

      // 查找该分类的关键词列表
      final keywords = _categoryKeywords[categoryName] ?? [];

      // 遍历关键词,计算匹配分数
      for (final keyword in keywords) {
        if (textLower.contains(keyword.toLowerCase())) {
          // 完全匹配得2分,部分匹配得1分
          score += textLower == keyword.toLowerCase() ? 2 : 1;
        }
      }

      // 如果分类名称本身出现在文本中,额外加分
      if (textLower.contains(categoryName.toLowerCase())) {
        score += 3;
      }

      if (score > 0) {
        scores[category.id] = score;
      }
    }

    // 找出得分最高的分类
    if (scores.isEmpty) return null;

    final bestMatch = scores.entries.reduce((a, b) => a.value > b.value ? a : b);
    return bestMatch.key;
  }

  /// 根据商家名称匹配分类
  static int? matchByMerchant(String? merchant, List<Category> categories) {
    if (merchant == null || merchant.isEmpty) return null;
    return matchCategory(merchant, categories);
  }

  /// 根据完整的OCR文本匹配分类
  static int? matchByFullText(String fullText, List<Category> categories) {
    if (fullText.isEmpty) return null;
    return matchCategory(fullText, categories);
  }

  /// 综合匹配:先尝试商家名称,再尝试完整文本
  static int? smartMatch({
    String? merchant,
    required String fullText,
    required List<Category> categories,
  }) {
    // 优先使用商家名称匹配
    if (merchant != null && merchant.isNotEmpty) {
      final merchantMatch = matchByMerchant(merchant, categories);
      if (merchantMatch != null) return merchantMatch;
    }

    // 如果商家名称没有匹配到,使用完整文本
    return matchByFullText(fullText, categories);
  }
}
