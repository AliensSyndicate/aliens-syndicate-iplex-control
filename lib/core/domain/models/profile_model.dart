import 'package:flutter/foundation.dart';
import 'model_utils.dart';

/// Representation of a playback profile in `profiles/{profileId}`.
/// Profiles represent viewing identities, independent of Firebase accounts.
@immutable
class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.familyId,
    required this.name,
    this.avatarKey = 'avatar-01',
    this.status = 'active',
    this.createdByUid = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String familyId;
  final String name;
  final String avatarKey;
  final String status;
  final String createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  factory ProfileModel.fromMap(String id, Map<String, dynamic> data) {
    return ProfileModel(
      id: id,
      familyId: (data['familyId'] ?? '') as String,
      name: (data['name'] ?? '') as String,
      avatarKey: (data['avatarKey'] ?? 'avatar-01') as String,
      status: (data['status'] ?? 'active') as String,
      createdByUid: (data['createdByUid'] ?? data['creatorId'] ?? '') as String,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'name': name,
      'avatarKey': avatarKey,
      'status': status,
      'createdByUid': createdByUid,
      if (createdAt != null) 'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null) 'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  ProfileModel copyWith({
    String? id,
    String? familyId,
    String? name,
    String? avatarKey,
    String? status,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      name: name ?? this.name,
      avatarKey: avatarKey ?? this.avatarKey,
      status: status ?? this.status,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          name == other.name &&
          avatarKey == other.avatarKey &&
          status == other.status &&
          createdByUid == other.createdByUid &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        familyId,
        name,
        avatarKey,
        status,
        createdByUid,
        createdAt,
        updatedAt,
      );
}
