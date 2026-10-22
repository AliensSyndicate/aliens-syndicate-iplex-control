import 'dart:async';

import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/public_identity.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/profile_manage_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements ManagerRepository {
  _Repo(this.profile, {this.admin = true, this.library = _library});
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
    theme: AppTokens.theme,
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
  await _tap(tester, finder);
}

void main() {
  Finder inSection(String section, Finder f) => find.descendant(
    of: find.byKey(ValueKey('library-$section')),
    matching: f,
  );

  testWidgets(
    'content sections: Busca tabs, images, progress, episodes and real data only',
    (tester) async {
      final repo = _Repo(Map.of(_regular));
      await _open(tester, repo);
      expect(repo.calls.first.$2, {'profileId': 'p1'});
      // Renamed: "Continuar assistindo" (no "na TV").
      expect(find.text('Continuar assistindo'), findsOneWidget);
      expect(find.textContaining('na TV'), findsNothing);
      for (final section in [
        'continueWatching',
        'favorites',
        'wishlist',
        'watched',
      ]) {
        final tabs = find.byKey(ValueKey('library-$section-tabs'));
        expect(tabs, findsOneWidget);
        expect(tester.widget(tabs), isA<AppTabs<String>>());
        for (final t in ['Ao vivo', 'Filmes', 'Séries']) {
          expect(
            find.descendant(of: tabs, matching: find.text(t)),
            findsOneWidget,
          );
        }
      }
      // Continuar assistindo opens on the first kind with content (Ao vivo):
      // the channel, no invented duration.
      expect(
        inSection(
          'continueWatching',
          find.byKey(const ValueKey('home-card-c1')),
        ),
        findsOneWidget,
      );
      expect(
        inSection('continueWatching', find.textContaining('restantes')),
        findsNothing,
      );
      await _tap(tester, inSection('continueWatching', find.text('Filmes')));
      expect(
        inSection(
          'continueWatching',
          find.byKey(const ValueKey('home-card-m1')),
        ),
        findsOneWidget,
      );
      expect(
        inSection('continueWatching', find.text('70 min restantes')),
        findsOneWidget,
      );
      expect(
        inSection('continueWatching', find.byType(AppProgressBar)),
        findsOneWidget,
      );
      // Favoritos by kind; titles out of the IPTV are kept.
      expect(
        inSection('favorites', find.byKey(const ValueKey('home-card-c2'))),
        findsOneWidget,
      );
      await _tap(tester, inSection('favorites', find.text('Filmes')));
      expect(
        inSection('favorites', find.text('Filme Favorito')),
        findsOneWidget,
      );
      expect(inSection('favorites', find.text('Fora do IPTV')), findsOneWidget);
      expect(inSection('favorites', find.text('Canal Esportes')), findsNothing);
      await _tap(tester, inSection('favorites', find.text('Séries')));
      expect(
        inSection('favorites', find.text('Série Favorita')),
        findsOneWidget,
      );
      // Lista de desejos: same layout; empty kinds say so.
      expect(inSection('wishlist', find.text('Desejo')), findsOneWidget);
      await _tap(tester, inSection('wishlist', find.text('Ao vivo')));
      expect(
        inSection(
          'wishlist',
          find.byKey(const ValueKey('library-wishlist-empty')),
        ),
        findsOneWidget,
      );
      // Assistidos: date of the playback.
      expect(inSection('watched', find.text('Já Visto')), findsOneWidget);
      expect(inSection('watched', find.textContaining('às')), findsOneWidget);
      // No clear of its own for the wishlist (shared favorites generation).
      expect(find.byKey(const ValueKey('clear-wishlist')), findsNothing);
    },
  );

  testWidgets('cancelling a clear changes nothing', (tester) async {
    final repo = _Repo(Map.of(_regular));
    await _open(tester, repo);
    await _tap(tester, find.byKey(const ValueKey('clear-favorites')));
    expect(find.text('Limpar favoritos?'), findsOneWidget);
    expect(
      find.textContaining('Todos os favoritos e a lista de desejos de João'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Cancelar'));
    expect(repo.actions.where((c) => c.$1 == 'clearProfileData'), isEmpty);
  });

  testWidgets(
    'each clear: text only, confirmation, its own category, no double send, closes after backend success',
    (tester) async {
      final repo = _Repo(Map.of(_regular));
      await _open(tester, repo);
      for (final (key, category, title, confirm) in [
        (
          'clear-favorites',
          'favorites',
          'Limpar favoritos?',
          'Limpar favoritos',
        ),
        ('clear-watched', 'watched', 'Limpar assistidos?', 'Limpar histórico'),
        (
          'clear-continueWatching',
          'progress',
          'Limpar Continuar assistindo?',
          'Limpar Continuar assistindo',
        ),
      ]) {
        final button = tester.widget<AppButton>(find.byKey(ValueKey(key)));
        expect(
          [button.icon, button.leading],
          [null, null],
          reason: 'text only',
        );
        repo.calls.clear();
        repo.gate = Completer<void>();
        await _tap(tester, find.byKey(ValueKey(key)));
        expect(find.text(title), findsOneWidget);
        final confirmButton = find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text(confirm),
        );
        await tester.tap(confirmButton);
        await tester.pump();
        await tester.tap(confirmButton, warnIfMissed: false);
        await tester.pump();
        expect(repo.actions.length, 1);
        expect(repo.actions.single.$2['category'], category);
        expect(
          find.text(title),
          findsOneWidget,
          reason: 'stays open until the backend confirms',
        );
        repo.gate!.complete();
        repo.gate = null;
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing);
        expect(find.text('Dados excluídos.'), findsOneWidget);
        await _tap(tester, find.text('Fechar'));
      }
    },
  );

  testWidgets(
    'a failed clear keeps the sheet open with the error and allows retry',
    (tester) async {
      final repo = _Repo(Map.of(_regular))
        ..failure = const AppFailure('clear-failed');
      await _open(tester, repo);
      await _tap(tester, find.byKey(const ValueKey('clear-watched')));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text('Limpar histórico'),
        ),
      );
      expect(find.text('Limpar assistidos?'), findsOneWidget);
      expect(find.byKey(const Key('confirm-and-run-error')), findsOneWidget);
      expect(find.text('Dados excluídos.'), findsNothing);
    },
  );

  testWidgets(
    'guest: toggle and permissions, no content; kids: mandatory restriction, no adult switch',
    (tester) async {
      final guest = _Repo({
        'name': 'Visitante',
        'type': 'guest',
        'enabled': true,
      });
      await _open(tester, guest);
      expect(find.text('Visitante'), findsWidgets);
      expect(find.byKey(const Key('guest-enabled')), findsOneWidget);
      expect(find.byKey(const Key('limits-adult')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-favorites')), findsNothing);
      expect(guest.calls.where((c) => c.$1 == 'readProfileLibrary'), isEmpty);
      await _tap(tester, find.byKey(const Key('guest-enabled')));
      expect(guest.actions.single.$1, 'setGuestEnabled');
      expect(guest.actions.single.$2['enabled'], false);

      final kids = _Repo({
        'name': 'Lia',
        'type': 'kids',
        'linkedUid': null,
        'permissions': {'allSpaces': false, 'spaces': []},
      });
      await tester.pumpWidget(const SizedBox());
      await _open(tester, kids);
      expect(find.text('Infantil'), findsOneWidget);
      expect(
        find.textContaining('Perfis infantis recebem somente'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('limits-adult')), findsNothing);
      await _tap(tester, find.byKey(const Key('space-s1-movie')));
      expect(kids.actions.single.$1, 'setProfilePermissions');
      expect(kids.actions.single.$2['spaces'], ['s1:movie']);
    },
  );

  testWidgets(
    'administrator: adult content limit and sections; no PIN of another member',
    (tester) async {
      final repo = _Repo(Map.of(_regular))
        ..members = [
          Entry('m9', const {'name': 'João', 'lastActiveAt': 1767349800000}),
        ];
      repo.profile = {...repo.profile, 'linkedUid': 'm9'};
      await _open(tester, repo);
      // Header: last sync of the linked account, only here.
      expect(find.byKey(const Key('member-last-sync')), findsOneWidget);
      expect(find.textContaining('Última sincronização:'), findsOneWidget);
      expect(find.text('Membro'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('limits-adult')));
      expect(repo.actions.single.$1, 'setProfilePermissions');
      expect(repo.actions.single.$2['adult'], false);
      expect(find.byKey(const Key('personal-pin')), findsNothing);
      expect(find.byKey(const Key('remove-from-family')), findsOneWidget);
    },
  );

  testWidgets(
    'member on its own profile: preferences within the limits, its own PIN, no administration',
    (tester) async {
      final repo = _Repo({
        'name': 'Rui',
        'type': 'regular',
        'linkedUid': 'u',
        'permissions': {'allSpaces': true, 'spaces': [], 'adult': false},
      }, admin: false);
      await _open(tester, repo);
      expect(find.byKey(const Key('limits-adult')), findsNothing);
      expect(find.byKey(const ValueKey('clear-favorites')), findsNothing);
      expect(find.byKey(const Key('remove-profile')), findsNothing);
      // Adult content not allowed by the administrator: cannot be turned on.
      final adult = tester.widget<NeumorphicSwitchTile>(
        find.byKey(const Key('preferences-adult')),
      );
      expect([adult.value, adult.disabled], [false, true]);
      expect(find.text('Não permitido pelo administrador'), findsOneWidget);
      // Narrowing the sections: only its own preferences.
      await _tap(tester, find.byKey(const Key('pref-s1-channel')));
      expect(repo.actions.single.$1, 'setProfilePreferences');
      expect(repo.actions.single.$2['spaces'], ['s1:movie', 's1:series']);
      // Personal PIN: only here, set by the account itself.
      repo.calls.clear();
      await _tap(tester, find.byKey(const Key('personal-pin-set')));
      await tester.enterText(find.byKey(const Key('personal-pin-new')), '1234');
      await tester.enterText(
        find.byKey(const Key('personal-pin-confirm')),
        '1234',
      );
      await _tap(tester, find.byKey(const Key('personal-pin-save')));
      expect(repo.actions.single.$1, 'setPersonalPin');
      expect(repo.actions.single.$2, {'pin': '1234', 'confirmPin': '1234'});
      expect(find.byKey(const Key('leave-family')), findsOneWidget);
    },
  );

  testWidgets('changing an existing PIN asks for the current one', (
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
      expect(find.text('Sem conta vinculada'), findsOneWidget);
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
}
