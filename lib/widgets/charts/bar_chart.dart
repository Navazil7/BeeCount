import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 柱状图 —— 用于「按时间分布」的**离散分桶**数据（每月支出、每日支出…）。
///
/// ## 为什么在洞察页取代折线图
///
/// `analytics_page.dart` 的数据是离散分桶：月视图 = 每天一个桶、年视图 = 12 个月、
/// 全部 = 按年。折线图的**斜率**会暗示"连续变化趋势"，而离散桶之间并不存在连续
/// 过渡。柱状图用**高度**表达量级，是更诚实的表达，也与「钱迹」统计页的做法一致
/// （其「每日统计」用的就是柱状图）。
///
/// 折线图另有一处噪音：它把数值标注在**每一个点**上，31 天就是 31 个标签。
/// 本实现只在**当前高亮的那根柱子**上标数值，其余靠读高度 + 左侧 Y 轴刻度。
///
/// ## 与 LineChart 的关系
///
/// 参数协议刻意与 `line_chart.dart` 对齐（`values` / `xLabels` / `highlightIndex` /
/// `onSwipeLeft` / `onSwipeRight` / `showHint` …），便于在调用点原地替换。
/// 折线图**仍然保留**给真正的连续趋势场景（净值走势、结余趋势），不要一并替换。
class BarChart extends StatefulWidget {
  final List<double> values;
  final List<String> xLabels;
  final int? highlightIndex;
  final bool hideAmounts;
  final Color themeColor;
  final double cornerRadius;
  final double barCornerRadius;
  final double xLabelFontSize;
  final double yLabelFontSize;
  final bool isDark;
  final bool showHint;
  final String? hintText;
  final VoidCallback? onCloseHint;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  /// 点击某根柱子的回调（索引）。为 null 时只做本地高亮，不通知外部。
  final ValueChanged<int>? onBarTap;

  const BarChart({
    super.key,
    required this.values,
    required this.xLabels,
    required this.highlightIndex,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.hideAmounts = false,
    required this.themeColor,
    this.cornerRadius = 12,
    this.barCornerRadius = 3,
    this.xLabelFontSize = 10,
    this.yLabelFontSize = 10,
    this.isDark = false,
    this.showHint = false,
    this.hintText,
    this.onCloseHint,
    this.onBarTap,
  });

  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  /// 用户点选过的柱子索引（本地状态）。点选后数值标签跟随它，
  /// 这样即使外层不改 highlightIndex，点图表也有即时反馈。
  int? _tapped;

