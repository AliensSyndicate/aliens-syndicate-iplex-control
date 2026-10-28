import 'package:flutter_test/flutter_test.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_data.dart';

Map<String, dynamic> title(String id, String kind, int addedAt) => {
  'id': id,
  'kind': kind,
  'title': id,
  'addedAt': addedAt,
};

void main() {
  test(
    'Lançamentos from an older backend: 5 newest per kind, merged by date',
    () {
      final home = HomeData.fromJson({
        'recentMovies': [
          for (var i = 0; i < 7; i++) title('m$i', 'movie', 100 - i * 2),
        ],
        'recentSeries': [
          for (var i = 0; i < 7; i++) title('s$i', 'series', 99 - i * 2),
        ],
      });
      expect(home.releases.map((e) => e.id), [
        'm0', 's0', 'm1', 's1', 'm2', 's2', 'm3', 's3', 'm4', 's4', //
      ]);
      expect(home.section(HomeSection.releases), home.releases);
    },
  );

  test('Lançamentos and Assistidos as published by the backend', () {
    final home = HomeData.fromJson({
      'releases': [title('r1', 'series', 1)],
      'recentMovies': [title('m1', 'movie', 2)],
      'watched': [title('w1', 'movie', 0)],
    });
    expect(home.releases.map((e) => e.id), ['r1']);
    expect(home.section(HomeSection.watched).map((Entry e) => e.id), ['w1']);
  });

  test('Meu iPlex order', () {
    expect(homeSections, [
      HomeSection.continueWatching,
      HomeSection.favorites,
      HomeSection.wishlist,
      HomeSection.releases,
      HomeSection.watched,
    ]);
  });

  test('Meu iPlex rules hold with older backends: no adult, no channels in Continuar, one per title', () {
    Map<String, dynamic> t(
      String id,
      String kind,
      String name, {
      String? category,
    }) => {'id': id, 'kind': kind, 'title': name, 'category': ?category};
    final home = HomeData.fromJson({
      'continueWatching': [
        t('a', 'movie', 'Masterplan'),
        t('b', 'series', 'Big Bang'),
        t('b', 'series', 'Big Bang'),
        t('c', 'movie', 'FILMES ADULTOS'),
        t('d', 'movie', 'Qualquer', category: 'XXX Hot'),
        t('e', 'channel', 'Canal'),
      ],
      'library': {
        'favorites': [t('e', 'channel', 'Canal'), t('f', 'movie', 'Filme +18')],
        'wishlist': [],
      },
    });
    expect(home.section(HomeSection.continueWatching).map((e) => e.id), [
      'a',
      'b',
    ]);
    expect(home.section(HomeSection.favorites).map((e) => e.id), ['e']);
    expect(
      home.continueWatching.length,
      6,
      reason: 'raw data kept for progress lookups',
    );
  });
}
