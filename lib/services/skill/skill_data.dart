/// ⚠️ 本文件是 skill 的【唯一真相源】（方案 C：硬编码为真相源）。
///
/// - 规则数据全部在这里，编译期有类型检查（拼错字段/键名会立刻编译失败）
/// - 导出：App 内「导出 Skill」或 tools/skill/extract_from_dart.js（单向序列化，不会漂移）
/// - 结构刻意做成"表格化"，便于 AI 阅读与逆向导出
library;

import 'skill_definition.dart';

class SkillData {
  SkillData._();

  static const int schemaVersion = 2;
  static const String skillName = "wechat-bill-agent";

  /// 分类合法性清单（一级 → 二级）
  static const Map<String, List<String>> categories = {
    "三餐": ["买菜", "外卖", "下馆子", "午餐", ""],
    "汽车": ["25汉dmi", "过路费", "停车费", "充电", "油费", "洗车", "配件", "车险", "维修保养", "汽车罚款", ""],
    "股票基金": [""],
    "恋爱": [""],
    "宠物": ["猫砂", "窝", "零食", "疫苗", "猫粮", "猫咪玩具", ""],
    "电子产品": ["耳机", "手机配件", ""],
    "工资": [""],
    "人情": ["请客送礼", "礼金", "发红包", ""],
    "日常": ["话费", "理发", "党费", "快递", "矿泉水", "洗衣房", "照相", "核酸", ""],
    "住房": ["房租", "车位租金", "家具", "电器", "清洁", "燃气", "搬家", "水费", "物业费", ""],
    "娱乐": ["QQ音乐", "游戏", "旅行", "电影", "梯子", "麻将", "演出", ""],
    "交通": ["打车", "地铁", "火车", "顺风车", "电瓶车", "电瓶车充电", ""],
    "零食": ["奶茶", "饮料", "水果", "咖啡", ""],
    "收红包": [""],
    "退税": [""],
    "外快": ["顺风车", ""],
    "聚会": [""],
    "衣饰": ["鞋子", "眼镜", ""],
    "医疗": [""],
    "日用品": ["安全套", ""],
    "提升": ["学习", "练唱"],
    "家人": [""],
    "奖金": [""],
    "二手置换": [""],
    "其它": [""],
    "麻将": [""],
    "运动": ["游泳", "健身房"],
  };

  /// 商户规则 —— **顺序即优先级，首个命中即止**
  static const List<MerchantRule> merchantRules = [
    // ⚠️ 必须排在平台默认之前：否则「美团金融还款」会被当成美团外卖
    MerchantRule(
        pattern: "美团金融|金融还款|还款|信用卡还款",
        category: "其它",
        note: "信贷还款，非消费"),
    MerchantRule(pattern: "美的领贤", category: "住房", sub: "房租"),
    MerchantRule(pattern: "言己领贤|自己领贤", manual: true, reason: "金额需拆分：固定车位租金 260，余额为汽车-充电（如 300.60 → 260 车位租金 + 40.6 充电）"),
    MerchantRule(pattern: "腾讯计算机系统", category: "娱乐", sub: "QQ音乐"),
    MerchantRule(pattern: "Sapphire Entertainment", category: "娱乐", sub: "游戏"),
    MerchantRule(pattern: "手机充值|中国联通", category: "日常", sub: "话费"),
    MerchantRule(pattern: "腾讯天游", category: "娱乐", sub: "游戏"),
    MerchantRule(pattern: "京东快递", category: "日常", sub: "快递"),
    MerchantRule(pattern: "美团外卖", category: "三餐", sub: "外卖"),
    MerchantRule(pattern: "星巴克|瑞幸|costa", category: "零食", sub: "咖啡"),
    MerchantRule(pattern: "盒马|叮咚买菜", category: "三餐", sub: "买菜"),
    MerchantRule(pattern: "滴滴出行", category: "交通", sub: "打车"),
    MerchantRule(pattern: "中国石化|中国石油|加油站", category: "汽车", sub: "油费"),
    MerchantRule(pattern: "国家电网|特来电|小桔充电", category: "汽车", sub: "充电"),
    MerchantRule(pattern: "ETC|高速", category: "汽车", sub: "过路费"),
    MerchantRule(pattern: "停车场|停车费", category: "汽车", sub: "停车费"),
    MerchantRule(pattern: "饿了么", category: "三餐", sub: "外卖"),
    MerchantRule(pattern: "宠物.*猫粮|宠物.*猫砂", category: "宠物", sub: ""),
    MerchantRule(pattern: "Valve", category: "娱乐", sub: "游戏"),
    MerchantRule(pattern: "摩登茶记", category: "三餐", sub: "下馆子"),
    MerchantRule(pattern: "白糖塘", category: "三餐", sub: "下馆子"),
    MerchantRule(pattern: "谢记大树烤肉|CHILL Pho|大麦穗", category: "三餐", sub: "下馆子"),
    MerchantRule(pattern: "深圳市致远创想", category: "日常", sub: "理发"),
  ];

