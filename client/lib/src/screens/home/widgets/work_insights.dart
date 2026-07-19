import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../models/attendance.dart';
import '../../../utils/formatters.dart';

class WorkInsights extends StatelessWidget {
  const WorkInsights({
    super.key,
    required this.snapshot,
    required this.biometricAvailable,
    required this.onEnrollDevice,
  });

  final DashboardSnapshot snapshot;
  final bool biometricAvailable;
  final VoidCallback onEnrollDevice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final streakCard = _StreakCard(days: snapshot.streakDays);
        final securityCard = _SecurityCard(
          biometricAvailable: biometricAvailable,
          deviceTrusted: snapshot.deviceTrusted,
          onEnrollDevice: onEnrollDevice,
        );

        if (constraints.maxWidth < 500) {
          return Column(
            children: <Widget>[
              SizedBox(width: double.infinity, child: streakCard),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: securityCard),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _RecentActionCard(snapshot: snapshot),
              ),
            ],
          );
        }

        return Column(
          children: <Widget>[
            IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  Expanded(child: streakCard),
                  const SizedBox(width: 12),
                  Expanded(child: securityCard),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _RecentActionCard(snapshot: snapshot),
            ),
          ],
        );
      },
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            M3EContainer.sunny(
              width: 46,
              height: 46,
              color: colors.tertiary,
              child: Icon(
                Icons.local_fire_department_rounded,
                color: colors.onTertiary,
                size: 23,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '$days 天',
              style: textTheme.headlineLarge?.copyWith(
                color: colors.onTertiaryContainer,
              ),
            ),
            Text(
              '连续准时打卡',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onTertiaryContainer.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({
    required this.biometricAvailable,
    required this.deviceTrusted,
    required this.onEnrollDevice,
  });

  final bool biometricAvailable;
  final bool deviceTrusted;
  final VoidCallback onEnrollDevice;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('安全校验', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _CheckRow(
              icon: Icons.fingerprint_rounded,
              label: '生物识别',
              passed: biometricAvailable,
            ),
            const SizedBox(height: 12),
            _CheckRow(
              icon: Icons.phonelink_lock_rounded,
              label: '信任设备',
              passed: deviceTrusted,
            ),
            if (!deviceTrusted) ...<Widget>[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: M3EButton(
                  onPressed: onEnrollDevice,
                  size: M3EButtonSize.xs,
                  style: M3EButtonStyle.tonal,
                  child: const Text('登记此设备'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.icon,
    required this.label,
    required this.passed,
  });

  final IconData icon;
  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: colors.onSurfaceVariant),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
        Icon(
          passed ? Icons.check_circle_rounded : Icons.error_rounded,
          size: 19,
          color: passed ? colors.primary : colors.error,
        ),
      ],
    );
  }
}

class _RecentActionCard extends StatelessWidget {
  const _RecentActionCard({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final working = snapshot.state.isWorking;

    return Card(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: ShapeDecoration(
                color: colors.primaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(5),
                  ),
                ),
              ),
              child: Icon(
                working ? Icons.login_rounded : Icons.logout_rounded,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    working ? '上班打卡' : '最近一次打卡',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    working ? '本次开始于服务器时间' : '记录以服务器时间为准',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatShortTime(
                working ? snapshot.activeSince : snapshot.lastActionAt,
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
