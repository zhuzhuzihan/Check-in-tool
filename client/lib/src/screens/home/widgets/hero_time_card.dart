import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../models/attendance.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/expressive_indicators.dart';

class HeroTimeCard extends StatelessWidget {
  const HeroTimeCard({
    super.key,
    required this.snapshot,
    required this.now,
    required this.todayWorked,
  });

  final DashboardSnapshot snapshot;
  final DateTime now;
  final Duration todayWorked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progress =
        (todayWorked.inSeconds / const Duration(hours: 8).inSeconds)
            .clamp(0.0, 1.0)
            .toDouble();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      container: true,
      label:
          '当前服务器校准时间 ${formatClock(now)}，${snapshot.state.label}，'
          '今日已工作 ${formatDuration(todayWorked)}',
      child: Material(
        color: colors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(32),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -54,
              top: -64,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.16,
                  child: M3EShape.sunny(
                    width: 210,
                    height: 210,
                    color: colors.onPrimary,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 42,
              bottom: -42,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.12,
                  child: M3EShape.c9SidedCookie(
                    width: 112,
                    height: 112,
                    color: colors.onPrimary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: colors.onPrimary),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _StatusPill(state: snapshot.state),
                        const Spacer(),
                        Icon(
                          Icons.cloud_done_rounded,
                          size: 18,
                          color: colors.onPrimary.withValues(alpha: 0.82),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '服务器已校时',
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.onPrimary.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedSwitcher(
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          child: Text(
                            formatClock(now),
                            key: ValueKey<int>(now.second),
                            maxLines: 1,
                            style: textTheme.displayLarge?.copyWith(
                              color: colors.onPrimary,
                              fontSize: 64,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatDate(now),
                      style: textTheme.titleMedium?.copyWith(
                        color: colors.onPrimary.withValues(alpha: 0.78),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '今日已工作',
                                style: textTheme.labelLarge?.copyWith(
                                  color: colors.onPrimary.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                formatDuration(todayWorked, showSeconds: true),
                                style: textTheme.headlineMedium?.copyWith(
                                  color: colors.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: textTheme.titleLarge?.copyWith(
                            color: colors.onPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return ExpressiveWavyProgressIndicator(
                          value: progress,
                          width: constraints.maxWidth,
                          height: 24,
                          color: colors.onPrimary,
                          backgroundColor: colors.onPrimary.withValues(
                            alpha: 0.22,
                          ),
                          animate: !disableAnimations,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '每日目标 8 小时',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.onPrimary.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});

  final AttendanceState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final working = state.isWorking;
    final background = working ? colors.tertiaryContainer : colors.onPrimary;
    final foreground = working ? colors.onTertiaryContainer : colors.primary;

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            working ? Icons.bolt_rounded : Icons.nightlight_round,
            color: foreground,
            size: 17,
          ),
          const SizedBox(width: 5),
          Text(
            state.label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
