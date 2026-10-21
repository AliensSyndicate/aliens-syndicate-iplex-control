import 'package:flutter/foundation.dart';

import 'model_utils.dart';

/// Representation of a family in `families/{familyId}`.
/// Belongs to an administrator (`adminUid`) and supports up to `maxMembers` members.
@immutable
class FamilyModel {
  const FamilyModel({
    required this.id,
    required this.adminUid,
    required this.name,
    this.status = 'active',
    this.maxMembers = 5,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String adminUid;
  final String name;
  final String status;
  final int maxMembers;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';
  bool isAdmin(String uid) => adminUid == uid;

  factory FamilyModel.fromMap(String id, Map<String, dynamic> data) {
    return FamilyModel(
      id: id,
      adminUid: (data['adminUid'] ?? data['adminId'] ?? '') as String,
      name: (data['name'] ?? '') as String,
      status: (data['status'] ?? 'active') as String,
      maxMembers: (data['maxMembers'] as num?)?.toInt() ?? 5,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'adminUid': adminUid,
      'name': name,
      'status': status,
      'maxMembers': maxMembers,
      if (createdAt != null)
        'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null)
        'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  FamilyModel copyWith({
    String? id,
    String? adminUid,
    String? name,
    String? status,
    int? maxMembers,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FamilyModel(
      id: id ?? this.id,
      adminUid: adminUid ?? this.adminUid,
      name: name ?? this.name,
      status: status ?? this.status,
      maxMembers: maxMembers ?? this.maxMembers,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          adminUid == other.adminUid &&
          name == other.name &&
          status == other.status &&
          maxMembers == other.maxMembers &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, adminUid, name, status, maxMembers, createdAt, updatedAt);
}
