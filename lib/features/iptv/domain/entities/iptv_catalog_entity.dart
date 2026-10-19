import 'package:flutter/foundation.dart';

/// Pure domain entity representing an IPTV Catalog metadata.
/// The large catalog content JSON is safely stored in Cloud Storage.
@immutable
class IptvCatalogEntity {
  const IptvCatalogEntity({
    required this.catalogId,
    this.serverId,
    this.schemaVersion = 1,
    required this.version,
    required this.storagePath,
    this.status = 'ready',
    this.contentCount = 0,
    this.activeSourceCount = 0,
    this.integrityHash,
    this.createdAt,
    this.lastSuccessfulSyncAt,
    this.lastAttemptAt,
    this.updatedAt,
  });

  final String catalogId;
  final String? serverId;
  final int schemaVersion;
  final String version;
  final String storagePath;
  final String status;
  final int contentCount;
  final int activeSourceCount;
  final String? integrityHash;
  final DateTime? createdAt;
  final DateTime? lastSuccessfulSyncAt;
  final DateTime? lastAttemptAt;
  final DateTime? updatedAt;

  bool get isReady => status == 'ready';
  bool get hasActiveUsers => activeSourceCount > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IptvCatalogEntity &&
          runtimeType == other.runtimeType &&
          catalogId == other.catalogId &&
          serverId == other.serverId &&
          schemaVersion == other.schemaVersion &&
          version == other.version &&
          storagePath == other.storagePath &&
          status == other.status &&
          contentCount == other.contentCount &&
          activeSourceCount == other.activeSourceCount &&
          integrityHash == other.integrityHash &&
          createdAt == other.createdAt &&
          lastSuccessfulSyncAt == other.lastSuccessfulSyncAt &&
          lastAttemptAt == other.lastAttemptAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        catalogId,
        serverId,
        schemaVersion,
        version,
        storagePath,
        status,
        contentCount,
        activeSourceCount,
        integrityHash,
        createdAt,
        lastSuccessfulSyncAt,
        lastAttemptAt,
        updatedAt,
      );
}
