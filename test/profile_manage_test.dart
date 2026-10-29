import 'dart:async';
import 'dart:io';

import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/public_identity.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/profile_manage_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/profile_library.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_network_image.dart';
import 'widget_test.dart' as fixtures;

class _Repo implements ManagerRepository {
  _Repo(this.profile, {this.admin = true}) : library = _library;
  Map<String, dynamic> profile;
  final bool admin;
  final Map<String, dynamic> library;
  final calls = <(String, Map<String, dynamic>)>[];
  List<Entry> members = const [];
  Completer<void>? gate;
  Object? failure;

  /// Mutations only (reads of the library are not actions of the user).
  Iterable<(String, Map<String, dynamic>)> get actions =>
      calls.where((c) => c.$1 != 'readProfileLibrary');
  @override
  bool get configured => true;
  @override
  Stream<String?> authChanges() => Stream.value('u');
  @override
  Future<void> initializeAccount(String uid) async {}
  @override
  Stream<Account?> watchAccount(String uid) => Stream.value(
    Account(uid: uid, name: 'Admin', email: 'a@example.invalid', familyId: 'f'),
  );
  @override
  Stream<Family?> watchFamily(String id) => Stream.value(
    admin
        ? Family(id: id, adminId: 'u', members: const {'u': 'admin'})
        : Family(
            id: id,
            adminId: 'boss',
            members: const {'boss': 'admin', 'u': 'member'},
          ),
  );
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      Stream.value(switch (collection) {
        'sources' => [
          Entry('s1', const {'name': 'Lista'}),
        ],
        'members' => members,
        _ => const [],
      });
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      Stream.value(Entry('p1', profile));
  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add((action, payload));
    if (action == 'readProfileLibrary') return library;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return {'code': 'ABCD2345', 'expiresAt': 0};
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

const _library = <String, dynamic>{
  'continueWatching': [
    {
      'id': 'm1',
      'name': 'Missão Fictícia',
      'kind': 'movie',
      'sourceId': 's1',
      'progress': {'position': 1800, 'duration': 6000, 'updatedAt': 1},
    },
    {
      'id': 'c1',
      'name': 'Canal Notícias',
      'kind': 'channel',
      'sourceId': 's1',
      'progress': {'position': 60, 'duration': 0, 'updatedAt': 1},
    },
  ],
  'favorites': [
    {'id': 'c2', 'name': 'Canal Esportes', 'kind': 'channel', 'sourceId': 's1'},
    {'id': 'm2', 'name': 'Filme Favorito', 'kind': 'movie', 'sourceId': 's1'},
    {'id': 'sr1', 'name': 'Série Favorita', 'kind': 'series', 'sourceId': 's1'},
    // Saved title no catalog offers: kept (editorial).
    {
      'id': 'tmdb-doc',
      'title': 'Fora do IPTV',
      'kind': 'movie',
      'tmdbId': 603,
      'available': false,
    },
  ],
  'wishlist': [
    {'id': 'm3', 'name': 'Desejo', 'kind': 'movie', 'sourceId': 's1'},
  ],
  'watched': [
    {
      'id': 'm4',
      'name': 'Já Visto',
      'kind': 'movie',
      'sourceId': 's1',
      'watchedAt': 1767349800000,
    },
  ],
};

Widget _host(_Repo repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pt', 'BR'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ProfileManagePage(id: 'p1'),
  ),
);

Future<void> _open(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(1170, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(repo));
  await tester.pumpAndSettle();
}

