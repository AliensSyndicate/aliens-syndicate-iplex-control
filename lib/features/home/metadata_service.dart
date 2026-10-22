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

String? _tmdbImage(Object? v) =>
    v is String && v.startsWith('https://image.tmdb.org/') ? v : null;
String? _text(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

/// The same TMDB image at a higher resolution (`original`, or [size]):
/// TMDB serves every size from the same path.
String? tmdbSized(String? url, [String size = 'original']) {
  if (url == null) return null;
  // Any TMDB size segment (w342, original, w1066_and_h600_face…).
  return url.replaceFirst(RegExp(r'/t/p/[^/]+/'), '/t/p/$size/');
}

/// One episode of a TMDB season (editorial information only).
@immutable
class EpisodeInfo {
  const EpisodeInfo({
    required this.number,
    this.name = '',
    this.overview = '',
    this.runtimeMinutes,
    this.still,
  });
  final int number;
  final String name, overview;
  final int? runtimeMinutes;
  final String? still;
}

/// A person in the cast or crew. [id] opens the person's page (TMDB person id).
@immutable
class Credit {
  const Credit({this.id, required this.name, this.role = '', this.photo});
  factory Credit.fromJson(Map json) => Credit(
    id: (json['id'] as num?)?.toInt(),
    name: '${json['name']}',
    role: _text(json['role']) ?? '',
    photo: _tmdbImage(json['photo']),
  );
  final int? id;
  final String name, role;
  final String? photo;
}

/// Editorial season (TMDB): never a claim that its episodes are playable.
@immutable
class SeasonInfo {
  const SeasonInfo(this.number, this.name, this.episodeCount);
  final int number, episodeCount;
  final String name;
}

/// TMDB metadata of a movie/series. For catalog items only a confident match
/// (`status: matched`, decided by the backend) is ever returned; editorial
/// titles come from the discovery endpoint. Missing fields stay null/empty and
/// are simply not shown — nothing is invented.
@immutable
class ContentMetadata {
  const ContentMetadata({
    this.tmdbId,
    this.title,
    this.originalTitle,
    this.releaseDate,
    this.poster,
    this.posterOriginal,
    this.backdrop,
    this.overview = '',
    this.genres = const [],
    this.year,
    this.rating,
    this.runtimeMinutes,
    this.certification,
    this.certificationDescriptors = const [],
    this.seasonCount,
    this.episodeCount,
    this.cast = const [],
    this.crew = const [],
    this.seasons = const [],
  });

  factory ContentMetadata.fromJson(Map<String, dynamic> json) {
    List<Credit> people(String key) => [
      for (final p in (json[key] as List? ?? const []))
        if (p is Map && p['name'] is String && '${p['name']}'.isNotEmpty)
          Credit.fromJson(p),
    ];
    return ContentMetadata(
      tmdbId: (json['tmdbId'] as num?)?.toInt(),
      title: _text(json['title']),
      originalTitle: _text(json['originalTitle']),
      releaseDate: DateTime.tryParse('${json['releaseDate'] ?? ''}'),
      poster: _tmdbImage(json['poster']),
      posterOriginal: _tmdbImage(json['posterOriginal']),
      backdrop: _tmdbImage(json['backdrop']),
      overview: '${json['overview'] ?? ''}'.trim(),
      genres: [
        for (final g in (json['genres'] as List? ?? const []))
          if (g is String && g.isNotEmpty) g,
      ],
      year: (json['year'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble(),
      runtimeMinutes: (json['runtimeMinutes'] as num?)?.toInt(),
      certification: _text(json['certification']),
      certificationDescriptors: [
        for (final d in (json['certificationDescriptors'] as List? ?? const []))
          ?_text(d),
      ],
      seasonCount: (json['seasonCount'] as num?)?.toInt(),
      episodeCount: (json['episodeCount'] as num?)?.toInt(),
      cast: people('cast'),
      crew: people('crew'),
      seasons: [
        for (final s in (json['seasons'] as List? ?? const []))
          if (s is Map && s['seasonNumber'] is num)
            SeasonInfo(
              (s['seasonNumber'] as num).toInt(),
              '${s['name'] ?? ''}',
              (s['episodeCount'] as num?)?.toInt() ?? 0,
            ),
      ],
    );
  }

  final int? tmdbId;
  final String? title, originalTitle, poster, backdrop, certification;

  /// Original-resolution poster: background of the details page.
  final String? posterOriginal;

  /// Reasons of the Brazilian age rating ("Violência", "Drogas"…).
  final List<String> certificationDescriptors;
  final DateTime? releaseDate;
  final String overview;
  final List<String> genres;
  final List<Credit> cast, crew;
  final List<SeasonInfo> seasons;
  final int? year, runtimeMinutes, seasonCount, episodeCount;
  final double? rating;
}

/// One work of a person's filmography (TMDB, adult content excluded server-side).
@immutable
class PersonCredit {
  const PersonCredit({
    required this.tmdbId,
    required this.kind,
    required this.title,
    this.originalTitle,
    this.character = '',
    this.job = '',
    this.date,
    this.year,
    this.poster,
    this.episodeCount,
  });
  final int tmdbId;
  final String kind, title, character, job;
  final String? originalTitle, poster;
  final DateTime? date;
  final int? year, episodeCount;

  /// Editorial card/route target (no IPTV source): see [EditorialTitle].
  Entry get entry => editorialEntry(
    kind: kind,
    tmdbId: tmdbId,
    title: title,
    originalTitle: originalTitle,
    year: year,
    poster: poster,
  );
}

/// Official profile of a person (TMDB external ids; URL built server-side).
@immutable
class SocialLink {
  const SocialLink(this.network, this.url);
  final String network;
  final Uri url;

  static const _hosts = {
    'instagram': 'www.instagram.com',
    'x': 'x.com',
    'facebook': 'www.facebook.com',
    'tiktok': 'www.tiktok.com',
    'youtube': 'www.youtube.com',
    'imdb': 'www.imdb.com',
  };

  /// Brand name (not translated).
  String get label => const {
    'instagram': 'Instagram',
    'x': 'X',
    'facebook': 'Facebook',
    'tiktok': 'TikTok',
    'youtube': 'YouTube',
    'imdb': 'IMDb',
  }[network]!;

  /// Only https links to the expected host of each network.
  static SocialLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final network = '${raw['network']}';
    final url = Uri.tryParse('${raw['url']}');
    if (url == null ||
        url.scheme != 'https' ||
        _hosts[network] == null ||
        url.host != _hosts[network]) {
      return null;
    }
    return SocialLink(network, url);
  }
}

@immutable
class PersonDetails {
  const PersonDetails({
    required this.tmdbId,
    required this.name,
    this.biography = '',
    this.birthday,
    this.deathday,
    this.placeOfBirth,
    this.photo,
    this.social = const [],
    this.credits = const [],
  });

  factory PersonDetails.fromJson(Map<String, dynamic> json) => PersonDetails(
    tmdbId: (json['tmdbId'] as num).toInt(),
    name: '${json['name'] ?? ''}',
    biography: '${json['biography'] ?? ''}'.trim(),
    birthday: DateTime.tryParse('${json['birthday'] ?? ''}'),
    deathday: DateTime.tryParse('${json['deathday'] ?? ''}'),
    placeOfBirth: _text(json['placeOfBirth']),
    photo: _tmdbImage(json['photo']),
    social: [
      for (final raw in (json['social'] as List? ?? const []))
        ?SocialLink.fromJson(raw),
    ],
    credits: [
      for (final c in (json['credits'] as List? ?? const []))
        if (c is Map &&
            c['tmdbId'] is num &&
            (c['kind'] == 'movie' || c['kind'] == 'series') &&
            _text(c['title']) != null)
          PersonCredit(
            tmdbId: (c['tmdbId'] as num).toInt(),
            kind: '${c['kind']}',
            title: _text(c['title'])!,
            originalTitle: _text(c['originalTitle']),
            character: _text(c['character']) ?? '',
            job: _text(c['job']) ?? '',
            date: DateTime.tryParse('${c['date'] ?? ''}'),
            year: (c['year'] as num?)?.toInt(),
            poster: _tmdbImage(c['poster']),
            episodeCount: (c['episodeCount'] as num?)?.toInt(),
          ),
    ],
  );

  final int tmdbId;
  final String name, biography;
  final DateTime? birthday, deathday;
  final String? placeOfBirth, photo;
  final List<SocialLink> social;
  final List<PersonCredit> credits;
}

abstract class MetadataService {
  /// Summary (poster, backdrop, overview, genres) of a catalog item — for cards.
  Future<ContentMetadata?> summary(Entry item);

  /// Full details (runtime, certification, cast, seasons) of a catalog item.
  Future<ContentMetadata?> details(Entry item);

  /// Editorial title (TMDB) that may not exist in any IPTV source. null when
  /// TMDB has no such title; throws when the service is unreachable.
  Future<ContentMetadata?> title(String kind, int tmdbId);

  /// Person with filmography. null when unknown; throws when unreachable.
  Future<PersonDetails?> person(int tmdbId);

  /// Episodes of one TMDB season of [series] (catalog or editorial entry).
  /// Empty when TMDB has nothing; never a claim of availability.
  Future<List<EpisodeInfo>> season(Entry series, int tmdbId, int number);
}

List<EpisodeInfo> _episodes(Map<String, dynamic>? json) => [
  for (final e in (json?['episodes'] as List? ?? const []))
    if (e is Map && e['episodeNumber'] is num)
      EpisodeInfo(
        number: (e['episodeNumber'] as num).toInt(),
        name: _text(e['name']) ?? '',
        overview: _text(e['overview']) ?? '',
        runtimeMinutes: (e['runtimeMinutes'] as num?)?.toInt(),
        still: _tmdbImage(e['still']),
      ),
];

/// Thrown when editorial discovery is not allowed (TV, kids profile, quota).
class MetadataUnavailable implements Exception {
  const MetadataUnavailable(this.status);
  final int status;
}

/// Calls the existing `iplexWebTmdb` endpoint. The TMDB key never leaves the
/// server. Catalog items are authorized one by one (`manager` →
/// authorizeMetadata); editorial discovery (`/discover`) by `manager` →
/// authorizeDiscovery. Both need this account's ID token AND App Check token.
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
  final _titles = <String, Future<ContentMetadata?>>{};
  final _people = <int, Future<PersonDetails?>>{};
  final _seasons = <String, Future<List<EpisodeInfo>?>>{};
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
      final json = await _get(path, item: item);
      return json == null ? match.summary : ContentMetadata.fromJson(json);
    });
  }

  @override
  Future<ContentMetadata?> title(String kind, int tmdbId) =>
      _keep(_titles, '$kind/$tmdbId', () async {
        final json = await _get(
          '/api/tmdb/discover/${kind == 'movie' ? 'movie' : 'tv'}/$tmdbId',
        );
        return json == null ? null : ContentMetadata.fromJson(json);
      });

  @override
  Future<PersonDetails?> person(int tmdbId) => _keep(_people, tmdbId, () async {
    final json = await _get('/api/tmdb/discover/person/$tmdbId');
    return json == null ? null : PersonDetails.fromJson(json);
  });

  @override
  Future<List<EpisodeInfo>> season(
    Entry series,
    int tmdbId,
    int number,
  ) async =>
      await _remember(_seasons, '$tmdbId/$number', () async {
        final editorial = series.isEditorial;
        final json = await _get(
          editorial
              ? '/api/tmdb/discover/tv/$tmdbId/season/$number'
              : '/api/tmdb/tv/$tmdbId/season/$number',
          item: editorial ? null : series,
        );
        return _episodes(json);
      }) ??
      const [];

  Future<_Match?> _match(Entry item) {
    if (!item.isPlayableTitle || item.isEditorial) return Future.value();
    return _remember(_summaries, '${item.sourceId}/${item.id}', () async {
      final json = await _get(
        '/api/tmdb/match',
        item: item,
        params: {
          'kind': item.kind,
          'title': item.name,
          if (item.year != null) 'year': '${item.year}',
        },
      );
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
  /// failures are not, so a later attempt can succeed. Cards never fail.
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

  /// Same cache, but errors reach the page (it shows a retry instead of
  /// pretending the title has no information).
  Future<T?> _keep<K, T>(
    Map<K, Future<T?>> cache,
    K key,
    Future<T?> Function() load,
  ) {
    final future = cache.putIfAbsent(key, load);
    future.catchError((_) {
      cache.remove(key);
      return null;
    }).ignore();
    return future;
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    Entry? item,
    Map<String, String> params = const {},
  }) async {
    await _acquire();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw const MetadataUnavailable(401);
      final idToken = await user.getIdToken();
      final appCheck = await FirebaseAppCheck.instance.getToken();
      if (idToken == null || appCheck == null) {
        throw const MetadataUnavailable(401);
      }
      final context = _contextFamilyId();
      final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: {
          ...params,
          if (item != null) ...{'sourceId': item.sourceId, 'itemId': item.id},
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
      if (response.statusCode == 403 || response.statusCode == 401) {
        throw MetadataUnavailable(response.statusCode);
      }
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

/// No enrichment (tests, emulators): cards and pages use source metadata;
/// editorial pages report that the information is unavailable.
class NoMetadataService implements MetadataService {
  const NoMetadataService();
  @override
  Future<ContentMetadata?> summary(Entry item) async => null;
  @override
  Future<ContentMetadata?> details(Entry item) async => null;
  @override
  Future<ContentMetadata?> title(String kind, int tmdbId) async =>
      throw const MetadataUnavailable(503);
  @override
  Future<PersonDetails?> person(int tmdbId) async =>
      throw const MetadataUnavailable(503);
  @override
  Future<List<EpisodeInfo>> season(
    Entry series,
    int tmdbId,
    int number,
  ) async => const [];
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