  /// 平台默认推测（账单只显示平台名时使用）
  static const List<MerchantRule> platformDefaults = [
    MerchantRule(pattern: "美团", category: "三餐", sub: "外卖", note: "外卖/团购场景"),
    MerchantRule(pattern: "京东", category: "日用品", note: "电商默认"),
    MerchantRule(pattern: "淘宝", category: "日用品", note: "电商默认"),
    MerchantRule(pattern: "拼多多", category: "日用品", note: "电商默认"),
    MerchantRule(pattern: "天猫", category: "日用品", note: "电商默认"),
  ];

  /// 需确认清单
  static const List<NeedConfirmRule> needConfirm = [
    NeedConfirmRule(
        pattern: "还款",
        type: "question",
        hint: "信贷/信用卡还款，分类需用户确认"),
    NeedConfirmRule(
        pattern: "退款|退货",
        type: "question",
        hint: "退款入账，分类需用户确认（skill：与原始支出一致）"),
    NeedConfirmRule(pattern: "亲属卡交易", type: "question", hint: "亲属卡代付，用途需用户口述确认"),
    NeedConfirmRule(pattern: "微信红包-发出群红包", type: "question", hint: "群红包支出，用途/对象需用户确认"),
    NeedConfirmRule(pattern: "美团", type: "screenshot", hint: "需美团账单截图，推测分类后提问确认"),
    NeedConfirmRule(pattern: "京东", type: "screenshot", hint: "需京东账单截图，推测分类后提问确认"),
    NeedConfirmRule(pattern: "淘宝", type: "screenshot", hint: "需淘宝账单截图，推测分类后提问确认"),
    NeedConfirmRule(pattern: "拼多多", type: "screenshot", hint: "需拼多多账单截图，推测分类后提问确认"),
    NeedConfirmRule(pattern: "天猫", type: "screenshot", hint: "需天猫账单截图，推测分类后提问确认"),
  ];

  /// 需确认清单的例外（命中即放行）
  static const List<String> needConfirmExceptions = [
  ];

  /// MANUAL 金额拆分
  static const List<ManualSplitRule> manualSplits = [
    ManualSplitRule(
      pattern: "言己领贤|自己领贤",
      fixedAmount: 260,
      fixedCategory: "住房",
      fixedSub: "车位租金",
      restCategory: "汽车",
      restSub: "充电",
      note: "固定车位租金 260，余额为汽车-充电（如 300.60 → 260 + 40.6）",
    ),
  ];

