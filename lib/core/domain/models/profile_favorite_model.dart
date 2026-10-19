import 'package:flutter/foundation.dart';

import 'model_utils.dart';

/// Representation of a profile favorite in `profile_favorites/{favoriteId}`.
/// Deterministic keying typically: `${profileId}_${contentId}`.
@immutable
class ProfileFavoriteModel {
  const ProfileFavoriteModel({
    required this.id,
    required this.familyId,
    required this.profileId,
    required this.contentId,
    this.catalogId,
    required this.title,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String familyId;
  final String profileId;
  final String contentId;
  final String? catalogId;
  final String title;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String generateId(String profileId, String contentId) =>
      '${profileId}_$contentId';

  factory ProfileFavoriteModel.fromMap(String id, Map<String, dynamic> data) {
    return ProfileFavoriteModel(
      id: id,
      familyId: (data['familyId'] ?? '') as String,
      profileId: (data['profileId'] ?? '') as String,
      contentId: (data['contentId'] ?? '') as String,
      catalogId: data['catalogId'] as String?,
      title: (data['title'] ?? '') as String,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'profileId': profileId,
      'contentId': contentId,
      'catalogId': catalogId,
      'title': title,
      if (createdAt != null)
        'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null)
        'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  ProfileFavoriteModel copyWith({
    String? id,
    String? familyId,
    String? profileId,
    String? contentId,
    String? catalogId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProfileFavoriteModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      profileId: profileId ?? this.profileId,
      contentId: contentId ?? this.contentId,
      catalogId: catalogId ?? this.catalogId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileFavoriteModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          profileId == other.profileId &&
          contentId == other.contentId &&
          catalogId == other.catalogId &&
          title == other.title &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    familyId,
    profileId,
    contentId,
    catalogId,
    title,
    createdAt,
    updatedAt,
  );
}
