import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/attendance.dart';
import 'attendance_repository.dart';

class RemoteAttendanceRepository implements AttendanceRepository {
  RemoteAttendanceRepository({
    required String baseUrl,
    required this.authToken,
    http.Client? client,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
       _client = client ?? http.Client();

  final String _baseUrl;
  final String authToken;
  final http.Client _client;

  @override
  bool get isDemo => false;

  @override
  Future<DateTime> fetchServerTime() async {
    final body = await _request('GET', '/time');
    return _parseDate(_data(body)['server_time']);
  }

  @override
  Future<DashboardSnapshot> fetchDashboard({String? deviceFingerprint}) async {
    final body = await _request(
      'GET',
      '/dashboard',
      extraHeaders: <String, String>{
        'x-device-fingerprint': ?deviceFingerprint,
      },
    );
    return _parseDashboard(_data(body));
  }

  @override
  Future<void> trustDevice({
    required DeviceIdentity identity,
    required String enrollmentToken,
  }) async {
    await _request(
      'POST',
      '/devices/trust',
      extraHeaders: <String, String>{
        'x-device-enrollment-token': enrollmentToken,
      },
      payload: <String, Object?>{
        'device_fingerprint': identity.fingerprint,
        'device_info': identity.metadata,
      },
    );
  }

  @override
  Future<DashboardSnapshot> clock(ClockRequest request) async {
    final body = await _request(
      'POST',
      '/attendance/clock',
      payload: <String, Object?>{
        'action': request.action.wireName,
        'request_id': request.requestId,
        'device_fingerprint': request.deviceIdentity.fingerprint,
        'device_info': <String, Object?>{
          ...request.deviceIdentity.metadata,
          'screen_width': request.screenMetrics.width,
          'screen_height': request.screenMetrics.height,
          'pixel_ratio': request.screenMetrics.pixelRatio,
        },
        'touch_duration_ms': request.touchMetrics.duration.inMilliseconds,
        'touch_distance_px': request.touchMetrics.distance,
        'touch_sample_count': request.touchMetrics.sampleCount,
        'client_timestamp': request.clientTime.millisecondsSinceEpoch,
      },
    );
    return _parseDashboard(_data(body));
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? payload,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    if (authToken.isEmpty) {
      throw const AttendanceRepositoryException(
        '已配置 API_BASE_URL，但缺少 AUTH_TOKEN',
        code: 'missing_auth_token',
      );
    }

    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(<String, String>{
        'accept': 'application/json',
        'authorization': 'Bearer $authToken',
        if (payload != null) 'content-type': 'application/json',
        ...extraHeaders,
      });
    if (payload != null) request.body = jsonEncode(payload);

    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(response.body) as Map).cast<String, Object?>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        if (error is Map) {
          final details = error.cast<String, Object?>();
          throw AttendanceRepositoryException(
            details['message']?.toString() ?? '请求失败',
            code: details['code']?.toString(),
          );
        }
        throw AttendanceRepositoryException('请求失败 (${response.statusCode})');
      }
      return decoded;
    } on AttendanceRepositoryException {
      rethrow;
    } on Object catch (error) {
      throw AttendanceRepositoryException('无法连接打卡服务：$error');
    }
  }

  Map<String, Object?> _data(Map<String, Object?> body) {
    final data = body['data'];
    return data is Map ? data.cast<String, Object?>() : body;
  }

  DashboardSnapshot _parseDashboard(Map<String, Object?> json) {
    final weekly = json['weekly_hours'];
    return DashboardSnapshot(
      displayName: json['display_name']?.toString() ?? '你好',
      state: _parseState(json['state']),
      serverTime: _parseDate(json['server_time']),
      todayWorked: Duration(milliseconds: _parseInt(json['today_worked_ms'])),
      activeSince: _parseNullableDate(json['active_since']),
      lastActionAt: _parseNullableDate(json['last_action_at']),
      weeklyHours: weekly is List
          ? weekly
                .map((item) {
                  final entry = (item as Map).cast<String, Object?>();
                  return DailyHours(
                    day: _parseDay(entry['day']),
                    worked: Duration(
                      milliseconds: _parseInt(entry['worked_ms']),
                    ),
                  );
                })
                .toList(growable: false)
          : const <DailyHours>[],
      streakDays: _parseInt(json['streak_days']),
      deviceTrusted: json['device_trusted'] == true,
    );
  }

  AttendanceState _parseState(Object? value) => switch (value) {
    'on_duty' => AttendanceState.onDuty,
    'on_break' => AttendanceState.onBreak,
    _ => AttendanceState.offDuty,
  };

  DateTime _parseDate(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return DateTime.parse(value.toString()).toUtc();
  }

  DateTime? _parseNullableDate(Object? value) {
    return value == null ? null : _parseDate(value);
  }

  DateTime _parseDay(Object? value) {
    final parts = value.toString().split('-');
    if (parts.length == 3) {
      return DateTime.utc(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return _parseDate(value);
  }

  int _parseInt(Object? value) => switch (value) {
    int number => number,
    num number => number.round(),
    _ => int.tryParse(value?.toString() ?? '') ?? 0,
  };
}
