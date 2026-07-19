import '../models/attendance.dart';
import 'attendance_repository.dart';

class DemoAttendanceRepository implements AttendanceRepository {
  DashboardSnapshot? _snapshot;

  @override
  bool get isDemo => true;

  @override
  Future<DateTime> fetchServerTime() async => DateTime.now().toUtc();

  @override
  Future<DashboardSnapshot> fetchDashboard({String? deviceFingerprint}) async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    return _snapshot ??= _initialSnapshot();
  }

  @override
  Future<void> trustDevice({
    required DeviceIdentity identity,
    required String enrollmentToken,
  }) async {}

  @override
  Future<DashboardSnapshot> clock(ClockRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 720));
    final current = _snapshot ?? _initialSnapshot();
    final now = DateTime.now().toUtc();

    if (request.action == AttendanceAction.clockIn &&
        current.state != AttendanceState.offDuty) {
      throw const AttendanceRepositoryException(
        '当前已经处于工作状态',
        code: 'already_clocked_in',
      );
    }
    if (request.action == AttendanceAction.clockOut &&
        current.state != AttendanceState.onDuty) {
      throw const AttendanceRepositoryException(
        '尚未上班，无法下班打卡',
        code: 'not_clocked_in',
      );
    }

    if (request.action == AttendanceAction.clockIn) {
      return _snapshot = DashboardSnapshot(
        displayName: current.displayName,
        state: AttendanceState.onDuty,
        serverTime: now,
        todayWorked: current.todayWorked,
        weeklyHours: current.weeklyHours,
        streakDays: current.streakDays,
        deviceTrusted: current.deviceTrusted,
        activeSince: now,
        lastActionAt: now,
      );
    }

    final elapsed = now.difference(current.activeSince ?? now);
    return _snapshot = DashboardSnapshot(
      displayName: current.displayName,
      state: AttendanceState.offDuty,
      serverTime: now,
      todayWorked: current.todayWorked + elapsed,
      weeklyHours: current.weeklyHours,
      streakDays: current.streakDays,
      deviceTrusted: current.deviceTrusted,
      lastActionAt: now,
    );
  }

  DashboardSnapshot _initialSnapshot() {
    final now = DateTime.now().toUtc();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeek = DateTime.utc(monday.year, monday.month, monday.day);
    const minutes = <int>[472, 505, 438, 496, 342, 0, 0];

    return DashboardSnapshot(
      displayName: '早上好，林澈',
      state: AttendanceState.onDuty,
      serverTime: now,
      todayWorked: const Duration(hours: 5, minutes: 42),
      activeSince: now.subtract(const Duration(hours: 5, minutes: 42)),
      lastActionAt: now.subtract(const Duration(hours: 5, minutes: 42)),
      weeklyHours: List<DailyHours>.generate(
        7,
        (index) => DailyHours(
          day: startOfWeek.add(Duration(days: index)),
          worked: Duration(minutes: minutes[index]),
        ),
      ),
      streakDays: 12,
      deviceTrusted: true,
    );
  }
}
