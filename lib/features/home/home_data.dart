import 'package:flutter/foundation.dart';

import '../../core/domain/models.dart';

/// Catalog item as returned by readSourceCatalog/readHome: public ids and
/// display metadata only (never a stream URL or provider credential).
extension HomeItem on Entry {
  String get kind => text('kind');
  String get sourceId => text('sourceId');
  bool get isChannel => kind == 'channel';
  bool get isPlayableTitle => kind == 'movie' || kind == 'series';

  /// Artwork published by the source (http or https as published,
  /// credential-free by the backend).
  String? get sourceImage {
    final value = text('imageRef');
    return value.startsWith('https://') || value.startsWith('http://')
        ? value
        : null;
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

  /// Editorial identity (TMDB): published by the provider, attached by the
  /// library, or the editorial entry itself.
  int? get tmdbId {
    final raw = data['tmdbId'] ?? (data['library'] as Map?)?['tmdbId'];
    return raw is num && raw > 0 ? raw.toInt() : null;
  }

  /// A title known only from TMDB (filmography, a saved title no catalog
  /// offers): no source, never playable as such.
  bool get isEditorial => sourceId.isEmpty && tmdbId != null;

  /// TMDB poster carried by editorial entries.
  String? get editorialPoster {
    final value = text('poster');
    return value.startsWith('https://image.tmdb.org/') ? value : null;
  }

  /// Library row id of a saved title (canonical row, any source).
  String? get libraryId {
    final raw = (data['library'] as Map?)?['id'];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  /// Keys under which the library may know this title.
  Set<String> get libraryKeys => {
    if (!isEditorial) id,
    ?libraryId,
    if (tmdbId case final t? when kind != 'channel')
      'tmdb:${kind == 'movie' ? 'movie' : 'tv'}:$t',
  };

  /// Series episode of a "continue watching" entry.
  String? get episodeId {
    final value = text('episodeId');
    return value.isEmpty ? null : value;
  }
}

/// Editorial title as an [Entry] (same cards and pages as catalog items).
Entry editorialEntry({
  required String kind,
  required int tmdbId,
  required String title,
  String? originalTitle,
  int? year,
  String? poster,
}) => Entry('tmdb-${kind == 'movie' ? 'movie' : 'tv'}-$tmdbId', {
  'kind': kind,
  'title': title,
  'tmdbId': tmdbId,
  'originalTitle': ?originalTitle,
  'year': ?year,
  'poster': ?poster,
  'available': false,
});

/// Home sections; the name is the backend `readHome.section` value.
enum HomeSection {
  favorites,
  continueWatching,
  wishlist,
  releases,
  watched,
  recentMovies,
  recentSeries,
  recentSearches,
}

/// The "Meu iPlex" rows, in order (same rule as the TV): Continuar
/// assistindo, Favoritos, Lista de desejos, Lançamentos and Assistidos. A
/// guest only has Lançamentos (the backend returns no personal rows for it)
/// and a row without content is never shown.
const homeSections = [
  HomeSection.continueWatching,
  HomeSection.favorites,
  HomeSection.wishlist,
  HomeSection.releases,
  HomeSection.watched,
];

/// Rows with 16:9 covers (channels square); the others use 2:3 posters.
const landscapeSections = {HomeSection.continueWatching, HomeSection.favorites};

/// Titles per kind in Lançamentos (the newest movies and series, merged).
const releasesPerKind = 5;

/// Favoritos and Lista de desejos: independent lists of the same profile.
enum LibraryList { favorites, wishlist }

@immutable
class HomeProgress {
  const HomeProgress(this.position, this.duration);
  final double position, duration;
  double get fraction => (position / duration).clamp(0, 1).toDouble();
}

/// The account's own profile in the current scope (writes carry its generation).
@immutable
class HomeProfile {
  const HomeProfile(
    this.id,
    this.name,
    this.type,
    this.favoritesGeneration, [
    int? wishlistGeneration,
  ]) : wishlistGeneration = wishlistGeneration ?? favoritesGeneration;
  final String id, name, type;

  /// Each list has its own generation (older backends: the wishlist follows
  /// the favorites one).
  final int favoritesGeneration, wishlistGeneration;
  bool get persistent => type != 'guest';

  /// Kids profiles only see catalog items classified as children's content:
  /// no editorial discovery (people, filmographies, titles outside the catalog).
  bool get canDiscover => type != 'kids';
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
    this.recentSearches = const [],
    this.releases = const [],
    this.watched = const [],
    this.libraryFavorites = const [],
    this.wishlist = const [],
    this.saved = const {},
  });

