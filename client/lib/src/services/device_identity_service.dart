import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/attendance.dart';

abstract interface class DeviceIdentityProvider {
  Future<DeviceIdentity> getIdentity();
}

class DeviceIdentityService implements DeviceIdentityProvider {
  DeviceIdentityService({
    DeviceInfoPlugin? deviceInfo,
    FlutterSecureStorage? storage,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _storage = storage ?? const FlutterSecureStorage();

  static const _installIdKey = 'installation_id_v1';

  final DeviceInfoPlugin _deviceInfo;
  final FlutterSecureStorage _storage;
  Future<DeviceIdentity>? _cachedIdentity;

  @override
  Future<DeviceIdentity> getIdentity() {
    return _cachedIdentity ??= _createIdentity();
  }

  Future<DeviceIdentity> _createIdentity() async {
    final installId = await _installationId();
    final package = await PackageInfo.fromPlatform();
    final metadata = await _metadata();
    final canonical = <Object?>[
      installId,
      package.packageName,
      metadata['platform'],
      metadata['manufacturer'],
      metadata['model'],
      metadata['os_version'],
    ].join('|');

    return DeviceIdentity(
      fingerprint: sha256.convert(utf8.encode(canonical)).toString(),
      metadata: <String, Object?>{
        ...metadata,
        'app_package': package.packageName,
        'app_version': package.version,
        'app_build': package.buildNumber,
      },
    );
  }

  Future<String> _installationId() async {
    final existing = await _storage.read(key: _installIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final created = const Uuid().v4();
    await _storage.write(key: _installIdKey, value: created);
    return created;
  }

  Future<Map<String, Object?>> _metadata() async {
    if (kIsWeb) {
      return const <String, Object?>{
        'platform': 'web',
        'is_physical_device': false,
      };
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await _deviceInfo.androidInfo;
        return <String, Object?>{
          'platform': 'android',
          'manufacturer': info.manufacturer,
          'model': info.model,
          'os_version': info.version.release,
          'sdk_int': info.version.sdkInt,
          'is_physical_device': info.isPhysicalDevice,
          'is_low_ram_device': info.isLowRamDevice,
        };
      case TargetPlatform.iOS:
        final info = await _deviceInfo.iosInfo;
        return <String, Object?>{
          'platform': 'ios',
          'manufacturer': 'Apple',
          'model': info.utsname.machine,
          'model_name': info.modelName,
          'os_version': info.systemVersion,
          'is_physical_device': info.isPhysicalDevice,
        };
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return <String, Object?>{
          'platform': defaultTargetPlatform.name,
          'is_physical_device': true,
        };
    }
  }
}
