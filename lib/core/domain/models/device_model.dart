import 'package:flutter/foundation.dart';
import 'model_utils.dart';

/// Representation of a registered playback device in `devices/{deviceId}`.
/// Platforms: `android_tv`, `tizen`, `webos`, `web` (iPlex Web in a browser).
@immutable
class DeviceModel {
  const DeviceModel({
    required this.id,
    required this.familyId,
    required this.displayName,
    this.platform = 'android_tv',
    this.status = 'linked',
    this.lastSeenAt,
    this.linkedAt,
    this.linkedByUid = '',
    this.manufacturer = '',
    this.model = '',
    this.nativeIdentityFingerprint = '',
    this.identitySource = 'standard',
    this.identityScope = 'app_scoped',
    this.identityStability = 'os_reinstall_stable',
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
  final DateTime? lastSeenAt;
  final DateTime? linkedAt;
  final String linkedByUid;
  final String manufacturer;
  final String model;
  final String nativeIdentityFingerprint;
  final String identitySource;
  final String identityScope;
  final String identityStability;
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
      case 'web':
        return 'Navegador';
      case 'android_tv':
      default:
        return 'Android TV';
    }
  }

  factory DeviceModel.fromMap(String id, Map<String, dynamic> data) {
    final rawOnlineUntil = ModelUtils.parseDateTime(data['onlineUntil']);
    final rawCreatedAt = ModelUtils.parseDateTime(data['createdAt']);
    final rawUpdatedAt = ModelUtils.parseDateTime(data['updatedAt']);
    final rawLinkedAt = ModelUtils.parseDateTime(data['linkedAt'] ?? data['createdAt']);

    return DeviceModel(
      id: id,
      familyId: (data['familyId'] ?? '') as String,
      displayName: (data['displayName'] ?? data['name'] ?? '') as String,
      platform: (data['platform'] ?? 'android_tv') as String,
      status: (data['status'] ?? 'linked') as String,
      lastSeenAt: ModelUtils.parseDateTime(data['lastSeenAt']),
      linkedAt: rawLinkedAt,
      linkedByUid: (data['linkedByUid'] ?? data['issuer'] ?? '') as String,
      manufacturer: (data['manufacturer'] ?? '') as String,
      model: (data['model'] ?? '') as String,
      nativeIdentityFingerprint: (data['nativeIdentityFingerprint'] ?? '') as String,
      identitySource: (data['identitySource'] ?? 'standard') as String,
      identityScope: (data['identityScope'] ?? 'app_scoped') as String,
      identityStability: (data['identityStability'] ?? 'os_reinstall_stable') as String,
      onlineUntil: rawOnlineUntil,
      sessionId: data['sessionId'] as String?,
      createdAt: rawCreatedAt,
      updatedAt: rawUpdatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'displayName': displayName,
      'name': displayName,
      'platform': platform,
      'status': status,
      'linkedByUid': linkedByUid,
      'manufacturer': manufacturer,
      'model': model,
      'nativeIdentityFingerprint': nativeIdentityFingerprint,
      'identitySource': identitySource,
      'identityScope': identityScope,
      'identityStability': identityStability,
      if (sessionId != null) 'sessionId': sessionId,
      if (onlineUntil != null) 'onlineUntil': ModelUtils.toTimestampOrNull(onlineUntil),
      if (lastSeenAt != null) 'lastSeenAt': ModelUtils.toTimestampOrNull(lastSeenAt),
      if (linkedAt != null) 'linkedAt': ModelUtils.toTimestampOrNull(linkedAt),
      if (createdAt != null) 'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null) 'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  DeviceModel copyWith({
    String? id,
    String? familyId,
    String? displayName,
    String? platform,
    String? status,
    DateTime? lastSeenAt,
    DateTime? linkedAt,
    String? linkedByUid,
    String? manufacturer,
    String? model,
    String? nativeIdentityFingerprint,
    String? identitySource,
    String? identityScope,
    String? identityStability,
    DateTime? onlineUntil,
    String? sessionId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      displayName: displayName ?? this.displayName,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      linkedAt: linkedAt ?? this.linkedAt,
      linkedByUid: linkedByUid ?? this.linkedByUid,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      nativeIdentityFingerprint: nativeIdentityFingerprint ?? this.nativeIdentityFingerprint,
      identitySource: identitySource ?? this.identitySource,
      identityScope: identityScope ?? this.identityScope,
      identityStability: identityStability ?? this.identityStability,
      onlineUntil: onlineUntil ?? this.onlineUntil,
      sessionId: sessionId ?? this.sessionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          displayName == other.displayName &&
          platform == other.platform &&
          status == other.status &&
          lastSeenAt == other.lastSeenAt &&
          linkedAt == other.linkedAt &&
          linkedByUid == other.linkedByUid &&
          manufacturer == other.manufacturer &&
          model == other.model &&
          nativeIdentityFingerprint == other.nativeIdentityFingerprint &&
          identitySource == other.identitySource &&
          identityScope == other.identityScope &&
          identityStability == other.identityStability &&
          onlineUntil == other.onlineUntil &&
          sessionId == other.sessionId &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        familyId,
        displayName,
        platform,
        status,
        lastSeenAt,
        linkedAt,
        linkedByUid,
        manufacturer,
        model,
        nativeIdentityFingerprint,
        identitySource,
        identityScope,
        identityStability,
        onlineUntil,
        sessionId,
        createdAt,
        updatedAt,
      );
}