const _regular = {
  'name': 'João',
  'type': 'regular',
  'linkedUid': null,
  'permissions': {'allSpaces': true, 'spaces': []},
};

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final type in ['regular', 'kids']) {
    testWidgets(
      'administrator can reclassify $type without recreating the profile',
      (tester) async {
        final repo = _Repo({..._regular, 'type': type});
        await _open(tester, repo);
        final toggle = find.byKey(const Key('kids-account-toggle'));
        expect(
          tester.widget<NeumorphicSwitchTile>(toggle).value,
          type == 'kids',
        );
        await _tap(tester, toggle);
        expect(repo.actions.single.$1, 'saveProfile');
        expect(repo.actions.single.$2, {
          'id': 'p1',
          'name': 'João',
          'type': type == 'kids' ? 'regular' : 'kids',
        });
      },
    );
  }
  testWidgets('member sees its classification but cannot change it', (
    tester,
  ) async {
    final repo = _Repo({
      ..._regular,
      'type': 'kids',
      'linkedUid': 'u',
    }, admin: false);
    await _open(tester, repo);
    final toggle = find.byKey(const Key('kids-account-toggle'));
    expect(tester.widget<NeumorphicSwitchTile>(toggle).disabled, isTrue);
  });

  testWidgets('header: no account link text; last sync inside a card', (
    tester,
  ) async {
    final repo = _Repo({..._regular, 'linkedUid': 'm1'})
      ..members = [
        Entry('m1', const {'name': 'João', 'lastActiveAt': 1767349800000}),
      ];
    await _open(tester, repo);
    expect(find.byKey(const Key('profile-link-status')), findsNothing);
    expect(find.text('Conta vinculada'), findsNothing);
    expect(find.text('Sem conta vinculada'), findsNothing);
    final sync = find.byKey(const Key('member-last-sync'));
    expect(sync, findsOneWidget);
    expect(tester.widget<EntryTile>(sync).title, 'Última sincronização');
    expect(find.text('Administrador acessa todos os espaços'), findsNothing);
    expect(find.byKey(const Key('parental-control')), findsNothing);
  });

  testWidgets('one card per list, in order, with only its name and count', (
    tester,
  ) async {
    final repo = _Repo({..._regular, 'linkedUid': 'u'});
    await _open(tester, repo);
    final cards = [
      for (final k in ['continueWatching', 'favorites', 'wishlist', 'watched'])
        find.byKey(ValueKey('library-$k')),
    ];
    final tops = [for (final c in cards) tester.getTopLeft(c).dy];
    expect(tops, [...tops]..sort(), reason: 'mandatory order');
    expect(
      [for (final c in cards) tester.widget<EntryTile>(c).title],
      ['Continuar assistindo', 'Favoritos', 'Lista de desejos', 'Assistidos'],
    );
    for (final (k, n) in [
      ('continueWatching', '2'),
      ('favorites', '4'),
      ('wishlist', '1'),
      ('watched', '1'),
    ]) {
      expect(
        tester.widget<Text>(find.byKey(ValueKey('library-$k-count'))).data,
        n,
      );
    }
    // The titles themselves only appear on the list page.
    expect(find.text('Missão Fictícia'), findsNothing);
  });

  testWidgets('order: lists, then the PIN card, then Conteúdo', (tester) async {
    final repo = _Repo({..._regular, 'linkedUid': 'u'});
    await _open(tester, repo);
    double y(Finder f) => tester.getTopLeft(f).dy;
    final watched = y(find.byKey(const ValueKey('library-watched')));
    final pin = y(find.byKey(const Key('personal-pin')));
    final content = y(find.text('Conteúdo'));
    final kids = y(find.byKey(const Key('kids-account-toggle')));
    final channel = y(find.byKey(const Key('content-channel')));
    expect(watched < pin && pin < content && content < kids, isTrue);
    expect(kids < channel, isTrue, reason: 'Conta infantil comes first');
    expect(find.byKey(const Key('personal-pin-set')), findsNothing);
  });

  testWidgets('administrator sets the types and adult content of a member', (
    tester,
  ) async {
    final repo = _Repo(Map.of(_regular));
    await _open(tester, repo);
    for (final k in ['channel', 'movie', 'series', 'adult']) {
      final t = tester.widget<NeumorphicSwitchTile>(
        find.byKey(Key('content-$k')),
      );
      expect(t.value, isTrue, reason: k);
      expect(t.disabled, isFalse, reason: k);
    }
    await _tap(tester, find.byKey(const Key('content-movie')));
    expect(repo.actions.last.$1, 'setProfilePermissions');
    expect(repo.actions.last.$2, {
      'profileId': 'p1',
      'kinds': ['channel', 'series'],
    });
    await _tap(tester, find.byKey(const Key('content-adult')));
    expect(repo.actions.last.$1, 'setProfilePermissions');
    expect(repo.actions.last.$2, {'profileId': 'p1', 'adult': false});
    // No PIN card for another member's profile.
    expect(find.byKey(const Key('personal-pin')), findsNothing);
  });

  testWidgets(
    'member on its own profile: narrows its types, never the adult content',
    (tester) async {
      final repo = _Repo({
        'name': 'Rui',
        'type': 'regular',
        'linkedUid': 'u',
        'permissions': {
          'allSpaces': true,
          'spaces': [],
          'kinds': ['channel', 'movie'],
        },
      }, admin: false);
      await _open(tester, repo);
      NeumorphicSwitchTile tile(String k) =>
          tester.widget(find.byKey(Key('content-$k')));
      expect(tile('series').value, isFalse);
      expect(tile('series').disabled, isTrue);
      expect(tile('series').subtitle, 'Não permitido pelo administrador');
      expect(tile('adult').disabled, isTrue);
      await _tap(tester, find.byKey(const Key('content-channel')));
      expect(repo.actions.last.$1, 'setProfilePreferences');
      expect(repo.actions.last.$2, {
        'kinds': ['movie'],
      });
      // Its own lists and PIN; no administration; can leave.
      expect(find.byKey(const ValueKey('library-favorites')), findsOneWidget);
      expect(find.byKey(const Key('personal-pin')), findsOneWidget);
      expect(find.byKey(const Key('remove-profile')), findsNothing);
      expect(find.byKey(const Key('leave-family')), findsOneWidget);
    },
  );

  testWidgets('member viewing another member: everything read-only', (
    tester,
  ) async {
    final repo = _Repo({
      ..._regular,
      'linkedUid': 'someone-else',
    }, admin: false);
    await _open(tester, repo);
    for (final k in ['channel', 'movie', 'series', 'adult']) {
      expect(
        tester
            .widget<NeumorphicSwitchTile>(find.byKey(Key('content-$k')))
            .disabled,
        isTrue,
        reason: k,
      );
    }
    expect(
      tester
          .widget<NeumorphicSwitchTile>(
            find.byKey(const Key('kids-account-toggle')),
          )
          .disabled,
      isTrue,
    );
    expect(find.byKey(const ValueKey('library-favorites')), findsNothing);
    expect(find.byKey(const Key('personal-pin')), findsNothing);
    expect(find.byKey(const Key('remove-profile')), findsNothing);
    expect(find.byKey(const Key('leave-family')), findsNothing);
    expect(repo.actions, isEmpty);
  });

  testWidgets('kids profile never shows the adult content switch', (
    tester,
  ) async {
    final repo = _Repo({..._regular, 'type': 'kids'});
    await _open(tester, repo);
    expect(find.byKey(const Key('content-adult')), findsNothing);
    expect(find.byKey(const Key('content-channel')), findsOneWidget);
  });

  testWidgets('guest: on/off switch and content, no lists nor kids switch', (
    tester,
  ) async {
    final repo = _Repo({
      'name': 'Visitante',
      'type': 'guest',
      'enabled': true,
      'permissions': {'allSpaces': true, 'spaces': []},
    });
    await _open(tester, repo);
    expect(find.byKey(const Key('guest-enabled')), findsOneWidget);
    expect(find.byKey(const Key('kids-account-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('library-favorites')), findsNothing);
    expect(find.byKey(const Key('content-adult')), findsOneWidget);
  });

  testWidgets('administrator on its own profile: own types and adult content', (
    tester,
  ) async {
    final repo = _Repo({'name': 'Admin', 'type': 'admin', 'linkedUid': 'u'});
    await _open(tester, repo);
    expect(find.byKey(const Key('kids-account-toggle')), findsNothing);
    await _tap(tester, find.byKey(const Key('content-series')));
    expect(repo.actions.last.$1, 'setProfilePreferences');
    expect(repo.actions.last.$2, {
      'kinds': ['channel', 'movie'],
    });
    await _tap(tester, find.byKey(const Key('content-adult')));
    expect(repo.actions.last.$1, 'setProfilePermissions');
    expect(repo.actions.last.$2, {'profileId': 'p1', 'adult': false});
    expect(find.byKey(const Key('personal-pin')), findsOneWidget);
  });

  testWidgets('PIN card: off opens the form to turn it on', (tester) async {
    final repo = _Repo({..._regular, 'linkedUid': 'u'}, admin: false);
    await _open(tester, repo);
    expect(find.text('Desativado'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('personal-pin')));
    expect(find.byKey(const Key('personal-pin-current')), findsNothing);
    await tester.enterText(find.byKey(const Key('personal-pin-new')), '2468');
    await tester.enterText(
      find.byKey(const Key('personal-pin-confirm')),
      '2468',
    );
    await _tap(tester, find.byKey(const Key('personal-pin-save')));
    expect(repo.actions.single.$1, 'setPersonalPin');
    expect(repo.actions.single.$2, {'pin': '2468', 'confirmPin': '2468'});
  });

  testWidgets('PIN card: on offers change or turn off; both ask the current', (
    tester,
  ) async {
    final repo = _Repo({
      'name': 'Rui',
      'type': 'regular',
      'linkedUid': 'u',
      'personalPin': {'configured': true},
    }, admin: false);
    await _open(tester, repo);
    expect(find.text('Ativado'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('personal-pin')));
    expect(find.byKey(const Key('personal-pin-change')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('personal-pin-remove')));
    await tester.enterText(
      find.byKey(const Key('personal-pin-current')),
      '1234',
    );
    await _tap(tester, find.byKey(const Key('personal-pin-save')));
    expect(repo.actions.single.$1, 'clearPersonalPin');
    expect(repo.actions.single.$2, {'currentPin': '1234'});
  });

  testWidgets(
    'link code sheet shows the single-use code for an unlinked profile',
    (tester) async {
      final repo = _Repo(Map.of(_regular));
      await _open(tester, repo);
      await _tap(tester, find.text('Vincular com conta'));
      expect(repo.actions.single.$1, 'createProfileLinkCode');
      expect(find.byKey(const Key('profile-link-code')), findsOneWidget);
      expect(parseProfileLinkCode(profileLinkQr('ABCD2345')), 'ABCD2345');
      expect(parseProfileLinkCode('iplex://pair?token=${'a' * 64}'), isNull);
      expect(
        parseProfileLinkCode('iplex://user?v=1&code=K7M4P9R2T6X8'),
        isNull,
      );
    },
  );

  group('list page', () {
    Future<void> openList(
      WidgetTester tester,
      _Repo repo,
      LibraryKind kind,
    ) async {
      tester.view.physicalSize = const Size(1170, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      HttpOverrides.global = FakeImageHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            locale: const Locale('pt', 'BR'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProfileLibraryPage(profileId: 'p1', kind: kind),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('titles as a grid with the content type tabs', (tester) async {
      final repo = _Repo({..._regular, 'linkedUid': 'u'});
      await openList(tester, repo, LibraryKind.favorites);
      expect(find.text('Favoritos'), findsOneWidget);
      expect(find.byKey(const Key('library-grid')), findsOneWidget);
      // First type with content: channels.
      expect(find.text('Canal Esportes'), findsOneWidget);
      await _tap(tester, find.text('Filmes'));
      expect(find.text('Filme Favorito'), findsOneWidget);
      expect(find.text('Fora do IPTV'), findsOneWidget);
      await _tap(tester, find.text('Séries'));
      expect(find.text('Série Favorita'), findsOneWidget);
    });

    for (final (kind, category, title) in [
      (
        LibraryKind.continueWatching,
        'progress',
        'Limpar Continuar assistindo?',
      ),
      (LibraryKind.favorites, 'favorites', 'Limpar favoritos?'),
      (LibraryKind.wishlist, 'wishlist', 'Limpar lista de desejos?'),
      (LibraryKind.watched, 'watched', 'Limpar assistidos?'),
    ]) {
      testWidgets('${kind.name}: app bar clear with confirmation', (
        tester,
      ) async {
        final repo = _Repo({..._regular, 'linkedUid': 'u'})
          ..gate = Completer<void>();
        await openList(tester, repo, kind);
        await _tap(tester, find.byKey(const Key('library-clear')));
        expect(find.text(title), findsOneWidget);
        final confirm = find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.byType(AppButton),
        );
        await tester.tap(confirm.first);
        await tester.pump();
        await tester.tap(confirm.first, warnIfMissed: false);
        await tester.pump();
        expect(repo.actions.length, 1, reason: 'no double send');
        expect(repo.actions.single.$1, 'clearProfileData');
        expect(repo.actions.single.$2['category'], category);
        expect(find.text(title), findsOneWidget, reason: 'waits the backend');
        repo.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Dados excluídos.'), findsOneWidget);
      });
    }

    testWidgets('cancelling a clear changes nothing', (tester) async {
      final repo = _Repo({..._regular, 'linkedUid': 'u'});
      await openList(tester, repo, LibraryKind.watched);
      await _tap(tester, find.byKey(const Key('library-clear')));
      await _tap(tester, find.text('Cancelar'));
      expect(repo.actions, isEmpty);
    });

    testWidgets('a failed clear keeps the sheet open with the error', (
      tester,
    ) async {
      final repo = _Repo({..._regular, 'linkedUid': 'u'})
        ..failure = const AppFailure('clear-in-progress');
      await openList(tester, repo, LibraryKind.favorites);
      await _tap(tester, find.byKey(const Key('library-clear')));
      final confirm = find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.byType(AppButton),
      );
      await _tap(tester, confirm.first);
      expect(find.byKey(const Key('confirm-and-run-error')), findsOneWidget);
      expect(find.text('Limpar favoritos?'), findsOneWidget);
    });

    testWidgets('another member’s list: no clear button', (tester) async {
      final repo = _Repo({
        ..._regular,
        'linkedUid': 'someone-else',
      }, admin: false);
      await openList(tester, repo, LibraryKind.favorites);
      expect(find.byKey(const Key('library-clear')), findsNothing);
    });
  });

  testWidgets('screenshot: member on its own profile', (tester) async {
    if (!const bool.fromEnvironment('SCREENSHOTS')) return;
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo =
        _Repo({
            'name': 'Rui',
            'type': 'regular',
            'linkedUid': 'u',
            'personalPin': {'configured': true},
            'permissions': {
              'allSpaces': true,
              'spaces': [],
              'kinds': ['channel', 'movie'],
            },
          }, admin: false)
          ..members = [
            Entry('u', const {'name': 'Rui', 'lastActiveAt': 1767349800000}),
          ];
    await tester.pumpWidget(
      RepaintBoundary(key: const Key('screen'), child: _host(repo)),
    );
    await tester.pumpAndSettle();
    await fixtures.screenshot(tester, 'member-own');
  });
}
