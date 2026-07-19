import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/attendance.dart';

class WeeklyHoursCard extends StatelessWidget {
  const WeeklyHoursCard({super.key, required this.hours, required this.now});

  final List<DailyHours> hours;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = hours.fold<double>(0, (sum, item) => sum + item.hours);
    final maxHours = hours.fold<double>(8, (value, item) {
      return math.max(value, item.hours);
    });
    final maxY = math.max(10.0, (maxHours + 1).ceilToDouble());
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Card(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '近七日节奏',
                        style: textTheme.titleLarge?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已记录 ${total.toStringAsFixed(1)} 小时',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.onSecondaryContainer.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: ShapeDecoration(
                    color: colors.secondary,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    '目标 40h',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.onSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 196,
              child: hours.isEmpty
                  ? Center(
                      child: Text(
                        '本周还没有工时记录',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    )
                  : Semantics(
                      label: _chartSemantics(hours),
                      child: ExcludeSemantics(
                        child: BarChart(
                          _chartData(context, maxY),
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 480),
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  BarChartData _chartData(BuildContext context, double maxY) {
    final colors = Theme.of(context).colorScheme;
    final labels = <int, String>{
      1: '一',
      2: '二',
      3: '三',
      4: '四',
      5: '五',
      6: '六',
      7: '日',
    };

    return BarChartData(
      minY: 0,
      maxY: maxY,
      alignment: BarChartAlignment.spaceAround,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 4,
        getDrawingHorizontalLine: (_) => FlLine(
          color: colors.onSecondaryContainer.withValues(alpha: 0.11),
          strokeWidth: 1,
          dashArray: const <int>[5, 5],
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= hours.length) {
                return const SizedBox.shrink();
              }
              final isToday = hours[index].day.weekday == now.weekday;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  labels[hours[index].day.weekday] ?? '',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          tooltipBorderRadius: BorderRadius.circular(14),
          getTooltipColor: (_) => colors.inverseSurface,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            return BarTooltipItem(
              '${rod.toY.toStringAsFixed(1)} 小时',
              TextStyle(
                color: colors.onInverseSurface,
                fontWeight: FontWeight.w700,
              ),
              textDirection: TextDirection.ltr,
            );
          },
        ),
      ),
      barGroups: List<BarChartGroupData>.generate(hours.length, (index) {
        final item = hours[index];
        final isToday = item.day.weekday == now.weekday;
        return BarChartGroupData(
          x: index,
          barRods: <BarChartRodData>[
            BarChartRodData(
              toY: item.hours,
              width: isToday ? 22 : 16,
              color: isToday ? colors.tertiary : colors.secondary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
                bottom: Radius.circular(4),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 8,
                color: colors.onSecondaryContainer.withValues(alpha: 0.08),
              ),
            ),
          ],
        );
      }),
    );
  }

  String _chartSemantics(List<DailyHours> entries) {
    const labels = <String>['一', '二', '三', '四', '五', '六', '日'];
    return entries
        .map(
          (item) =>
              '星期${labels[item.day.weekday - 1]} ${item.hours.toStringAsFixed(1)} 小时',
        )
        .join('，');
  }
}