  @override
  Widget build(BuildContext context) {
    final activeIndex = _tapped ?? widget.highlightIndex;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final n = widget.values.length;
            if (n == 0) return;
            final w = constraints.maxWidth;
            if (w <= 0) return;
            final i = (details.localPosition.dx / (w / n)).floor();
            if (i < 0 || i >= n) return;
            setState(() => _tapped = i);
            widget.onBarTap?.call(i);
          },
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < 0) {
              widget.onSwipeLeft();
            } else if (v > 0) {
              widget.onSwipeRight();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _BarPainter(
                  values: widget.values,
                  xLabels: widget.xLabels,
                  highlightIndex: activeIndex,
                  hideAmounts: widget.hideAmounts,
                  themeColor: widget.themeColor,
                  cornerRadius: widget.cornerRadius,
                  barCornerRadius: widget.barCornerRadius,
                  xLabelFontSize: widget.xLabelFontSize,
                  yLabelFontSize: widget.yLabelFontSize,
                  isDark: widget.isDark,
                ),
              ),
              if (widget.showHint && (widget.hintText?.isNotEmpty ?? false))
                Positioned(
                  right: 8,
                  top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BeeTokens.dividerStatic,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swipe,
                            size: 12,
                            color: BeeTokens.textSecondary(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.hintText!,
                            style: TextStyle(
                              fontSize: 10,
                              color: BeeTokens.textSecondary(context),
                            ),
                          ),
                          if (widget.onCloseHint != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: widget.onCloseHint,
                              child: Icon(
                                Icons.close,
                                size: 13,
                                color: BeeTokens.textSecondary(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<double> values;
  final List<String> xLabels;
  final int? highlightIndex;
  final bool hideAmounts;
  final Color themeColor;
  final double cornerRadius;
  final double barCornerRadius;
  final double xLabelFontSize;
  final double yLabelFontSize;
  final bool isDark;

  _BarPainter({
    required this.values,
    required this.xLabels,
    required this.highlightIndex,
    required this.hideAmounts,
    required this.themeColor,
    required this.cornerRadius,
    required this.barCornerRadius,
    required this.xLabelFontSize,
    required this.yLabelFontSize,
    required this.isDark,
  });

  Color get primaryTextColor =>
      isDark ? Colors.white : BeeTokens.primaryTextStatic;

  Color get secondaryTextColor =>
      isDark ? Colors.white70 : BeeTokens.secondaryTextStatic;

  /// 把轴上限抬到"好看"的整数（1 / 2 / 2.5 / 5 / 10 × 10^n）。
  /// 这样 Y 轴刻度是 0 / 500 / 1K / 1.5K / 2K 这种可读值，而不是 0 / 437 / 874…
  static double _niceMax(double v) {
    if (v <= 0) return 1;
    final exp = (math.log(v) / math.ln10).floor();
    final base = math.pow(10, exp).toDouble();
    final f = v / base;
    double nf;
    if (f <= 1) {
      nf = 1;
    } else if (f <= 2) {
      nf = 2;
    } else if (f <= 2.5) {
      nf = 2.5;
    } else if (f <= 5) {
      nf = 5;
    } else {
      nf = 10;
    }
    return nf * base;
  }

  static String _fmtAxis(double v) {
    if (v >= 10000) {
      final d = v / 10000;
      return d == d.roundToDouble()
          ? '${d.toStringAsFixed(0)}w'
          : '${d.toStringAsFixed(1)}w';
    }
    if (v >= 1000) {
      final d = v / 1000;
      return d == d.roundToDouble()
          ? '${d.toStringAsFixed(0)}k'
          : '${d.toStringAsFixed(1)}k';
    }
    return v.toStringAsFixed(0);
  }

  static String _fmtValue(double v) {
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 背景（与 LineChart 同款配色：亮色纯白，暗色用 dividerStatic 的分隔灰，
    // 这样在纯黑页面上图表区域仍是可辨识的一块）
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)),
      Paint()..color = isDark ? BeeTokens.dividerStatic : Colors.white,
    );

    if (values.isEmpty) return;

    final maxV = values.reduce(math.max);
    final axisMax = _niceMax(maxV == 0 ? 1 : maxV);

    const topPadding = 16.0; // 给高亮柱的数值标签留位置
    const bottomPadding = 18.0; // X 轴标签
    const tickCount = 4; // 4 段 → 5 条刻度（含 0）

    // ── Y 轴刻度：先量出最宽标签，决定左侧留白 ──
    final tickStyle = TextStyle(
      fontSize: yLabelFontSize,
      color: secondaryTextColor,
    );
    final axisLabelStyle = TextStyle(
      fontSize: yLabelFontSize,
      color: secondaryTextColor,
    );
    final tickTexts = <String>[];
    var maxLabelW = 0.0;
    for (int i = 0; i <= tickCount; i++) {
      final v = axisMax * i / tickCount;
      final t = _fmtAxis(v);
      tickTexts.add(t);
      final tp = TextPainter(
        text: TextSpan(text: t, style: tickStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > maxLabelW) maxLabelW = tp.width;
    }
    final leftGutter = maxLabelW + 8;

    final chartW = size.width - leftGutter - 8;
    final chartH = size.height - topPadding - bottomPadding;
    if (chartW <= 0 || chartH <= 0) return;

    double yFor(double v) => topPadding + chartH * (1 - v / axisMax);

    // ── 网格线 + Y 轴标签（只画浅色横线，不画竖线，保持干净） ──
    final gridPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 0; i <= tickCount; i++) {
      final v = axisMax * i / tickCount;
      final y = yFor(v);
      canvas.drawLine(
        Offset(leftGutter, y),
        Offset(size.width - 8, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: tickTexts[i], style: axisLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftGutter - 6 - tp.width, y - tp.height / 2));
    }

    // ── 柱子 ──
    final n = values.length;
    final slot = chartW / n;
    // 柱子占槽宽的 58%，并留 1px 以上的间隙
    final barW = math.max(2.0, math.min(slot * 0.58, 28.0));

    for (int i = 0; i < n; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final cx = leftGutter + slot * (i + 0.5);
      final top = yFor(v);
      final h = (topPadding + chartH) - top;
      if (h <= 0) continue;
      final isHi = highlightIndex != null && i == highlightIndex;
      final paint = Paint()
        ..color = isHi
            ? themeColor
            : themeColor.withValues(alpha: 0.55)
        ..isAntiAlias = true;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, top, barW, h),
        topLeft: Radius.circular(barCornerRadius),
        topRight: Radius.circular(barCornerRadius),
      );
      canvas.drawRRect(r, paint);
    }

    // ── 只在"当前高亮"柱上标数值（避免折线图那种满屏标签） ──
    if (!hideAmounts && highlightIndex != null) {
      final i = highlightIndex!;
      if (i >= 0 && i < n && values[i] > 0) {
        final cx = leftGutter + slot * (i + 0.5);
        final tp = TextPainter(
          text: TextSpan(
            text: _fmtValue(values[i]),
            style: TextStyle(
              fontSize: yLabelFontSize,
              color: primaryTextColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slot * 2);
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, yFor(values[i]) - tp.height - 3),
        );
      }
    }

    // ── X 轴标签：抽样，但**首尾必留**，最多 6 个 ──
    if (xLabels.isNotEmpty) {
      final baseStyle =
          TextStyle(fontSize: xLabelFontSize, color: secondaryTextColor);
      final hiStyle = TextStyle(
        fontSize: xLabelFontSize,
        color: primaryTextColor,
        fontWeight: FontWeight.w600,
      );
      final m = xLabels.length;
      final maxLabels = 6;
      final step = m <= maxLabels ? 1 : (m / maxLabels).ceil();
      final drawn = <int>{};
      for (int i = 0; i < m; i += step) {
        drawn.add(i);
      }
      drawn.add(m - 1); // 末位标签始终显示，避免"最后一根柱子没有标签"
      for (final i in drawn) {
        if (i < 0 || i >= m) continue;
        final tp = TextPainter(
          text: TextSpan(
            text: xLabels[i],
            style: (highlightIndex != null && i == highlightIndex)
                ? hiStyle
                : baseStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slot * 2);
        // 用与柱子相同的槽位中心，保证标签正对柱子
        final cx = leftGutter + slot * (i + 0.5);
        tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height - 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) {
    // 注意：这里比 LineChart 的 shouldRepaint 更严格 —— 旧实现漏比了
    // themeColor / 尺寸类参数，导致换主题色后图表不重绘。
    return old.values != values ||
        old.xLabels != xLabels ||
        old.highlightIndex != highlightIndex ||
        old.hideAmounts != hideAmounts ||
        old.themeColor != themeColor ||
        old.cornerRadius != cornerRadius ||
        old.barCornerRadius != barCornerRadius ||
        old.xLabelFontSize != xLabelFontSize ||
        old.yLabelFontSize != yLabelFontSize ||
        old.isDark != isDark;
  }
}
