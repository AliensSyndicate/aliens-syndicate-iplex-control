import 'package:flutter/foundation.dart';
import 'model_utils.dart';

/// Representation of catalog metadata in `catalogs/{catalogId}`.
/// Large payload data is stored in Cloud Storage (`storagePath`).
@immutable
class CatalogModel {
  const CatalogModel({
    required this.id,
    this.status = 'ready',
    this.version = 1,
    required this.storagePath,
    this.contentCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String status;
  final int version;
  final String storagePath;
  final int contentCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isReady => status == 'ready';

  factory CatalogModel.fromMap(String id, Map<String, dynamic> data) {
    return CatalogModel(
      id: id,
      status: (data['status'] ?? 'ready') as String,
      version: (data['version'] as num?)?.toInt() ?? 1,
      storagePath: (data['storagePath'] ?? '') as String,
      contentCount: (data['contentCount'] as num?)?.toInt() ?? 0,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'version': version,
      'storagePath': storagePath,
      'contentCount': contentCount,
      if (createdAt != null) 'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null) 'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  CatalogModel copyWith({
    String? id,
    String? status,
    int? version,
    String? storagePath,
    int? contentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CatalogModel(
      id: id ?? this.id,
      status: status ?? this.status,
      version: version ?? this.version,
      storagePath: storagePath ?? this.storagePath,
      contentCount: contentCount ?? this.contentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          version == other.version &&
          storagePath == other.storagePath &&
          contentCount == other.contentCount &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        status,
        version,
        storagePath,
        contentCount,
        createdAt,
        updatedAt,
      );
}
