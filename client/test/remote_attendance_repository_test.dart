import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_clock_in/src/data/remote_attendance_repository.dart';
import 'package:remote_clock_in/src/models/attendance.dart';

void main() {
  test('server time is read from the backend data envelope', () async {
    final repository = RemoteAttendanceRepository(
      baseUrl: 'https://attendance.example/api/v1',
      authToken: 'test-token',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/time');
        return http.Response(
          '{"data":{"server_time":"2026-07-19T08:30:00Z"}}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    expect(
      await repository.fetchServerTime(),
      DateTime.utc(2026, 7, 19, 8, 30),
    );
  });

  test(
    'dashboard sends the current fingerprint and parses its envelope',
    () async {
      final fingerprint = List<String>.filled(64, 'a').join();
      final repository = RemoteAttendanceRepository(
        baseUrl: 'https://attendance.example/api/v1/',
        authToken: 'test-token',
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer test-token');
          expect(request.headers['x-device-fingerprint'], fingerprint);
          return http.Response(
            '''
          {
            "data": {
              "display_name": "测试用户",
              "state": "on_duty",
              "server_time": "2026-07-19T08:30:00Z",
              "today_worked_ms": 3600000,
              "active_since": "2026-07-19T07:30:00Z",
              "last_action_at": "2026-07-19T07:30:00Z",
              "weekly_hours": [
                {"day": "2026-07-19", "worked_ms": 3600000}
              ],
              "streak_days": 3,
              "device_trusted": true
            }
          }
          ''',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final dashboard = await repository.fetchDashboard(
        deviceFingerprint: fingerprint,
      );
      expect(dashboard.displayName, '测试用户');
      expect(dashboard.state.isWorking, isTrue);
      expect(dashboard.deviceTrusted, isTrue);
      expect(dashboard.weeklyHours.single.worked.inHours, 1);
      expect(dashboard.weeklyHours.single.day, DateTime.utc(2026, 7, 19));
    },
  );
}
