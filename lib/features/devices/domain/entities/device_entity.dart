import 'package:flutter/foundation.dart';

@immutable
class DeviceEntity {
  const DeviceEntity({
    required this.id,
    required this.familyId,
    required this.displayName,
    this.platform = 'android_tv',
    this.status = 'linked',
    this.manufacturer = '',
    this.model = '',
    this.nativeIdentityFingerprint = '',
    this.identitySource = 'standard',
    this.identityScope = 'app_scoped',
    this.identityStability = 'os_reinstall_stable',
    this.linkedAt,
    this.lastSeenAt,
    this.linkedByUid = '',
    this.onlineUntil,
    this.sessionId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String familyId;
  final String displayName;
  final String platform;
  final String status;
  final String manufacturer;
  final String model;
  final String nativeIdentityFingerprint;
  final String identitySource;
  final String identityScope;
  final String identityStability;
  final DateTime? linkedAt;
  final DateTime? lastSeenAt;
  final String linkedByUid;
  final DateTime? onlineUntil;
  final String? sessionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLinked => status == 'linked';

  bool isOnline(DateTime now) {
    if (onlineUntil == null || sessionId == null || sessionId!.isEmpty) {
      return false;
    }
    return onlineUntil!.isAfter(now);
  }

  String get maskedId {
    if (id.length <= 8) return id;
    final tail = id.substring(id.length - 4);
    return 'dev_••••$tail';
  }

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

  String get subtitleInfo {
    final parts = <String>[];
    if (manufacturer.isNotEmpty) parts.add(manufacturer);
    if (model.isNotEmpty) parts.add(model);
    if (parts.isEmpty) parts.add(platformLabel);
    return parts.join(' • ');
  }
}