  factory HomeData.fromJson(Map<String, dynamic> json) {
    List<Entry> items(String key) => [
      for (final raw in (json[key] as List? ?? const []))
        if (raw is Map && raw['id'] is String)
          Entry(raw['id'] as String, Map<String, dynamic>.from(raw)),
    ];
    final profile = json['profile'];
    final library = json['library'];
    Set<String> keys(String list) => {
      for (final k in ((json['saved'] as Map?)?[list] as List? ?? const []))
        if (k is String) k,
    };
    return HomeData(
      profile: profile is Map && profile['id'] is String
          ? HomeProfile(
              profile['id'] as String,
              '${profile['name'] ?? ''}',
              '${profile['type'] ?? 'regular'}',
              ((profile['generations'] as Map?)?['favorites'] as num?)
                      ?.toInt() ??
                  0,
              ((profile['generations'] as Map?)?['wishlist'] as num?)?.toInt(),
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
      recentSearches: items('recentSearches'),
      // Older backends: the newest movies and series rows, merged here.
      releases: json.containsKey('releases')
          ? items('releases')
          : mergeReleases(items('recentMovies'), items('recentSeries')),
      watched: items('watched'),
      // Older backends: favorites (channels) + my list (titles), all available.
      libraryFavorites: library is Map
          ? [
              for (final raw in (library['favorites'] as List? ?? const []))
                if (raw is Map && raw['id'] is String)
                  Entry(raw['id'] as String, Map<String, dynamic>.from(raw)),
            ]
          : [...items('favorites'), ...items('myList')],
      wishlist: library is Map
          ? [
              for (final raw in (library['wishlist'] as List? ?? const []))
                if (raw is Map && raw['id'] is String)
                  Entry(raw['id'] as String, Map<String, dynamic>.from(raw)),
            ]
          : const [],
      saved: {
        LibraryList.favorites: json['saved'] is Map
            ? keys('favorites')
            : {
                for (final id in (json['favoriteIds'] as List? ?? const []))
                  if (id is String) id,
              },
        LibraryList.wishlist: keys('wishlist'),
      },
    );
  }

  final HomeProfile? profile;
  final Set<String> favoriteIds;
  final List<Entry> favorites, continueWatching, myList;
  final List<Entry> recentMovies, recentSeries;
  final List<Entry> recentSearches;

  /// Lançamentos (newest movies and series by provider date, never adult)
  /// and Assistidos (history, one entry per title).
  final List<Entry> releases, watched;

  /// Library rows (catalog items and editorial titles, `available` flag).
  final List<Entry> libraryFavorites, wishlist;
  final Map<LibraryList, Set<String>> saved;

  bool get isEmpty =>
      libraryFavorites.isEmpty &&
      wishlist.isEmpty &&
      favorites.isEmpty &&
      continueWatching.isEmpty &&
      myList.isEmpty &&
      recentMovies.isEmpty &&
      recentSeries.isEmpty &&
      recentSearches.isEmpty &&
      releases.isEmpty &&
      watched.isEmpty;

  /// Items of one section (the Home shows 10; "Ver tudo" the whole list).
  /// "Meu iPlex" rules (same as the TV), also applied here so they hold
  /// with older backends: never adult content; Continuar assistindo,
  /// Lançamentos and Assistidos only movies and series, one entry per title.
  List<Entry> section(HomeSection section) => switch (section) {
    HomeSection.favorites => meuIplex(libraryFavorites, channels: true),
    HomeSection.continueWatching => meuIplex(continueWatching),
    HomeSection.wishlist => meuIplex(wishlist),
    HomeSection.releases => meuIplex(releases),
    HomeSection.watched => meuIplex(watched),
    HomeSection.recentMovies => recentMovies,
    HomeSection.recentSeries => recentSeries,
    HomeSection.recentSearches => recentSearches,
  };

  bool isFavorite(Entry item) => isSaved(LibraryList.favorites, item);

  bool isSaved(LibraryList list, Entry item) =>
      item.libraryKeys.any((saved[list] ?? const {}).contains);
}

/// Items of a "Meu iPlex" row: no adult content, one entry per title and,
/// unless [channels], movies and series only.
List<Entry> meuIplex(List<Entry> items, {bool channels = false}) {
  final seen = <String>{};
  return [
    for (final item in items)
      if ((channels || !item.isChannel) &&
          !isAdultEntry(item) &&
          seen.add(item.id))
        item,
  ];
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};
String _fold(Object? value) => [
  for (final c in '${value ?? ''}'.toLowerCase().trim().split(''))
    _accents[c] ?? c,
].join();
final _adult = RegExp(
  r'(^|[^a-z0-9])(xxx|adult[oa]?s?|adults?|porn\w*|erotic\w*|erotik\w*|hentai|playboy|sexy|18\s*\+|\+\s*18|for adults)([^a-z0-9]|$)',
);
final _adultRating = RegExp(
  r'^(18|18\+|r18|nc-17|nc17|x|xxx|pegi 18|pegi18|fsk 18|fsk18)$',
);

/// Adult content: same signals as the backend (`isAdultContent`): provider
/// flag, title/category words or an 18 rating.
bool isAdultEntry(Entry item) {
  if (item.data['isAdult'] == true) return true;
  if (_adult.hasMatch(_fold(item.data['title'])) ||
      _adult.hasMatch(_fold(item.data['category']))) {
    return true;
  }
  final rating = _fold(item.data['ageRating'])
      .replaceFirst(
        RegExp(r'^(rated|classificacao|clasificacion|age|idade|edad)[:\s]*'),
        '',
      )
      .replaceFirst(RegExp(r'\s+anos?$|\s+years?$'), '')
      .trim();
  return _adultRating.hasMatch(rating);
}

/// Lançamentos from the separate rows of older backends: the
/// [releasesPerKind] newest of each kind, newest first by provider date.
List<Entry> mergeReleases(List<Entry> movies, List<Entry> series) {
  num added(Entry e) => e.data['addedAt'] is num ? e.data['addedAt'] as num : 0;
  Iterable<Entry> newest(List<Entry> items) =>
      items.where((e) => !isAdultEntry(e)).take(releasesPerKind);
  return [...newest(movies), ...newest(series)]
    ..sort((a, b) => added(b).compareTo(added(a)));
}

/// Sources the Home can show: published catalog, and unlocked when protected.
List<Entry> readySources(List<Entry> sources, Set<String> unlocked) => sources
    .where(
      (entry) =>
          entry.text('version').isNotEmpty &&
          (entry.data['isProtected'] != true || unlocked.contains(entry.id)),
    )
    .toList();
