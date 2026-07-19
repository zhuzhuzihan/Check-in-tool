import '../models/attendance.dart';

abstract interface class AttendanceRepository {
  bool get isDemo;

  Future<DateTime> fetchServerTime();

  Future<DashboardSnapshot> fetchDashboard({String? deviceFingerprint});

  Future<void> trustDevice({
    required DeviceIdentity identity,
    required String enrollmentToken,
  });

  Future<DashboardSnapshot> clock(ClockRequest request);
}

class AttendanceRepositoryException implements Exception {
  const AttendanceRepositoryException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
