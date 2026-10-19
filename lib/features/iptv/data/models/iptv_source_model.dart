import 'package:flutter/foundation.dart';
import '../../../../core/domain/models/model_utils.dart';
import '../../domain/entities/iptv_source_entity.dart';

@immutable
class IptvSourceModel extends IptvSourceEntity {
  const IptvSourceModel({
    String? sourceId,
    String? id,
    required super.familyId,
    String? ownerUid,
    String? createdByUid,
    super.serverId,
    required super.name,
    required super.type,
    super.status = 'ready',
    super.catalogId,
    super.currentJobId,
    super.credentialsRef,
    super.epgEnabled = false,
    super.pinProtected = false,
    super.contentCount = 0,
    super.errorCode,
    super.createdAt,
    super.updatedAt,
    super.lastSyncAt,
    this.updatedByUid = '',
  }) : super(
          sourceId: sourceId ?? id ?? '',
          ownerUid: ownerUid ?? createdByUid ?? '',
        );

  final String updatedByUid;

  /// Backward-compatibility getter for legacy components
  String get id => sourceId;

  /// Backward-compatibility getter for legacy components
  String get createdByUid => ownerUid;

  factory IptvSourceModel.fromMap(String id, Map<String, dynamic> data) {
    final rawType = (data['type'] ?? data['format'] ?? 'url') as String;
    final normalizedType = rawType == 'other_m3u8'
        ? 'm3u8_alternative'
        : (rawType == 'm3u' ? 'url' : rawType);

    final sourceId = (data['sourceId'] ?? id) as String;
    final ownerUid = (data['ownerUid'] ?? data['createdByUid'] ?? data['ownerId'] ?? '') as String;

    return IptvSourceModel(
      sourceId: sourceId,
      familyId: (data['familyId'] ?? '') as String,
      ownerUid: ownerUid,
      serverId: data['serverId'] as String?,
      name: (data['name'] ?? '') as String,
      type: normalizedType,
      status: (data['status'] ?? 'ready') as String,
      catalogId: data['catalogId'] as String?,
      currentJobId: data['currentJobId'] as String?,
      credentialsRef: (data['credentialsRef'] ?? data['secretRef']) as String?,
      epgEnabled: (data['epgEnabled'] ?? data['hasEpg'] ?? false) as bool,
      pinProtected: (data['pinProtected'] ?? data['isProtected'] ?? false) as bool,
      contentCount: (data['contentCount'] as num?)?.toInt() ?? 0,
      errorCode: data['errorCode'] as String?,
      updatedByUid: (data['updatedByUid'] ?? '') as String,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
      lastSyncAt: ModelUtils.parseDateTime(data['lastSuccessfulSyncAt'] ?? data['lastSyncAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sourceId': sourceId,
      'familyId': familyId,
      'ownerUid': ownerUid,
      'serverId': serverId,
      'name': name,
      'type': type,
      'status': status,
      'catalogId': catalogId,
      'currentJobId': currentJobId,
      'credentialsRef': credentialsRef,
      'epgEnabled': epgEnabled,
      'pinProtected': pinProtected,
      'contentCount': contentCount,
      'errorCode': errorCode,
      'updatedByUid': updatedByUid,
      if (createdAt != null) 'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null) 'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
      if (lastSyncAt != null) 'lastSyncAt': ModelUtils.toTimestampOrNull(lastSyncAt),
    };
  }

  IptvSourceModel copyWith({
    String? sourceId,
    String? id,
    String? familyId,
    String? ownerUid,
    String? createdByUid,
    String? serverId,
    String? name,
    String? type,
    String? status,
    String? catalogId,
    String? currentJobId,
    String? credentialsRef,
    bool? epgEnabled,
    bool? pinProtected,
    int? contentCount,
    String? errorCode,
    String? updatedByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncAt,
  }) {
    return IptvSourceModel(
      sourceId: sourceId ?? id ?? this.sourceId,
      familyId: familyId ?? this.familyId,
      ownerUid: ownerUid ?? createdByUid ?? this.ownerUid,
      serverId: serverId ?? this.serverId,
      name: name ?? this.name,
      type: type ?? this.type,
      status: status ?? this.status,
      catalogId: catalogId ?? this.catalogId,
      currentJobId: currentJobId ?? this.currentJobId,
      credentialsRef: credentialsRef ?? this.credentialsRef,
      epgEnabled: epgEnabled ?? this.epgEnabled,
      pinProtected: pinProtected ?? this.pinProtected,
      contentCount: contentCount ?? this.contentCount,
      errorCode: errorCode ?? this.errorCode,
      updatedByUid: updatedByUid ?? this.updatedByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}
