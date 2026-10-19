import 'package:flutter/foundation.dart';
import '../../../../core/domain/models/model_utils.dart';
import '../../domain/entities/iptv_catalog_entity.dart';

@immutable
class IptvCatalogModel extends IptvCatalogEntity {
  const IptvCatalogModel({
    required super.catalogId,
    super.serverId,
    super.schemaVersion = 1,
    required super.version,
    required super.storagePath,
    super.status = 'ready',
    super.contentCount = 0,
    super.activeSourceCount = 0,
    super.integrityHash,
    super.createdAt,
    super.lastSuccessfulSyncAt,
    super.lastAttemptAt,
    super.updatedAt,
  });

  /// Backward-compatibility getter
  String get id => catalogId;

  factory IptvCatalogModel.fromMap(String id, Map<String, dynamic> data) {
    return IptvCatalogModel(
      catalogId: (data['catalogId'] ?? id) as String,
      serverId: data['serverId'] as String?,
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ?? 1,
      version: (data['version'] ?? id).toString(),
      storagePath: (data['storagePath'] ?? '') as String,
      status: (data['status'] ?? 'ready') as String,
      contentCount: (data['contentCount'] as num?)?.toInt() ?? 0,
      activeSourceCount: (data['activeSourceCount'] as num?)?.toInt() ?? 0,
      integrityHash: data['integrityHash'] as String?,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      lastSuccessfulSyncAt: ModelUtils.parseDateTime(data['lastSuccessfulSyncAt']),
      lastAttemptAt: ModelUtils.parseDateTime(data['lastAttemptAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'catalogId': catalogId,
      'serverId': serverId,
      'schemaVersion': schemaVersion,
      'version': version,
      'storagePath': storagePath,
      'status': status,
      'contentCount': contentCount,
      'activeSourceCount': activeSourceCount,
      if (integrityHash != null) 'integrityHash': integrityHash,
      if (createdAt != null) 'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (lastSuccessfulSyncAt != null)
        'lastSuccessfulSyncAt': ModelUtils.toTimestampOrNull(lastSuccessfulSyncAt),
      if (lastAttemptAt != null)
        'lastAttemptAt': ModelUtils.toTimestampOrNull(lastAttemptAt),
      if (updatedAt != null) 'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  IptvCatalogModel copyWith({
    String? catalogId,
    String? serverId,
    int? schemaVersion,
    String? version,
    String? storagePath,
    String? status,
    int? contentCount,
    int? activeSourceCount,
    String? integrityHash,
    DateTime? createdAt,
    DateTime? lastSuccessfulSyncAt,
    DateTime? lastAttemptAt,
    DateTime? updatedAt,
  }) {
    return IptvCatalogModel(
      catalogId: catalogId ?? this.catalogId,
      serverId: serverId ?? this.serverId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      version: version ?? this.version,
      storagePath: storagePath ?? this.storagePath,
      status: status ?? this.status,
      contentCount: contentCount ?? this.contentCount,
      activeSourceCount: activeSourceCount ?? this.activeSourceCount,
      integrityHash: integrityHash ?? this.integrityHash,
      createdAt: createdAt ?? this.createdAt,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
