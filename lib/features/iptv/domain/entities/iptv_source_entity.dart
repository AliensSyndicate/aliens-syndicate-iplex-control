import 'package:flutter/foundation.dart';

/// Pure domain entity representing an IPTV Source.
@immutable
class IptvSourceEntity {
  const IptvSourceEntity({
    required this.sourceId,
    required this.familyId,
    required this.ownerUid,
    this.serverId,
    required this.name,
    required this.type,
    this.status = 'pending',
    this.catalogId,
    this.currentJobId,
    this.credentialsRef,
    this.epgEnabled = false,
    this.pinProtected = false,
    this.contentCount = 0,
    this.errorCode,
    this.createdAt,
    this.updatedAt,
    this.lastSyncAt,
  });

  final String sourceId;
  final String familyId;
  final String ownerUid;
  final String? serverId;
  final String name;
  final String type; // 'url' | 'file' | 'xtream' | 'm3u8_alternative'
  final String status; // 'pending' | 'queued' | 'syncing' | 'ready' | 'error'
  final String? catalogId;
  final String? currentJobId;
  final String? credentialsRef;
  final bool epgEnabled;
  final bool pinProtected;
  final int contentCount;
  final String? errorCode;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastSyncAt;

  bool get isReady => status == 'ready';
  bool get isSyncing => status == 'syncing' || status == 'queued' || currentJobId != null;
  bool get hasError => status == 'error' || errorCode != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IptvSourceEntity &&
          runtimeType == other.runtimeType &&
          sourceId == other.sourceId &&
          familyId == other.familyId &&
          ownerUid == other.ownerUid &&
          serverId == other.serverId &&
          name == other.name &&
          type == other.type &&
          status == other.status &&
          catalogId == other.catalogId &&
          currentJobId == other.currentJobId &&
          credentialsRef == other.credentialsRef &&
          epgEnabled == other.epgEnabled &&
          pinProtected == other.pinProtected &&
          contentCount == other.contentCount &&
          errorCode == other.errorCode &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          lastSyncAt == other.lastSyncAt;

  @override
  int get hashCode => Object.hashAll([
        sourceId,
        familyId,
        ownerUid,
        serverId,
        name,
        type,
        status,
        catalogId,
        currentJobId,
        credentialsRef,
        epgEnabled,
        pinProtected,
        contentCount,
        errorCode,
        createdAt,
        updatedAt,
        lastSyncAt,
      ]);
}
