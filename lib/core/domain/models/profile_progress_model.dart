import 'package:flutter/foundation.dart';

import 'model_utils.dart';

/// Representation of playback progress in `profile_progress/{progressId}`.
/// Deterministic keying typically: `${profileId}_${contentId}`.
@immutable
class ProfileProgressModel {
  const ProfileProgressModel({
    required this.id,
    required this.familyId,
    required this.profileId,
    required this.contentId,
    this.catalogId,
    this.position = 0,
    this.duration = 0,
    this.updatedAt,
  });

  final String id;
  final String familyId;
  final String profileId;
  final String contentId;
  final String? catalogId;
  final int position;
  final int duration;
  final DateTime? updatedAt;

  static String generateId(String profileId, String contentId) =>
      '${profileId}_$contentId';

  double get progressPercentage =>
      duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

  bool get isCompleted => duration > 0 && (position / duration) >= 0.95;

  factory ProfileProgressModel.fromMap(String id, Map<String, dynamic> data) {
    return ProfileProgressModel(
      id: id,
      familyId: (data['familyId'] ?? '') as String,
      profileId: (data['profileId'] ?? '') as String,
      contentId: (data['contentId'] ?? '') as String,
      catalogId: data['catalogId'] as String?,
      position: (data['position'] as num?)?.toInt() ?? 0,
      duration: (data['duration'] as num?)?.toInt() ?? 0,
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'profileId': profileId,
      'contentId': contentId,
      'catalogId': catalogId,
      'position': position,
      'duration': duration,
      if (updatedAt != null)
        'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  ProfileProgressModel copyWith({
    String? id,
    String? familyId,
    String? profileId,
    String? contentId,
    String? catalogId,
    int? position,
    int? duration,
    DateTime? updatedAt,
  }) {
    return ProfileProgressModel(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      profileId: profileId ?? this.profileId,
      contentId: contentId ?? this.contentId,
      catalogId: catalogId ?? this.catalogId,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileProgressModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          familyId == other.familyId &&
          profileId == other.profileId &&
          contentId == other.contentId &&
          catalogId == other.catalogId &&
          position == other.position &&
          duration == other.duration &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    familyId,
    profileId,
    contentId,
    catalogId,
    position,
    duration,
    updatedAt,
  );
}
