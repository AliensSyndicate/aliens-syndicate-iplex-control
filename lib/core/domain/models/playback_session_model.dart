import 'package:flutter/foundation.dart';

import 'model_utils.dart';

/// Representation of an active TV playback lease in `playback_sessions/{sessionId}`.
/// Limits: maximum 3 concurrent playback sessions per family, 1 device per profile.
@immutable
class PlaybackSessionModel {
  const PlaybackSessionModel({
    required this.id,
    required this.familyId,
    required this.profileId,
    required this.deviceId,
    this.status = 'active',
    this.startedAt,
    this.lastHeartbeatAt,
    this.leaseExpiresAt,
  });

  final String id;
  final String familyId;
  final String profileId;
  final String deviceId;
  final String status; // 'active' | 'released' | 'expired'
  final DateTime? startedAt;
  final DateTime? lastHeartbeatAt;
  final DateTime? leaseExpiresAt;

  bool isAlive(DateTime now) {
    return status == 'active' &&
        leaseExpiresAt != null &&
        leaseExpiresAt!.isAfter(now);
  }

  factory PlaybackSessionModel.fromMap(String id, Map<String, dynamic> data) {
    return PlaybackSessionModel(
      id: id,
      familyId: (data['familyId'] ?? '') as String,
      profileId: (data['profileId'] ?? '') as String,
      deviceId: (data['deviceId'] ?? '') as String,
      status: (data['status'] ?? 'active') as String,
      startedAt: ModelUtils.parseDateTime(data['startedAt']),
      lastHeartbeatAt: ModelUtils.parseDateTime(data['lastHeartbeatAt']),
      leaseExpiresAt: ModelUtils.parseDateTime(
        data['leaseExpiresAt'] ?? data['expiresAt'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'profileId': profileId,
      'deviceId': deviceId,
      'status': status,
      if (startedAt != null)
        'startedAt': ModelUtils.toTimestampOrNull(startedAt),
      if (lastHeartbeatAt != null)
        'lastHeartbeatAt': ModelUtils.toTimestampOrNull(lastHeartbeatAt),
      if (leaseExpiresAt != null)
        'leaseExpiresAt': ModelUtils.toTimestampOrNull(leaseExpiresAt),
    };
  }

  PlaybackSessionModel copyWith({
    String? id,
    String? familyId,
    String? profileId,
    String? deviceId,
    String? status,
    DateTime? startedAt,
    DateTime? lastHeartbeatAt,
    DateTime? leaseExpiresAt,
  }) {
    return PlaybackSessionModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      profileId: profileId ?? this.profileId,
      deviceId: deviceId ?? this.deviceId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      leaseExpiresAt: leaseExpiresAt ?? this.leaseExpiresAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSessionModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          profileId == other.profileId &&
          deviceId == other.deviceId &&
          status == other.status &&
          startedAt == other.startedAt &&
          lastHeartbeatAt == other.lastHeartbeatAt &&
          leaseExpiresAt == other.leaseExpiresAt;

  @override
  int get hashCode => Object.hash(
    id,
    familyId,
    profileId,
    deviceId,
    status,
    startedAt,
    lastHeartbeatAt,
    leaseExpiresAt,
  );
}
