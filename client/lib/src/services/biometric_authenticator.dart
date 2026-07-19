import 'package:local_auth/local_auth.dart';

abstract interface class BiometricAuthenticator {
  Future<bool> isAvailable();

  Future<bool> authenticate();
}

class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isAvailable() async {
    try {
      final supported = await _authentication.isDeviceSupported();
      final canCheck = await _authentication.canCheckBiometrics;
      final enrolled = await _authentication.getAvailableBiometrics();
      return supported && canCheck && enrolled.isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _authentication.authenticate(
        localizedReason: '请验证本人身份后完成打卡',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (error) {
      throw BiometricAuthenticationException(
        _messageFor(error.code),
        code: error.code.name,
      );
    } on Object catch (error) {
      throw BiometricAuthenticationException('生物识别暂时不可用：$error');
    }
  }

  String _messageFor(LocalAuthExceptionCode code) => switch (code) {
    LocalAuthExceptionCode.noBiometricHardware => '此设备不支持生物识别',
    LocalAuthExceptionCode.noBiometricsEnrolled ||
    LocalAuthExceptionCode.noCredentialsSet => '请先在系统设置中录入面容或指纹',
    LocalAuthExceptionCode.biometricLockout => '生物识别已锁定，请先解锁设备',
    LocalAuthExceptionCode.temporaryLockout => '尝试次数过多，请稍后重试',
    LocalAuthExceptionCode.userCanceled => '已取消身份验证',
    LocalAuthExceptionCode.systemCanceled => '系统取消了身份验证，请重试',
    _ => '无法完成生物识别',
  };
}

class BiometricAuthenticationException implements Exception {
  const BiometricAuthenticationException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
