import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/attendance_repository.dart';
import '../models/attendance.dart';
import '../services/biometric_authenticator.dart';
import '../services/device_identity_service.dart';
import '../services/synced_clock.dart';

class AttendanceController extends ChangeNotifier {
  AttendanceController({
    required this.repository,
    required this.biometricAuthenticator,
    required this.deviceIdentityProvider,
    required this.clockSource,
  });

  final AttendanceRepository repository;
  final BiometricAuthenticator biometricAuthenticator;
  final DeviceIdentityProvider deviceIdentityProvider;
  final SyncedClock clockSource;

  DashboardSnapshot? _snapshot;
  Timer? _ticker;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _biometricAvailable = false;
  String? _notice;
  bool _noticeIsError = false;
  Object? _loadError;
  Future<void>? _initialization;

  DashboardSnapshot? get snapshot => _snapshot;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get biometricAvailable => _biometricAvailable;
  bool get isDemo => repository.isDemo;
  String? get notice => _notice;
  bool get noticeIsError => _noticeIsError;
  Object? get loadError => _loadError;
  DateTime get now => clockSource.now().toLocal();

  Duration get liveTodayWorked {
    final value = _snapshot;
    if (value == null || !value.state.isWorking) {
      return value?.todayWorked ?? Duration.zero;
    }
    final elapsed = clockSource.now().difference(value.serverTime);
    return value.todayWorked + (elapsed.isNegative ? Duration.zero : elapsed);
  }

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_snapshot != null) notifyListeners();
    });
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      await clockSource.sync();
      String? fingerprint;
      try {
        fingerprint = (await deviceIdentityProvider.getIdentity()).fingerprint;
      } on Object {
        // Dashboard remains readable if local device metadata is unavailable.
      }
      final dashboard = await repository.fetchDashboard(
        deviceFingerprint: fingerprint,
      );
      _snapshot = dashboard;
      _biometricAvailable = await biometricAuthenticator.isAvailable();
    } on Object catch (error) {
      _loadError = error;
      _setNotice('数据同步失败：$error', isError: true);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clock({
    required TouchMetrics touchMetrics,
    required ScreenMetrics screenMetrics,
  }) async {
    final current = _snapshot;
    if (current == null || _isSubmitting) return;

    final duration = touchMetrics.duration.inMilliseconds;
    if (duration < 50 || duration > 10000) {
      _setNotice('请自然按压打卡按钮后重试', isError: true);
      notifyListeners();
      return;
    }

    _isSubmitting = true;
    _notice = null;
    notifyListeners();
    try {
      final authenticated = await biometricAuthenticator.authenticate();
      if (!authenticated) {
        _setNotice('身份验证未通过，未提交打卡', isError: true);
        return;
      }

      final identity = await deviceIdentityProvider.getIdentity();
      final next = await repository.clock(
        ClockRequest(
          action: current.state.nextAction,
          requestId: const Uuid().v4(),
          deviceIdentity: identity,
          touchMetrics: touchMetrics,
          clientTime: clockSource.now(),
          screenMetrics: screenMetrics,
        ),
      );
      _snapshot = next;
      _setNotice(next.state.isWorking ? '上班打卡成功，今天也加油' : '下班打卡成功，辛苦了');
    } on BiometricAuthenticationException catch (error) {
      _setNotice(error.message, isError: true);
    } on AttendanceRepositoryException catch (error) {
      _setNotice(error.message, isError: true);
    } on Object catch (error) {
      _setNotice('打卡失败：$error', isError: true);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> enrollCurrentDevice(String enrollmentToken) async {
    if (_isSubmitting || enrollmentToken.trim().isEmpty) return;
    _isSubmitting = true;
    _notice = null;
    notifyListeners();
    try {
      final identity = await deviceIdentityProvider.getIdentity();
      await repository.trustDevice(
        identity: identity,
        enrollmentToken: enrollmentToken.trim(),
      );
      _snapshot = await repository.fetchDashboard(
        deviceFingerprint: identity.fingerprint,
      );
      _setNotice('设备登记成功，可进行生物识别打卡');
    } on AttendanceRepositoryException catch (error) {
      _setNotice(error.message, isError: true);
    } on Object catch (error) {
      _setNotice('设备登记失败：$error', isError: true);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  void _setNotice(String message, {bool isError = false}) {
    _notice = message;
    _noticeIsError = isError;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
