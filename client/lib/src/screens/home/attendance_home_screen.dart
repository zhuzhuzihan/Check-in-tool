import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../controllers/attendance_controller.dart';
import '../../models/attendance.dart';
import '../../widgets/expressive_indicators.dart';
import 'widgets/clock_toolbar.dart';
import 'widgets/hero_time_card.dart';
import 'widgets/weekly_hours_card.dart';
import 'widgets/work_insights.dart';

class AttendanceHomeScreen extends StatelessWidget {
  const AttendanceHomeScreen({super.key, required this.controller});

  final AttendanceController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        if (controller.isLoading && snapshot == null) {
          return const _LoadingView();
        }
        if (snapshot == null) {
          return _ErrorView(
            message: controller.loadError?.toString() ?? '无法加载打卡数据',
            onRetry: controller.refresh,
          );
        }

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: controller.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _PageHeader(
                                snapshot: snapshot,
                                isDemo: controller.isDemo,
                                isRefreshing: controller.isLoading,
                                onRefresh: controller.refresh,
                              ),
                              if (controller.notice != null) ...<Widget>[
                                const SizedBox(height: 16),
                                _NoticeBanner(
                                  message: controller.notice!,
                                  isError: controller.noticeIsError,
                                  onClose: controller.clearNotice,
                                ),
                              ],
                              const SizedBox(height: 20),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return _DashboardLayout(
                                    wide: constraints.maxWidth >= 840,
                                    snapshot: snapshot,
                                    now: controller.now,
                                    todayWorked: controller.liveTodayWorked,
                                    biometricAvailable:
                                        controller.biometricAvailable,
                                    onEnrollDevice: () => _showDeviceEnrollment(
                                      context,
                                      controller,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: ClockToolbar(
            state: snapshot.state,
            isSubmitting: controller.isSubmitting,
            biometricAvailable: controller.biometricAvailable,
            onClock: (touchMetrics, screenMetrics) => controller.clock(
              touchMetrics: touchMetrics,
              screenMetrics: screenMetrics,
            ),
          ),
        );
      },
    );
  }
}

class _DashboardLayout extends StatelessWidget {
  const _DashboardLayout({
    required this.wide,
    required this.snapshot,
    required this.now,
    required this.todayWorked,
    required this.biometricAvailable,
    required this.onEnrollDevice,
  });

  final bool wide;
  final DashboardSnapshot snapshot;
  final DateTime now;
  final Duration todayWorked;
  final bool biometricAvailable;
  final VoidCallback onEnrollDevice;

  @override
  Widget build(BuildContext context) {
    final hero = HeroTimeCard(
      snapshot: snapshot,
      now: now,
      todayWorked: todayWorked,
    );
    final secondary = Column(
      children: <Widget>[
        WeeklyHoursCard(hours: snapshot.weeklyHours, now: now),
        const SizedBox(height: 16),
        WorkInsights(
          snapshot: snapshot,
          biometricAvailable: biometricAvailable,
          onEnrollDevice: onEnrollDevice,
        ),
      ],
    );

    if (!wide) {
      return Column(
        children: <Widget>[hero, const SizedBox(height: 16), secondary],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 11, child: hero),
        const SizedBox(width: 18),
        Expanded(flex: 9, child: secondary),
      ],
    );
  }
}

Future<void> _showDeviceEnrollment(
  BuildContext context,
  AttendanceController controller,
) async {
  final input = TextEditingController();
  final token = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(Icons.phonelink_lock_rounded),
        title: const Text('登记此设备'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('输入管理员提供的设备登记令牌。令牌不会保存在设备中。'),
            const SizedBox(height: 16),
            TextField(
              controller: input,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '登记令牌',
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.of(dialogContext).pop(value.trim());
                }
              },
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = input.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            child: const Text('确认登记'),
          ),
        ],
      );
    },
  );
  input.dispose();
  if (token != null && context.mounted) {
    await controller.enrollCurrentDevice(token);
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.snapshot,
    required this.isDemo,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final DashboardSnapshot snapshot;
  final bool isDemo;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        M3EContainer.puffy(
          width: 52,
          height: 52,
          color: colors.primaryContainer,
          child: Center(
            child: Text(
              '林',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                snapshot.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '远程工作台',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (isDemo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              color: colors.tertiaryContainer,
              shape: const StadiumBorder(),
            ),
            child: Text(
              '演示',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onTertiaryContainer,
              ),
            ),
          ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: isRefreshing ? null : onRefresh,
          tooltip: '同步数据',
          icon: isRefreshing
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.sync_rounded),
        ),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.message,
    required this.isError,
    required this.onClose,
  });

  final String message;
  final bool isError;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.primaryContainer;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onPrimaryContainer;

    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          child: Row(
            children: <Widget>[
              Icon(
                isError ? Icons.error_rounded : Icons.check_circle_rounded,
                color: foreground,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: TextStyle(color: foreground)),
              ),
              IconButton(
                onPressed: onClose,
                tooltip: '关闭提示',
                icon: Icon(Icons.close_rounded, color: foreground, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ContainedExpressiveLoadingIndicator(
              size: 64,
              semanticsLabel: '正在同步打卡数据',
            ),
            const SizedBox(height: 18),
            Text('正在校准服务器时间', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  M3EContainer.softBurst(
                    width: 88,
                    height: 88,
                    color: colors.errorContainer,
                    child: Icon(
                      Icons.cloud_off_rounded,
                      color: colors.onErrorContainer,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '暂时无法连接',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  M3EButton.icon(
                    onPressed: onRetry,
                    size: M3EButtonSize.md,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新同步'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
