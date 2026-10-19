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
  _Repo(this.profile);
  Map<String, dynamic> profile;
  final calls = <(String, Map<String, dynamic>)>[];
  Completer<void>? gate;
  Object? failure;
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
  Stream<Family?> watchFamily(String id) =>
      Stream.value(Family(id: id, adminId: 'u', members: const {'u': 'admin'}));
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      Stream.value(
        collection == 'sources'
            ? [
                Entry('s1', const {'name': 'Lista'}),
              ]
            : const [],
      );
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      Stream.value(Entry('p1', profile));
  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add((action, payload));
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
  tester.view.physicalSize = const Size(1170, 4000);
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

void main() {
  testWidgets('cancelling a clear changes nothing', (tester) async {
    final repo = _Repo(Map.of(_regular));
    await _open(tester, repo);
    await tester.tap(find.byKey(const Key('clear-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('Limpar favoritos?'), findsOneWidget);
    expect(
      find.textContaining(
        'Todos os favoritos de João serão excluídos permanentemente',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.$1 == 'clearProfileData'), isEmpty);
  });

  testWidgets(
    'each clear sends only its own category, blocks repeated taps and closes after backend success',
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
        ('clear-watched', 'watched', 'Limpar assistidos?', 'Limpar assistidos'),
        (
          'clear-progress',
          'progress',
          'Limpar Continuar assistindo?',
          'Limpar progresso',
        ),
      ]) {
        repo.calls.clear();
        repo.gate = Completer<void>();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        final button = find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text(confirm),
        );
        await tester.tap(button);
        await tester.pump();
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();
        expect(repo.calls.length, 1);
        expect(repo.calls.single.$2['category'], category);
        expect(
          find.text(title),
          findsOneWidget,
          reason: 'stays open until the backend confirms',
        );
        repo.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing);
        expect(find.text('Dados excluídos.'), findsOneWidget);
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'a failed clear keeps the sheet open with the error and allows retry',
    (tester) async {
      final repo = _Repo(Map.of(_regular))
        ..failure = const AppFailure('clear-failed');
      await _open(tester, repo);
      await tester.tap(find.byKey(const Key('clear-watched')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text('Limpar assistidos'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Limpar assistidos?'), findsOneWidget);
      expect(find.byKey(const Key('confirm-and-run-error')), findsOneWidget);
      expect(find.text('Dados excluídos.'), findsNothing);
    },
  );

  testWidgets(
    'guest shows the toggle and no data actions; kids shows the mandatory restriction',
    (tester) async {
      final guest = _Repo({
        'name': 'Visitante',
        'type': 'guest',
        'enabled': true,
      });
      await _open(tester, guest);
      expect(find.byKey(const Key('guest-enabled')), findsOneWidget);
      expect(find.byKey(const Key('clear-favorites')), findsNothing);
      await tester.tap(find.byKey(const Key('guest-enabled')));
      await tester.pumpAndSettle();
      expect(guest.calls.single.$1, 'setGuestEnabled');
      expect(guest.calls.single.$2['enabled'], false);

      final kids = _Repo({
        'name': 'Lia',
        'type': 'kids',
        'linkedUid': null,
        'permissions': {'allSpaces': false, 'spaces': []},
      });
      await tester.pumpWidget(const SizedBox());
      await _open(tester, kids);
      expect(
        find.textContaining('Perfis infantis recebem somente'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('space-s1-movie')));
      await tester.pumpAndSettle();
      expect(kids.calls.single.$1, 'setProfilePermissions');
      expect(kids.calls.single.$2['spaces'], ['s1:movie']);
    },
  );

  testWidgets(
    'link code sheet shows the single-use code for an unlinked profile',
    (tester) async {
      final repo = _Repo(Map.of(_regular));
      await _open(tester, repo);
      expect(find.text('Sem conta vinculada'), findsOneWidget);
      await tester.tap(find.text('Vincular com conta'));
      await tester.pumpAndSettle();
      expect(repo.calls.single.$1, 'createProfileLinkCode');
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
