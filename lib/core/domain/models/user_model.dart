import 'package:flutter/foundation.dart';

import 'model_utils.dart';

/// Representation of a user in `users/{uid}`.
/// Document ID corresponds to the Firebase Auth UID.
@immutable
class UserModel {
  const UserModel({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    required this.email,
    this.primaryFamilyId,
    this.locale = 'pt_BR',
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String email;
  final String? primaryFamilyId;
  final String locale;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      uid: id,
      displayName: (data['displayName'] ?? data['name'] ?? '') as String,
      photoUrl: data['photoUrl'] as String?,
      email: (data['email'] ?? '') as String,
      primaryFamilyId: (data['primaryFamilyId'] ?? data['familyId']) as String?,
      locale: (data['locale'] ?? 'pt_BR') as String,
      status: (data['status'] ?? 'active') as String,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'email': email,
      'primaryFamilyId': primaryFamilyId,
      'locale': locale,
      'status': status,
      if (createdAt != null)
        'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null)
        'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  UserModel copyWith({
    String? uid,
    String? displayName,
    String? photoUrl,
    String? email,
    String? primaryFamilyId,
    String? locale,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      email: email ?? this.email,
      primaryFamilyId: primaryFamilyId ?? this.primaryFamilyId,
      locale: locale ?? this.locale,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl &&
          email == other.email &&
          primaryFamilyId == other.primaryFamilyId &&
          locale == other.locale &&
          status == other.status &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    uid,
    displayName,
    photoUrl,
    email,
    primaryFamilyId,
    locale,
    status,
    createdAt,
    updatedAt,
  );
}
