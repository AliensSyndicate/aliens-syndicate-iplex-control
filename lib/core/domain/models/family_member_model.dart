import 'package:flutter/foundation.dart';

import 'model_utils.dart';

/// Representation of a family membership in `family_members/{membershipId}`.
/// Defines a user's role and status within a family.
@immutable
class FamilyMemberModel {
  const FamilyMemberModel({
    required this.id,
    required this.familyId,
    required this.userUid,
    this.role = 'member',
    this.status = 'active',
    this.joinedAt,
  });

  final String id;
  final String familyId;
  final String userUid;
  final String role; // 'admin' | 'member'
  final String status; // 'active'
  final DateTime? joinedAt;

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';

  factory FamilyMemberModel.fromMap(String id, Map<String, dynamic> data) {
    return FamilyMemberModel(
      id: id,
      familyId: (data['familyId'] ?? '') as String,
      userUid: (data['userUid'] ?? data['uid'] ?? '') as String,
      role: (data['role'] ?? 'member') as String,
      status: (data['status'] ?? 'active') as String,
      joinedAt: ModelUtils.parseDateTime(data['joinedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'userUid': userUid,
      'role': role,
      'status': status,
      if (joinedAt != null) 'joinedAt': ModelUtils.toTimestampOrNull(joinedAt),
    };
  }

  FamilyMemberModel copyWith({
    String? id,
    String? familyId,
    String? userUid,
    String? role,
    String? status,
    DateTime? joinedAt,
  }) {
    return FamilyMemberModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      userUid: userUid ?? this.userUid,
      role: role ?? this.role,
      status: status ?? this.status,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyMemberModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          userUid == other.userUid &&
          role == other.role &&
          status == other.status &&
          joinedAt == other.joinedAt;

  @override
  int get hashCode =>
      Object.hash(id, familyId, userUid, role, status, joinedAt);
}
