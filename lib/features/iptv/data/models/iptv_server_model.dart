import 'package:flutter/foundation.dart';
import '../../../../core/domain/models/model_utils.dart';
import '../../domain/entities/iptv_server_entity.dart';

@immutable
class IptvServerModel extends IptvServerEntity {
  const IptvServerModel({
    required super.serverId,
    required super.type,
    required super.canonicalEndpoint,
    required super.identityHash,
    super.status,
    super.createdAt,
    super.updatedAt,
  });

  factory IptvServerModel.fromMap(String id, Map<String, dynamic> data) {
    return IptvServerModel(
      serverId: (data['serverId'] ?? id) as String,
      type: (data['type'] ?? '') as String,
      canonicalEndpoint: (data['canonicalEndpoint'] ?? '') as String,
      identityHash: (data['identityHash'] ?? '') as String,
      status: (data['status'] ?? 'active') as String,
      createdAt: ModelUtils.parseDateTime(data['createdAt']),
      updatedAt: ModelUtils.parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'serverId': serverId,
      'type': type,
      'canonicalEndpoint': canonicalEndpoint,
      'identityHash': identityHash,
      'status': status,
      if (createdAt != null) 'createdAt': ModelUtils.toTimestampOrNull(createdAt),
      if (updatedAt != null) 'updatedAt': ModelUtils.toTimestampOrNull(updatedAt),
    };
  }

  IptvServerModel copyWith({
    String? serverId,
    String? type,
    String? canonicalEndpoint,
    String? identityHash,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return IptvServerModel(
      serverId: serverId ?? this.serverId,
      type: type ?? this.type,
      canonicalEndpoint: canonicalEndpoint ?? this.canonicalEndpoint,
      identityHash: identityHash ?? this.identityHash,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
