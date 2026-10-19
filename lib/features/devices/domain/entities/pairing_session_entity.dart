import 'package:flutter/foundation.dart';

@immutable
class PairingSessionEntity {
  const PairingSessionEntity({
    required this.token,
    required this.deviceId,
    required this.displayName,
    this.platform = 'android_tv',
    this.manufacturer = '',
    this.model = '',
    this.nativeIdentityMasked = '',
    this.fingerprint = '',
    this.identitySource = 'standard',
    this.identityStability = 'os_reinstall_stable',
    this.isAlreadyLinked = false,
    this.isSameFamily = false,
    this.currentFamilyId,
  });

  final String token;
  final String deviceId;
  final String displayName;
  final String platform;
  final String manufacturer;
  final String model;
  final String nativeIdentityMasked;
  final String fingerprint;
  final String identitySource;
  final String identityStability;
  final bool isAlreadyLinked;
  final bool isSameFamily;
  final String? currentFamilyId;

  String get platformLabel {
    switch (platform) {
      case 'tizen':
        return 'Samsung Tizen';
      case 'webos':
        return 'LG webOS';
      case 'android_tv':
      default:
        return 'Android TV';
    }
  }

  factory PairingSessionEntity.fromMap(Map<String, dynamic> data) {
    return PairingSessionEntity(
      token: (data['token'] ?? '') as String,
      deviceId: (data['deviceId'] ?? '') as String,
      displayName: (data['displayName'] ?? '') as String,
      platform: (data['platform'] ?? 'android_tv') as String,
      manufacturer: (data['manufacturer'] ?? '') as String,
      model: (data['model'] ?? '') as String,
      nativeIdentityMasked: (data['nativeIdentityMasked'] ?? '') as String,
      fingerprint: (data['fingerprint'] ?? '') as String,
      identitySource: (data['identitySource'] ?? 'standard') as String,
      identityStability: (data['identityStability'] ?? 'os_reinstall_stable') as String,
      isAlreadyLinked: data['isAlreadyLinked'] == true,
      isSameFamily: data['isSameFamily'] == true,
      currentFamilyId: data['currentFamilyId'] as String?,
    );
  }
}
