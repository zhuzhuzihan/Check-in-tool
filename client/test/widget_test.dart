import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_clock_in/src/app.dart';
import 'package:remote_clock_in/src/controllers/attendance_controller.dart';
import 'package:remote_clock_in/src/data/attendance_repository.dart';
import 'package:remote_clock_in/src/models/attendance.dart';
import 'package:remote_clock_in/src/services/biometric_authenticator.dart';
import 'package:remote_clock_in/src/services/device_identity_service.dart';
import 'package:remote_clock_in/src/services/synced_clock.dart';

void main() {
  testWidgets('dashboard renders and clocks in after a human-length press', (
    tester,
  ) async {
    final repository = _TestRepository();
    final controller = _controller(repository);
    await controller.initialize();

    await tester.pumpWidget(AttendanceApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(tester.takeException(), isNull);
    expect(find.text('近七日节奏'), findsOneWidget);
    expect(find.text('上班打卡'), findsOneWidget);
    expect(find.text('未上班'), findsOneWidget);

    final action = find.byTooltip('上班打卡');
    final gesture = await tester.startGesture(tester.getCenter(action));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up(timeStamp: const Duration(milliseconds: 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      repository.lastRequest,
      isNotNull,
      reason: 'controller notice: ${controller.notice}',
    );
    expect(
      repository.lastRequest!.touchMetrics.duration.inMilliseconds,
      greaterThanOrEqualTo(50),
    );
    expect(find.text('下班打卡'), findsOneWidget);
    expect(find.text('工作中'), findsOneWidget);
  });

  testWidgets('dashboard has no layout exception on compact and wide screens', (
    tester,
  ) async {
    final sizes = <Size>[const Size(360, 780), const Size(1100, 900)];
    for (final size in sizes) {
      await tester.binding.setSurfaceSize(size);
      final repository = _TestRepository();
      final controller = _controller(repository);
      await controller.initialize();
      await tester.pumpWidget(AttendanceApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
      expect(find.text('今日已工作'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'an untrusted device can be enrolled without persisting the token',
    (tester) async {
      final repository = _TestRepository(deviceTrusted: false);
      final controller = _controller(repository);
      await controller.initialize();
      await tester.pumpWidget(AttendanceApp(controller: controller));
      await tester.pump();

      final enrollButton = find.text('登记此设备');
      await tester.ensureVisible(enrollButton);
      await tester.pump();
      await tester.tap(enrollButton);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('登记令牌'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'temporary-enrollment-token',
      );
      await tester.tap(find.text('确认登记'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repository.receivedEnrollmentToken, 'temporary-enrollment-token');
      expect(find.text('设备登记成功，可进行生物识别打卡'), findsOneWidget);
    },
  );
}

AttendanceController _controller(AttendanceRepository repository) {
  return AttendanceController(
    repository: repository,
    biometricAuthenticator: const _TestBiometricAuthenticator(),
    deviceIdentityProvider: const _TestDeviceIdentityProvider(),
    clockSource: SyncedClock(repository: repository),
  );
}

class _TestRepository implements AttendanceRepository {
  _TestRepository({this.deviceTrusted = true});

  final DateTime now = DateTime.utc(2026, 7, 13, 9, 30);
  ClockRequest? lastRequest;
  AttendanceState state = AttendanceState.offDuty;
  bool deviceTrusted;
  String? receivedEnrollmentToken;

  @override
  bool get isDemo => false;

  @override
  Future<DateTime> fetchServerTime() async => now;

  @override
  Future<DashboardSnapshot> fetchDashboard({String? deviceFingerprint}) async {
    return _snapshot();
  }

  @override
  Future<void> trustDevice({
    required DeviceIdentity identity,
    required String enrollmentToken,
  }) async {
    receivedEnrollmentToken = enrollmentToken;
    deviceTrusted = true;
  }

  @override
  Future<DashboardSnapshot> clock(ClockRequest request) async {
    lastRequest = request;
    state = request.action == AttendanceAction.clockIn
        ? AttendanceState.onDuty
        : AttendanceState.offDuty;
    return _snapshot();
  }

  DashboardSnapshot _snapshot() {
    return DashboardSnapshot(
      displayName: '你好，测试用户',
      state: state,
      serverTime: now,
      todayWorked: const Duration(hours: 3, minutes: 20),
      activeSince: state.isWorking ? now : null,
      lastActionAt: now,
      weeklyHours: List<DailyHours>.generate(
        7,
        (index) => DailyHours(
          day: now.add(Duration(days: index)),
          worked: Duration(hours: index < 5 ? 8 : 0),
        ),
      ),
      streakDays: 8,
      deviceTrusted: deviceTrusted,
    );
  }
}

class _TestBiometricAuthenticator implements BiometricAuthenticator {
  const _TestBiometricAuthenticator();

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<bool> isAvailable() async => true;
}

class _TestDeviceIdentityProvider implements DeviceIdentityProvider {
  const _TestDeviceIdentityProvider();

  @override
  Future<DeviceIdentity> getIdentity() async {
    return const DeviceIdentity(
      fingerprint: 'test-device-fingerprint',
      metadata: <String, Object?>{'platform': 'test'},
    );
  }
}
