enum AttendanceState { offDuty, onDuty, onBreak }

enum AttendanceAction { clockIn, clockOut }

extension AttendanceStateUi on AttendanceState {
  bool get isWorking => this == AttendanceState.onDuty;

  String get label => switch (this) {
    AttendanceState.offDuty => '未上班',
    AttendanceState.onDuty => '工作中',
    AttendanceState.onBreak => '休息中',
  };

  AttendanceAction get nextAction =>
      isWorking ? AttendanceAction.clockOut : AttendanceAction.clockIn;
}

extension AttendanceActionApi on AttendanceAction {
  String get wireName => switch (this) {
    AttendanceAction.clockIn => 'clock_in',
    AttendanceAction.clockOut => 'clock_out',
  };
}

class DailyHours {
  const DailyHours({required this.day, required this.worked});

  final DateTime day;
  final Duration worked;

  double get hours => worked.inMinutes / 60;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.displayName,
    required this.state,
    required this.serverTime,
    required this.todayWorked,
    required this.weeklyHours,
    required this.streakDays,
    required this.deviceTrusted,
    this.activeSince,
    this.lastActionAt,
  });

  final String displayName;
  final AttendanceState state;
  final DateTime serverTime;
  final Duration todayWorked;
  final List<DailyHours> weeklyHours;
  final int streakDays;
  final bool deviceTrusted;
  final DateTime? activeSince;
  final DateTime? lastActionAt;
}

class TouchMetrics {
  const TouchMetrics({
    required this.duration,
    required this.distance,
    required this.sampleCount,
  });

  const TouchMetrics.accessibility()
    : duration = const Duration(milliseconds: 180),
      distance = 0,
      sampleCount = 1;

  final Duration duration;
  final double distance;
  final int sampleCount;
}

class DeviceIdentity {
  const DeviceIdentity({required this.fingerprint, required this.metadata});

  final String fingerprint;
  final Map<String, Object?> metadata;
}

typedef ScreenMetrics = ({double width, double height, double pixelRatio});

class ClockRequest {
  const ClockRequest({
    required this.action,
    required this.requestId,
    required this.deviceIdentity,
    required this.touchMetrics,
    required this.clientTime,
    required this.screenMetrics,
  });

  final AttendanceAction action;
  final String requestId;
  final DeviceIdentity deviceIdentity;
  final TouchMetrics touchMetrics;
  final DateTime clientTime;
  final ScreenMetrics screenMetrics;
}
