import 'package:flutter/foundation.dart';

/// Pure domain entity representing an IPTV Server identified by the backend.
@immutable
class IptvServerEntity {
  const IptvServerEntity({
    required this.serverId,
    required this.type,
    required this.canonicalEndpoint,
    required this.identityHash,
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  });

  final String serverId;
  final String type;
  final String canonicalEndpoint;
  final String identityHash;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IptvServerEntity &&
          runtimeType == other.runtimeType &&
          serverId == other.serverId &&
          type == other.type &&
          canonicalEndpoint == other.canonicalEndpoint &&
          identityHash == other.identityHash &&
          status == other.status &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    serverId,
    type,
    canonicalEndpoint,
    identityHash,
    status,
    createdAt,
    updatedAt,
  );
}
