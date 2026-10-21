import 'package:flutter/foundation.dart';

import '../../core/domain/models.dart';

/// Catalog item as returned by readSourceCatalog/readHome: public ids and
/// display metadata only (never a stream URL or provider credential).
extension HomeItem on Entry {
  String get kind => text('kind');
  String get sourceId => text('sourceId');
  bool get isChannel => kind == 'channel';
  bool get isPlayableTitle => kind == 'movie' || kind == 'series';

  /// Artwork published by the source (https, credential-free by the backend).
  String? get sourceImage {
    final value = text('imageRef');
    return value.startsWith('https://') ? value : null;
  }

  /// Year as published by the source ("2021", 2021 or absent).
  int? get year {
    final raw = data['year'];
    final value = raw is num ? raw.toInt() : int.tryParse('$raw'.trim());
    return value != null && value >= 1900 && value <= 2100 ? value : null;
  }

  HomeProgress? get progress {
    final raw = data['progress'];
    if (raw is! Map) return null;
    final position = (raw['position'] as num?)?.toDouble() ?? 0;
    final duration = (raw['duration'] as num?)?.toDouble() ?? 0;
    return duration > 0 ? HomeProgress(position, duration) : null;
  }

  /// Series episode of a "continue watching" entry.
  String? get episodeId {
    final value = text('episodeId');
    return value.isEmpty ? null : value;
  }
}

@immutable
class HomeProgress {
  const HomeProgress(this.position, this.duration);
  final double position, duration;
  double get fraction => (position / duration).clamp(0, 1).toDouble();
}

/// The account's own profile in the current scope (writes carry its generation).
@immutable
class HomeProfile {
  const HomeProfile(this.id, this.name, this.type, this.favoritesGeneration);
  final String id, name, type;
  final int favoritesGeneration;
  bool get persistent => type != 'guest';
}

/// readHome: personal rows of the account's profile + recent rows of the
/// selected source. Every list is already filtered by the backend with the
/// same visibility rules as the catalog.
@immutable
class HomeData {
  const HomeData({
    this.profile,
    this.favoriteIds = const {},
    this.favorites = const [],
    this.continueWatching = const [],
    this.myList = const [],
    this.recentMovies = const [],
    this.recentSeries = const [],
  });

  factory HomeData.fromJson(Map<String, dynamic> json) {
    List<Entry> items(String key) => [
      for (final raw in (json[key] as List? ?? const []))
        if (raw is Map && raw['id'] is String)
          Entry(raw['id'] as String, Map<String, dynamic>.from(raw)),
    ];
    final profile = json['profile'];
    return HomeData(
      profile: profile is Map && profile['id'] is String
          ? HomeProfile(
              profile['id'] as String,
              '${profile['name'] ?? ''}',
              '${profile['type'] ?? 'regular'}',
              ((profile['generations'] as Map?)?['favorites'] as num?)
                      ?.toInt() ??
                  0,
            )
          : null,
      favoriteIds: {
        for (final id in (json['favoriteIds'] as List? ?? const []))
          if (id is String) id,
      },
      favorites: items('favorites'),
      continueWatching: items('continueWatching'),
      myList: items('myList'),
      recentMovies: items('recentMovies'),
      recentSeries: items('recentSeries'),
    );
  }

  final HomeProfile? profile;
  final Set<String> favoriteIds;
  final List<Entry> favorites, continueWatching, myList;
  final List<Entry> recentMovies, recentSeries;

  bool get isEmpty =>
      favorites.isEmpty &&
      continueWatching.isEmpty &&
      myList.isEmpty &&
      recentMovies.isEmpty &&
      recentSeries.isEmpty;

  bool isFavorite(Entry item) => favoriteIds.contains(item.id);
}

/// Sources the Home can show: published catalog, and unlocked when protected.
List<Entry> readySources(List<Entry> sources, Set<String> unlocked) => sources
    .where(
      (entry) =>
          entry.text('version').isNotEmpty &&
          (entry.data['isProtected'] != true || unlocked.contains(entry.id)),
    )
    .toList();
