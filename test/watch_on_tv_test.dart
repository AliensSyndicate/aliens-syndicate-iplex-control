import 'dart:async';

import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/features/watch_on_tv/watch_on_tv_sheet.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract v1 fake: devices, play request status written by the "backend".
class _Repo implements ManagerRepository {
  _Repo({this.devices = const []});
  final List<Entry> devices;
  final calls = <(String, Map<String, dynamic>)>[];
  final request = StreamController<Entry?>.broadcast();
  Object? failure;
  @override
  bool get configured => true;
  @override
  Stream<String?> authChanges() => Stream.value('u');
  @override
  Future<void> initializeAccount(String uid) async {}
  @override
  Stream<Account?> watchAccount(String uid) => Stream.value(
    Account(uid: uid, name: 'Ana', email: 'a@example.invalid', familyId: 'f'),
  );
  @override
  Stream<Family?> watchFamily(String id) =>
      Stream.value(Family(id: id, adminId: 'u', members: const {'u': 'admin'}));
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      Stream.value(
        collection == 'devices'
            ? devices
            : collection == 'profiles'
            ? [
                Entry('admin', const {'name': 'Ana', 'type': 'admin'}),
                Entry('k', const {'name': 'Lia', 'type': 'kids'}),
              ]
            : const [],
      );
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) {
    calls.add(('watch', {'collection': collection, 'id': id}));
    return request.stream;
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add((action, payload));
    if (failure != null) throw failure!;
    if (action == 'requestPlayback') return {'id': 'pr_1', 'status': 'pending'};
    if (action == 'readSourceSeries') {
      return {
        'details': {
          'episodes': {
            '1': [
              {'id': '902', 'title': 'Segundo', 'season': 1, 'episodeNum': 2},
              {'id': '901', 'title': 'Piloto', 'season': 1, 'episodeNum': 1},
            ],
          },
        },
      };
    }
    return {};
  }

  @override
  Future<CatalogPage> catalog(
    String familyId,
    Entry source,
    String search, {
    Object? cursor,
  }) async => const CatalogPage([], null, false);
  @override
  Future<void> signIn(String provider, {bool reauthenticate = false}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

Widget _host(Widget child, _Repo repo, {bool page = false}) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: page ? child : Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Entry _tv(String id, String name, {bool online = true}) => Entry(id, {
  'name': name,
  'status': 'linked',
  'sessionId': online ? 'lease' : '',
  'onlineUntil': online ? DateTime.now().millisecondsSinceEpoch + 60000 : 0,
});

final _movie = Entry('item-hash', const {
  'title': 'Sintel',
  'kind': 'movie',
  'sourceId': 'src1',
  'providerRef': '1',
});

void main() {
  testWidgets('one TV: sends only stable ids and follows the TV result', (
    tester,
  ) async {
    final repo = _Repo(devices: [_tv('tv1', 'Sala')]);
    await tester.pumpWidget(_host(WatchOnTvSheet(item: _movie), repo));
    await tester.pumpAndSettle();
    expect(find.text('Sala'), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-to-tv')));
    await tester.pump();
    final sent = repo.calls.firstWhere((c) => c.$1 == 'requestPlayback').$2;
    expect(sent['deviceId'], 'tv1');
    expect(sent['sourceId'], 'src1');
    expect(sent['itemId'], 'item-hash');
    expect(sent.containsKey('url'), isFalse);
    expect(
      RegExp(r'^[a-f0-9]{32}$').hasMatch(sent['requestId'] as String),
      isTrue,
    );
    // No pause / seek / stop / volume / navigation: only "watch".
    for (final label in [
      'Pausar',
      'Parar',
      'Volume',
      'Avançar',
      'Retroceder',
    ]) {
      expect(find.text(label), findsNothing);
    }
    await tester.pump();
    expect(
      repo.calls.any(
        (c) =>
            c.$1 == 'watch' &&
            c.$2['collection'] == 'devices/tv1/play_requests' &&
            c.$2['id'] == 'pr_1',
      ),
      isTrue,
    );
    final expires = DateTime.now().millisecondsSinceEpoch + 60000;
    repo.request.add(
      Entry('pr_1', {'status': 'confirming', 'expiresAt': expires}),
    );
    await tester.pump();
    expect(
      find.textContaining('Aguardando confirmação em Sala'),
      findsOneWidget,
    );
    repo.request.add(
      Entry('pr_1', {
        'status': 'started',
        'kind': 'movie',
        'expiresAt': expires,
      }),
    );
    await tester.pump();
    expect(find.text('Reproduzindo em Sala.'), findsOneWidget);
  });

  testWidgets('several TVs: the user picks one; backend errors are specific', (
    tester,
  ) async {
    final repo = _Repo(devices: [_tv('tv1', 'Sala'), _tv('tv2', 'Quarto')])
      ..failure = const AppFailure('content-not-allowed');
    await tester.pumpWidget(_host(WatchOnTvSheet(item: _movie), repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-to-tv')));
    await tester.pump();
    expect(repo.calls.where((c) => c.$1 == 'requestPlayback'), isEmpty);
    await tester.tap(find.byKey(const Key('tv-tv2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-to-tv')));
    await tester.pumpAndSettle();
    expect(repo.calls.last.$2['deviceId'], 'tv2');
    expect(
      find.text('Este título não está disponível para o perfil em uso na TV.'),
      findsOneWidget,
    );
  });

  testWidgets('series: an episode is required and travels by id', (
    tester,
  ) async {
    final repo = _Repo(devices: [_tv('tv1', 'Sala')]);
    final series = Entry('series-hash', const {
      'title': 'Série',
      'kind': 'series',
      'sourceId': 'src1',
      'providerRef': '77',
    });
    await tester.pumpWidget(_host(WatchOnTvSheet(item: series), repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-to-tv')));
    await tester.pump();
    expect(
      find.text('Escolha um episódio para assistir na TV.'),
      findsOneWidget,
    );
    expect(repo.calls.where((c) => c.$1 == 'requestPlayback'), isEmpty);
    await tester.tap(find.byKey(const Key('episode-901')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-to-tv')));
    await tester.pump();
    final sent = repo.calls.firstWhere((c) => c.$1 == 'requestPlayback').$2;
    expect(sent['episodeId'], '901');
    expect(sent['episodeLabel'], 'Temporada 1 E1 · Piloto');
  });

  testWidgets('no linked TV: explains and offers to add one', (tester) async {
    await tester.pumpWidget(_host(WatchOnTvSheet(item: _movie), _Repo()));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma TV vinculada'), findsOneWidget);
  });

  test('status copy covers every backend state', () {
    final now = DateTime.now();
    expect(
      PlayRequestStatus.isFinal(
        Entry('r', {
          'status': 'pending',
          'expiresAt': now.millisecondsSinceEpoch + 10000,
        }),
        now,
      ),
      isFalse,
    );
    expect(
      PlayRequestStatus.isFinal(
        Entry('r', {
          'status': 'pending',
          'expiresAt': now.millisecondsSinceEpoch - 10000,
        }),
        now,
      ),
      isTrue,
    );
    for (final s in [
      'started',
      'declined',
      'failed',
      'expired',
      'superseded',
    ]) {
      expect(PlayRequestStatus.isFinal(Entry('r', {'status': s}), now), isTrue);
    }
    expect(parseEpisodes(null), isEmpty);
    expect(
      parseEpisodes({
        'episodes': {
          '2': [
            {'id': 5, 'episodeNum': '1'},
          ],
          '1': [
            {'id': '1', 'episodeNum': 3},
            {'title': 'sem id'},
          ],
        },
      }).map((e) => '${e.season}:${e.id}'),
      ['1:1', '2:5'],
    );
  });
}
