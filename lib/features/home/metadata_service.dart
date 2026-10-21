import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/data/firebase_repository.dart';
import '../../core/data/providers.dart';
import '../../core/domain/models.dart';
import 'home_data.dart';

/// TMDB enrichment of an authorized movie/series. Only a confident match
/// (`status: matched`, decided by the backend) is ever returned; otherwise the
/// Home keeps the source's own metadata and never invents anything.
@immutable
class ContentMetadata {
  const ContentMetadata({
    this.poster,
    this.backdrop,
    this.overview = '',
    this.genres = const [],
    this.year,
    this.rating,
    this.runtimeMinutes,
    this.certification,
    this.seasonCount,
    this.cast = const [],
  });

  factory ContentMetadata.fromJson(Map<String, dynamic> json) {
    String? image(Object? v) =>
        v is String && v.startsWith('https://image.tmdb.org/') ? v : null;
    return ContentMetadata(
      poster: image(json['poster']),
      backdrop: image(json['backdrop']),
      overview: '${json['overview'] ?? ''}'.trim(),
      genres: [
        for (final g in (json['genres'] as List? ?? const []))
          if (g is String && g.isNotEmpty) g,
      ],
      year: (json['year'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble(),
      runtimeMinutes: (json['runtimeMinutes'] as num?)?.toInt(),
      certification:
          json['certification'] is String &&
              (json['certification'] as String).isNotEmpty
          ? json['certification'] as String
          : null,
      seasonCount: (json['seasonCount'] as num?)?.toInt(),
      cast: [
        for (final p in (json['cast'] as List? ?? const []))
          if (p is Map && p['name'] is String) '${p['name']}',
      ],
    );
  }

  final String? poster, backdrop, certification;
  final String overview;
  final List<String> genres, cast;
  final int? year, runtimeMinutes, seasonCount;
  final double? rating;
}

abstract class MetadataService {
  /// Summary (poster, backdrop, overview, genres) — enough for cards.
  Future<ContentMetadata?> summary(Entry item);

  /// Full details (adds runtime, certification, cast, seasons) for the sheet.
  Future<ContentMetadata?> details(Entry item);
}

/// Calls the existing `iplexWebTmdb` endpoint. The TMDB key never leaves the
/// server; the endpoint authorizes the exact catalog item through the
/// `manager` callable with this account's ID token AND App Check token.
class TmdbMetadataService implements MetadataService {
  TmdbMetadataService(
    this._contextFamilyId, {
    http.Client? client,
    this.baseUrl = 'https://iplex-2c8fc.web.app',
  }) : _client = client ?? http.Client();

  final String? Function() _contextFamilyId;
  final http.Client _client;
  final String baseUrl;
  final _summaries = <String, Future<_Match?>>{};
  final _details = <String, Future<ContentMetadata?>>{};
  int _running = 0;
  final _waiting = <Completer<void>>[];

  @override
  Future<ContentMetadata?> summary(Entry item) async =>
      (await _match(item))?.summary;

  @override
  Future<ContentMetadata?> details(Entry item) {
    final key = '${item.sourceId}/${item.id}';
    return _remember(_details, key, () async {
      final match = await _match(item);
      if (match == null) return null;
      final path = item.kind == 'movie'
          ? '/api/tmdb/movie/${match.tmdbId}'
          : '/api/tmdb/tv/${match.tmdbId}';
      final json = await _get(path, item, const {});
      return json == null ? match.summary : ContentMetadata.fromJson(json);
    });
  }

  Future<_Match?> _match(Entry item) {
    if (!item.isPlayableTitle) return Future.value();
    return _remember(_summaries, '${item.sourceId}/${item.id}', () async {
      final json = await _get('/api/tmdb/match', item, {
        'kind': item.kind,
        'title': item.name,
        if (item.year != null) 'year': '${item.year}',
      });
      final summary = json?['summary'];
      if (json?['status'] != 'matched' || summary is! Map) return null;
      final tmdbId = (summary['tmdbId'] as num?)?.toInt();
      if (tmdbId == null) return null;
      return _Match(
        tmdbId,
        ContentMetadata.fromJson(Map<String, dynamic>.from(summary)),
      );
    });
  }

  /// Successful lookups (including "no match") are kept for the session;
  /// failures are not, so a later attempt can succeed.
  Future<T?> _remember<T>(
    Map<String, Future<T?>> cache,
    String key,
    Future<T?> Function() load,
  ) => cache.putIfAbsent(key, () async {
    try {
      return await load();
    } catch (_) {
      cache.remove(key);
      return null;
    }
  });

  Future<Map<String, dynamic>?> _get(
    String path,
    Entry item,
    Map<String, String> params,
  ) async {
    await _acquire();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final idToken = await user.getIdToken();
      final appCheck = await FirebaseAppCheck.instance.getToken();
      if (idToken == null || appCheck == null) return null;
      final context = _contextFamilyId();
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: {
          ...params,
          'sourceId': item.sourceId,
          'itemId': item.id,
          'contextFamilyId': context ?? 'null',
        },
      );
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
              'X-Firebase-AppCheck': appCheck,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw http.ClientException('metadata ${response.statusCode}');
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body is Map ? Map<String, dynamic>.from(body) : null;
    } finally {
      _release();
    }
  }

  // At most 4 requests at a time: a Home has up to 50 cards.
  Future<void> _acquire() async {
    if (_running < 4) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }
}

class _Match {
  const _Match(this.tmdbId, this.summary);
  final int tmdbId;
  final ContentMetadata summary;
}

/// No enrichment (tests, emulators): cards and sheets use source metadata.
class NoMetadataService implements MetadataService {
  const NoMetadataService();
  @override
  Future<ContentMetadata?> summary(Entry item) async => null;
  @override
  Future<ContentMetadata?> details(Entry item) async => null;
}

final metadataServiceProvider = Provider<MetadataService>((ref) {
  final repository = ref.watch(repositoryProvider);
  if (repository is! FirebaseManagerRepository ||
      !repository.configured ||
      const bool.fromEnvironment('USE_EMULATORS')) {
    return const NoMetadataService();
  }
  return TmdbMetadataService(() => repository.contextFamilyId);
});