  /// 关键词提示（分类名 → 关键词；覆盖广，优先级低于 merchantRules）
  static const Map<String, List<String>> keywordHints = {
    "房租": ["美的领贤", "租金", "领贤"],
    "住房": ["美的领贤"],
    "QQ音乐": ["腾讯计算机系统", "腾讯计算机"],
    "娱乐": ["腾讯计算机系统", "Sapphire Entertainment", "腾讯天游", "Valve"],
    "游戏": ["Sapphire Entertainment", "腾讯天游", "Valve", "Steam", "Sapphire", "网易游戏"],
    "话费": ["手机充值", "中国联通", "充值", "移动", "联通", "电信", "中国移动"],
    "日常": ["手机充值", "中国联通", "京东快递", "深圳市致远创想"],
    "快递": ["京东快递", "菜鸟", "丰巢", "顺丰", "中通", "圆通", "申通", "韵达", "极兔"],
    "外卖": ["美团外卖", "饿了么", "美团", "肯德基", "麦当劳", "汉堡王", "真功夫"],
    "三餐": ["美团外卖", "盒马", "叮咚买菜", "饿了么", "摩登茶记", "白糖塘", "谢记大树烤肉", "CHILL Pho", "大麦穗"],
    "咖啡": ["星巴克", "瑞幸", "costa", "Manner", "Tims"],
    "零食": ["星巴克", "瑞幸", "costa"],
    "买菜": ["盒马", "叮咚买菜", "叮咚", "永辉", "华润万家", "菜市场", "美团买菜"],
    "打车": ["滴滴出行", "滴滴", "高德", "曹操", "T3", "花小猪", "出租车"],
    "交通": ["滴滴出行"],
    "油费": ["中国石化", "中国石油", "加油站", "石化", "石油", "加油"],
    "汽车": ["中国石化", "中国石油", "加油站", "国家电网", "特来电", "小桔充电", "ETC", "高速", "停车场", "停车费"],
    "充电": ["国家电网", "特来电", "小桔充电", "小桔", "星星充电", "充电桩"],
    "过路费": ["ETC", "高速", "收费站"],
    "停车费": ["停车场", "停车"],
    "宠物": ["宠物猫粮", "宠物猫砂"],
    "下馆子": ["摩登茶记", "白糖塘", "谢记大树烤肉", "CHILL Pho", "大麦穗", "美团点餐", "团购", "火锅", "烤肉", "烧烤", "西贝", "海底捞", "茶记", "Pho", "牛肉粉", "越南粉", "米粉", "面馆", "粉店", "快餐", "小炒", "川菜", "湘菜", "日料", "寿司", "炸鸡", "炸串", "麻辣烫", "冒菜", "盖浇饭", "卤味"],
    "理发": ["深圳市致远创想", "美发", "剪发", "tony"],
    "日用品": ["京东", "淘宝", "拼多多", "天猫", "超市", "便利店", "屈臣氏"],
    "午餐": ["食堂", "工作餐"],
    "地铁": ["轨道交通"],
    "火车": ["铁路", "12306", "火车票", "高铁"],
    "顺风车": ["哈啰", "嘀嗒"],
    "电瓶车": ["电动车"],
    "电瓶车充电": [],
    "洗车": [],
    "车险": ["保险"],
    "维修保养": ["保养", "维修", "4S"],
    "汽车罚款": ["违章", "罚款", "交警"],
    "奶茶": ["喜茶", "奈雪", "蜜雪", "茶百道", "古茗", "一点点", "书亦", "茶颜悦色"],
    "饮料": ["可乐", "汽水"],
    "矿泉水": ["怡宝", "农夫山泉", "纯净水"],
    "水果": ["百果园", "鲜丰"],
    "车位租金": ["车位"],
    "水费": ["水务"],
    "物业费": ["物业"],
    "燃气": ["天然气"],
    "搬家": ["货拉拉"],
    "清洁": ["保洁"],
    "家具": ["宜家"],
    "电器": ["苏宁", "国美"],
    "电影": ["影院", "万达", "CGV"],
    "旅行": ["携程", "飞猪", "去哪儿", "酒店", "民宿"],
    "麻将": ["棋牌"],
    "演出": ["大麦", "话剧", "演唱会"],
    "梯子": ["VPN", "机场", "v2ray", "clash"],
    "游泳": ["泳池"],
    "健身房": ["健身", "瑜伽"],
    "猫粮": ["猫罐头"],
    "猫砂": [],
    "疫苗": ["宠物医院", "驱虫"],
    "猫咪玩具": ["猫玩具", "逗猫棒"],
    "窝": ["猫窝", "猫爬架"],
    "耳机": ["airpods", "耳麦"],
    "手机配件": ["手机壳", "充电线", "数据线", "贴膜"],
    "学习": ["课程", "培训", "考试", "买书", "学费", "深度求索", "DeepSeek", "openai", "订阅", "API"],
    "练唱": ["声乐", "KTV"],
    "安全套": ["避孕套", "冈本", "杜蕾斯"],
    "鞋子": ["鞋", "耐克", "阿迪", "安踏", "李宁"],
    "眼镜": ["镜片", "镜框"],
    "请客送礼": ["请客", "送礼"],
    "礼金": ["份子钱"],
    "发红包": ["红包"],
    "工资": ["薪资", "薪酬", "发薪", "月薪"],
    "收红包": ["收到红包", "红包收入", "领取红包"],
    "退税": ["个税", "税务"],
    "外快": ["副业", "私活", "接单"],
    "奖金": ["年终奖", "绩效"],
    "股票基金": ["基金", "股票", "证券", "理财"],
    "二手置换": ["闲鱼", "转转", "卖二手", "二手"],
    "聚会": ["聚餐", "团建"],
    "恋爱": ["约会", "鲜花"],
    "家人": ["给爸妈", "孝敬", "父母"],
    "党费": [],
    "洗衣房": ["洗衣", "干洗"],
    "照相": ["证件照", "摄影"],
    "核酸": ["抗原"],
    "配件": ["汽车配件", "车载", "脚垫", "行车记录仪"],
    "25汉dmi": ["比亚迪", "汉dmi", "车贷"],
    "医疗": ["医院", "药店", "诊所", "挂号", "看病", "药房", "体检", "药", "门诊"],
  };

  /// 特殊规则
  static const SpecialRules specialRules = SpecialRules(
    refundKeywords: ["退款", "退货"],
    negativeAmountIsIncome: true,
    refundKeepsOriginalCategory: true,
    fullRefundOffsetEnabled: true,
    fullRefundOffsetWindowDays: 3,
    fullRefundOffsetNote: "同商户、金额一致、退款在时间窗内 → 支出与退款两笔均不记录（净流水为 0）",
  );

  static const String defaultAccount = "";

  /// 子流程参数（提问批量、去重键、状态分区等）
  static const Map<String, Object> flow = {
    "questionBatchSize": 3,
    "questionFallbacks": ["采用推荐候选", "标记为 其它", "跳过本条"],
    "dedupeKey": ["time", "merchant", "amount"],
    "dedupeWindowDays": 1,
    "statePartitions": ["已确认", "待确认", "已跳过"],
  };

  /// 组装成运行时定义（matcher 使用）。纯内存操作，无 IO。
  static final SkillDefinition definition = SkillDefinition(
        schemaVersion: schemaVersion,
        name: skillName,
        categories: categories,
        merchantRules: merchantRules,
        platformDefaults: platformDefaults,
        needConfirm: needConfirm,
        needConfirmExceptions: needConfirmExceptions,
        manualSplits: manualSplits,
        keywordHints: keywordHints,
        specialRules: specialRules,
        flow: flow,
        defaultAccount: defaultAccount,
      );
}
