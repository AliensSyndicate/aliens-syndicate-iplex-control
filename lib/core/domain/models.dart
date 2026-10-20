import 'package:flutter/foundation.dart';

export 'models/catalog_model.dart';
export 'models/device_model.dart';
export 'models/family_member_model.dart';
export 'models/family_model.dart';
export 'models/iptv_source_model.dart';
export 'models/iptv_sync_job_model.dart';
export '../../features/iptv/data/models/iptv_server_model.dart';
export '../../features/iptv/domain/entities/iptv_server_entity.dart';
export 'models/playback_session_model.dart';
export 'models/profile_favorite_model.dart';
export 'models/profile_model.dart';
export 'models/profile_progress_model.dart';
export 'models/subscription_model.dart';
export 'models/user_model.dart';

@immutable
class Account {
  const Account({
    required this.uid,
    this.name = '',
    this.email = '',
    this.familyId,
    this.iptvWorkspaceId,
    this.publicCode,
    this.familyIds = const [],
    this.locale = 'system',
  });
  final String uid, name, email, locale;
  final String? familyId;
  final String? iptvWorkspaceId;
  final String? publicCode;
  final List<String> familyIds;
  List<String> get memberships => {...familyIds, ?familyId}.toList();
  String? get resourceScopeId => familyId ?? iptvWorkspaceId;
  String? get iptvScopeId => iptvWorkspaceId ?? familyId;
}

@immutable
class Family {
  const Family({
    required this.id,
    required this.adminId,
    required this.members,
    this.name = '',
    this.parentalPinConfigured = false,
  });
  final String id, adminId, name;
  final Map<String, String> members;

  /// The family has a parental PIN (the hash stays backend-only).
  final bool parentalPinConfigured;
  bool isAdmin(String uid) => adminId == uid && members[uid] == 'admin';
}

/// Immutable metadata boundary. Secrets never enter this model.
@immutable
class Entry {
  Entry(this.id, Map<String, dynamic> data) : data = Map.unmodifiable(data);
  final String id;
  final Map<String, dynamic> data;
  String text(String key) => data[key] as String? ?? '';
  int number(String key) => (data[key] as num?)?.toInt() ?? 0;
  String get name => text('name').isEmpty ? text('title') : text('name');
  bool onlineAt(DateTime now) =>
      number('onlineUntil') > now.millisecondsSinceEpoch &&
      text('sessionId').isNotEmpty;
}

@immutable
class CatalogPage {
  const CatalogPage(this.items, this.cursor, this.hasMore);
  final List<Entry> items;
  final Object? cursor;
  final bool hasMore;
}

class AppFailure implements Exception {
  const AppFailure(this.code, [this.details = const {}]);
  final String code;
  final Map<String, dynamic> details;
}
