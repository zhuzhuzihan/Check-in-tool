import '../data/attendance_repository.dart';

class SyncedClock {
  SyncedClock({required this.repository});

  final AttendanceRepository repository;
  Duration _offset = Duration.zero;
  DateTime? _lastSyncedAt;

  DateTime now() => DateTime.now().toUtc().add(_offset);

  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<void> sync() async {
    final startedAt = DateTime.now().toUtc();
    final serverTime = await repository.fetchServerTime();
    final finishedAt = DateTime.now().toUtc();
    final halfRoundTrip = Duration(
      microseconds: finishedAt.difference(startedAt).inMicroseconds ~/ 2,
    );
    _offset = serverTime.difference(startedAt.add(halfRoundTrip));
    _lastSyncedAt = finishedAt;
  }
}
