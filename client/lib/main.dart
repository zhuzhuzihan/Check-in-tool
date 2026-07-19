import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/controllers/attendance_controller.dart';
import 'src/data/attendance_repository.dart';
import 'src/data/demo_attendance_repository.dart';
import 'src/data/remote_attendance_repository.dart';
import 'src/services/biometric_authenticator.dart';
import 'src/services/device_identity_service.dart';
import 'src/services/synced_clock.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final AttendanceRepository repository = config.isDemo
      ? DemoAttendanceRepository()
      : RemoteAttendanceRepository(
          baseUrl: config.apiBaseUrl,
          authToken: config.authToken,
        );
  final clock = SyncedClock(repository: repository);
  final controller = AttendanceController(
    repository: repository,
    biometricAuthenticator: LocalBiometricAuthenticator(),
    deviceIdentityProvider: DeviceIdentityService(),
    clockSource: clock,
  );

  runApp(AttendanceApp(controller: controller));
}
