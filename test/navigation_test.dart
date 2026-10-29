import 'dart:async';

import 'package:aliens_syndicate_iplex_control/app/app.dart';
import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/app/session_loading_page.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/authentication/login_page.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/users_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_form.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

/// Controlled auth/repository boundary; no Firebase calls or production fixtures.
class SessionRepository extends fixtures.TestRepository {
  SessionRepository({
    String? uid,
    this.linked = false,
    this.administrator = true,
    this.waitForAuth = false,
  }) : currentUid = uid;
  String? currentUid;
  bool linked, administrator, waitForAuth;
  bool authFailure = false,
      initializationFailure = false,
      sourcesFailure = false,
      catalogFailure = false;
  Completer<void>? initialization;
  Completer<List<Entry>>? pendingSources;
  Completer<CatalogPage>? pendingCatalog;
  // readHome (Control Home rows): configurable payload, failure and latency.
  Map<String, dynamic> home = {};
  bool homeFailure = false;
  Completer<Map<String, dynamic>>? pendingHome;
  int homeReads = 0;
  final mutationPayloads = <(String, Map<String, dynamic>)>[];
  final authEvents = StreamController<String?>.broadcast(sync: true);
  final accountEvents = StreamController<Account?>.broadcast(sync: true);
  final familyEvents = StreamController<Family?>.broadcast(sync: true);
  final sourcesEvents = StreamController<List<Entry>>.broadcast(sync: true);
  List<Entry> sources = [];

  /// TVs of the family (a TV that plays carries `nowPlaying`).
  List<Entry> devices = [];
  final initialized = <String>[];
  int familyReads = 0, entryReads = 0, authReads = 0, catalogReads = 0;
  Account? get account => currentUid == null
      ? null
      : Account(
          uid: currentUid!,
          name: 'Account',
          familyId: linked ? 'family' : null,
        );
  @override
  Stream<String?> authChanges() async* {
    authReads++;
    if (authFailure) throw const AppFailure('unavailable');
    if (!waitForAuth) yield currentUid;
    yield* authEvents.stream;
  }

  @override
  Future<void> initializeAccount(String uid) async {
    initialized.add(uid);
    if (initializationFailure) throw const AppFailure('unavailable');
    await initialization?.future;
  }

  @override
  Stream<Account?> watchAccount(String uid) async* {
    yield account;
    yield* accountEvents.stream;
  }

  @override
  Stream<Family?> watchFamily(String id) async* {
    familyReads++;
    yield Family(
      id: id,
      adminId: administrator ? currentUid! : 'other',
      name: 'Account',
      individual: true,
      members: {currentUid!: administrator ? 'admin' : 'member'},
    );
    yield* familyEvents.stream;
  }

  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) async* {
    entryReads++;
    if (collection == 'sources') {
      if (sourcesFailure) throw const AppFailure('unavailable');
      yield pendingSources == null ? sources : await pendingSources!.future;
      yield* sourcesEvents.stream;
    } else {
      yield collection == 'devices'
          ? devices
          : collection == 'members'
          ? [
              Entry('u', {
                'name': 'Account',
                'role': administrator ? 'admin' : 'member',
              }),
            ]
          : [];
    }
  }

  @override
  Future<CatalogPage> catalog(
    String familyId,
    Entry source,
    String search, {
    Object? cursor,
  }) async {
    catalogReads++;
    if (catalogFailure) throw const AppFailure('unavailable');
    if (pendingCatalog != null) return pendingCatalog!.future;
    // Same contract as readSourceCatalog: title match, case-insensitive.
    final all = [
      Entry('film', {
        'title': 'Available title',
        'kind': 'movie',
        'sourceId': source.id,
      }),
    ];
    final key = search.trim().toLowerCase();
    return CatalogPage(
      all.where((e) => e.name.toLowerCase().contains(key)).toList(),
      null,
      false,
    );
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    mutationPayloads.add((action, Map.of(payload)));
    if (action != 'readHome') return super.mutate(action, payload);
    homeReads++;
    if (homeFailure) throw const AppFailure('unavailable');
    if (pendingHome != null) return pendingHome!.future;
    return home;
  }

  void restore(String? uid) {
    currentUid = uid;
    authEvents.add(uid);
  }

  @override
  Future<void> signIn(String provider, {bool reauthenticate = false}) async {
    mutations.add(provider);
    restore('u');
  }

  @override
  Future<void> signOut() async => restore(null);
  Future<void> close() async {
    await authEvents.close();
    await accountEvents.close();
    await familyEvents.close();
    await sourcesEvents.close();
  }
}

Future<ProviderContainer> launch(
  WidgetTester tester,
  SessionRepository repository, {
  String location = '/home',
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repository),
      initialRouteProvider.overrideWithValue(location),
    ],
  );
  addTearDown(() {
    container.dispose();
    repository.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('screen'),
      child: UncontrolledProviderScope(
        container: container,
        child: const IplexApp(),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}

String path(ProviderContainer container) =>
    container.read(routerProvider).state.uri.path;
Future<void> login(WidgetTester tester) async {
  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(fixtures.loadTestFont);
  testWidgets('1: guest sees splash while checking auth, then Login', (
    tester,
  ) async {
    final repo = SessionRepository(waitForAuth: true);
    final container = await launch(tester, repo, settle: false);
    expect(find.byType(SessionLoadingPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    repo.restore(null);
    await tester.pumpAndSettle();
    expect(path(container), '/login');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(repo.initialized, isEmpty);
  });
  testWidgets(
    '2: first login opens Home index zero without creating family data',
    (tester) async {
      final repo = SessionRepository();
      final c = await launch(tester, repo);
      await login(tester);
      expect(path(c), '/home');
      expect(find.text('Welcome to iPlex'), findsOneWidget);
      expect(
        tester.widget<BottomNavigation>(find.byType(BottomNavigation)).selected,
        0,
      );
      expect(repo.initialized, ['u']);
      expect(repo.familyReads, 0);
      expect(repo.entryReads, 0);
      expect(repo.mutations.where((m) => m != 'getPaymentsConfig'), ['google']);
      await fixtures.screenshot(tester, 'home-welcome');
    },
  );
  testWidgets('3: existing user logs in to Home, never family setup', (
    tester,
  ) async {
    final repo = SessionRepository(linked: true);
    final c = await launch(tester, repo);
    await login(tester);
    expect(path(c), '/home');
    expect(find.byType(UsersPage), findsNothing);
    expect(repo.initialized, ['u']);
  });
  testWidgets('4: persistent session restores directly to Home without Login', (
    tester,
  ) async {
    final repo = SessionRepository(uid: 'u', waitForAuth: true);
    final c = await launch(tester, repo, settle: false);
    repo.restore('u');
    await tester.pumpAndSettle();
    expect(path(c), '/home');
    expect(find.byType(LoginPage), findsNothing);
    expect(repo.initialized, ['u']);
  });
  testWidgets(
    '5 and 6: the Family tab lists the members and "+" → Invite opens the form; back preserves the tab',
    (tester) async {
      final c = await launch(tester, SessionRepository(uid: 'u', linked: true));
      c.read(routerProvider).go('/users');
      await tester.pumpAndSettle();
      expect(find.text('No additional members yet.'), findsNothing);
      expect(find.text('Create a family'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CircularButton && w.icon == AppIcons.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-profile')), findsNothing);
      expect(find.byType(AppModalSheet), findsNothing);
      expect(path(c), '/users/invite');
      c.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(path(c), '/users');
      // Menu: Home, Busca, Família…
      expect(
        tester.widget<BottomNavigation>(find.byType(BottomNavigation)).selected,
        2,
      );
    },
  );
  testWidgets('7: logout returns to Login; next normal login starts at Home', (
    tester,
  ) async {
    final repo = SessionRepository(uid: 'u', linked: true);
    final c = await launch(tester, repo);
    c.read(routerProvider).go('/account');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(path(c), '/login');
    expect(
      c
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .queryParameters['from'],
      isNull,
    );
    await login(tester);
    expect(path(c), '/home');
  });
  testWidgets(
    '8 and 10: private deep link retains its path, query and fragment through Splash/Login',
    (tester) async {
      final repo = SessionRepository(waitForAuth: true, linked: true);
      const destination = '/account/about?section=language#preference';
      final c = await launch(
        tester,
        repo,
        location: destination,
        settle: false,
      );
      repo.restore(null);
      await tester.pumpAndSettle();
      expect(path(c), '/login');
      expect(
        c
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .queryParameters['from'],
        destination,
      );
      await login(tester);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.toString(),
        destination,
      );
    },
  );
  testWidgets(
    '9: all main tabs stay accessible with no family, profiles, devices or sources',
    (tester) async {
      // Skeletons pulse; with reduced motion they stay still and the test
      // can settle.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final repo = SessionRepository(uid: 'u');
      final c = await launch(tester, repo);
      for (final route in [
        '/users',
        '/devices',
        '/iptv',
        '/account',
        '/home',
      ]) {
        c.read(routerProvider).go(route);
        await tester.pumpAndSettle();
        expect(path(c), route);
        expect(find.text('Create a family'), findsNothing);
      }
      expect(repo.initialized, ['u']);
      expect(find.byType(HomePage, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets('authenticated startup honors an authorized explicit deep link', (
    tester,
  ) async {
    final c = await launch(
      tester,
      SessionRepository(uid: 'u', linked: true),
      location: '/users/u/library/favorites?sort=recent',
    );
    expect(path(c), '/users/u/library/favorites');
    expect(find.text('Favorites'), findsWidgets);
  });
  testWidgets('member deep link cannot bypass administrative permission', (
    tester,
  ) async {
    final c = await launch(
      tester,
      SessionRepository(uid: 'u', linked: true, administrator: false),
      location: '/iptv/add',
    );
    expect(path(c), '/access');
    expect(
      find.text('You do not have permission for this action.'),
      findsWidgets,
    );
    expect(find.byType(IptvSourceForm), findsNothing);
  });
  testWidgets(
    'no-family deep link shows a prerequisite explanation without forcing family setup',
    (tester) async {
      final c = await launch(
        tester,
        SessionRepository(uid: 'u'),
        location: '/users/add',
      );
      expect(path(c), '/access');
      expect(find.byType(UsersPage), findsNothing);
      expect(find.text('Manage family accounts'), findsOneWidget);
    },
  );
  testWidgets(
    'external and nested redirect targets cannot escape the app or loop',
    (tester) async {
      final c = await launch(tester, SessionRepository(uid: 'u'));
      for (final from in [
        'https://example.invalid/',
        '//example.invalid',
        '/login?from=/family',
        '/loading?from=/family',
      ]) {
        c
            .read(routerProvider)
            .go(
              Uri(path: '/login', queryParameters: {'from': from}).toString(),
            );
        await tester.pumpAndSettle();
        expect(path(c), '/home');
      }
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'account initialization keeps splash until ready and runs once across tabs',
    (tester) async {
      // Skeletons pulse; with reduced motion they stay still and the test
      // can settle.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final ready = Completer<void>();
      final repo = SessionRepository(uid: 'u')..initialization = ready;
      final c = await launch(tester, repo, settle: false);
      expect(find.byType(SessionLoadingPage), findsOneWidget);
      expect(find.text('Welcome to iPlex'), findsNothing);
      ready.complete();
      await tester.pumpAndSettle();
      expect(path(c), '/home');
      c.read(routerProvider).go('/users');
      await tester.pumpAndSettle();
      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();
      expect(repo.initialized, ['u']);
    },
  );
  testWidgets('failed initialization offers retry and recovers to Home', (
    tester,
  ) async {
    final repo = SessionRepository(uid: 'u')..initializationFailure = true;
    final c = await launch(tester, repo);
    expect(path(c), '/loading');
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    await fixtures.screenshot(tester, 'session-retry');
    repo.initializationFailure = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(path(c), '/home');
  });
  testWidgets('family errors do not become a global Home redirect', (
    tester,
  ) async {
    final repo = SessionRepository(uid: 'u', linked: true);
    final c = await launch(tester, repo);
    repo.familyEvents.addError(const AppFailure('unavailable'));
    await tester.pumpAndSettle();
    expect(path(c), '/home');
  });
  testWidgets(
    'no-family welcome actions open device and IPTV tabs with useful prerequisites',
    (tester) async {
      final c = await launch(tester, SessionRepository(uid: 'u'));
      await tester.tap(find.text('Add device'));
      await tester.pumpAndSettle();
      expect(path(c), '/devices');
      expect(find.byType(DeviceListPage), findsOneWidget);
      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configure IPTV'));
      await tester.pumpAndSettle();
      expect(path(c), '/iptv');
    },
  );
  testWidgets(
    'loading sources shows skeleton, not an empty or failed catalog',
    (tester) async {
      // Skeletons pulse; with reduced motion they stay still and the test
      // can settle.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final pending = Completer<List<Entry>>();
      final repo = SessionRepository(uid: 'u', linked: true)
        ..pendingSources = pending;
      await launch(tester, repo);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AppLoadingSkeleton), findsOneWidget);
      expect(find.text('Welcome to iPlex'), findsNothing);
      await fixtures.screenshot(tester, 'home-skeleton');
      pending.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(AppLoadingSkeleton), findsNothing);
      expect(find.text('Welcome to iPlex'), findsOneWidget);
    },
  );
  testWidgets(
    'a source request error offers retry without claiming an empty catalog',
    (tester) async {
      final repo = SessionRepository(uid: 'u', linked: true)
        ..sourcesFailure = true;
      await launch(tester, repo);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Welcome to iPlex'), findsNothing);
      repo.sourcesFailure = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to iPlex'), findsOneWidget);
    },
  );
  testWidgets(
    'queued and failed sources show different status and recovery actions',
    (tester) async {
      final repo = SessionRepository(uid: 'u', linked: true)
        ..sources = [
          Entry('s', {'status': 'queued'}),
        ];
      await launch(tester, repo);
      expect(find.text('Waiting to synchronize'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      repo.sourcesEvents.add([
        Entry('s', {'status': 'error'}),
      ]);
      await tester.pumpAndSettle();
      expect(
        find.text('We could not synchronize your catalog'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'loading Home shows skeleton; an empty Home shows a discreet empty state',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final repo = SessionRepository(uid: 'u', linked: true)
        ..sources = [
          Entry('s', {'name': 'Source', 'version': 'v'}),
        ]
        ..pendingHome = pending;
      await launch(tester, repo, settle: false);
      for (var i = 0; i < 10 && repo.homeReads == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(PosterRowsSkeleton), findsOneWidget);
      expect(
        find.text('Your Home is still empty'),
        findsNothing,
        reason: 'loading is not absence of data',
      );
      pending.complete({});
      await tester.pumpAndSettle();
      expect(find.text('Your Home is still empty'), findsOneWidget);
      expect(find.text('Favorites'), findsNothing);
      expect(repo.homeReads, 1);
    },
  );
  testWidgets(
    'Home failure supports retry and displays real rows only after success',
    (tester) async {
      final repo = SessionRepository(uid: 'u', linked: true)
        ..sources = [
          Entry('s', {'name': 'Source', 'version': 'v'}),
        ]
        ..homeFailure = true;
      await launch(tester, repo);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Available title'), findsNothing);
      repo
        ..homeFailure = false
        ..home = {
          'myList': [
            {
              'id': 'film',
              'title': 'Available title',
              'kind': 'movie',
              'sourceId': 's',
            },
          ],
        };
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      // Older backend payload: "my list" titles are shown under Favoritos.
      expect(find.text('Favorites'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-card-film')),
          matching: find.text('Available title'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'search finds catalog titles; no match has clear feedback and can be cleared',
    (tester) async {
      final repo = SessionRepository(uid: 'u', linked: true)
        ..sources = [
          Entry('s', {'name': 'Source', 'version': 'v'}),
        ];
      final c = await launch(tester, repo);
      // Busca is an item of the main menu.
      await tester.tap(find.byKey(const ValueKey('main-menu-1')));
      await tester.pumpAndSettle();
      expect(path(c), '/search');
      await tester.enterText(find.byType(TextFormField), 'avail');
      await tester.pump(const Duration(milliseconds: 351));
      await tester.pumpAndSettle();
      expect(find.text('Available title'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'missing');
      await tester.pump(const Duration(milliseconds: 351));
      await tester.pumpAndSettle();
      expect(find.text('No matching content'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '');
      await tester.pump(const Duration(milliseconds: 351));
      await tester.pumpAndSettle();
      expect(find.text('No matching content'), findsNothing);
    },
  );
  testWidgets(
    'auth stream error offers retry instead of pretending the session is signed out',
    (tester) async {
      final repo = SessionRepository()..authFailure = true;
      final c = await launch(tester, repo);
      expect(path(c), '/loading');
      expect(
        find.text(
          'We could not prepare your session. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LoginPage), findsNothing);
      repo.authFailure = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(path(c), '/login');
    },
  );
  testWidgets('account initialization timeout shows feedback and can recover', (
    tester,
  ) async {
    final ready = Completer<void>();
    final repo = SessionRepository(uid: 'u')..initialization = ready;
    final c = await launch(tester, repo, settle: false);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(path(c), '/loading');
    expect(find.text('Try again'), findsOneWidget);
    ready.complete();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(path(c), '/home');
  });
  testWidgets(
    'a new explicit deep link after logout is preserved even to the previous tab',
    (tester) async {
      final repo = SessionRepository(uid: 'u', linked: true);
      final c = await launch(tester, repo, location: '/account');
      await repo.signOut();
      await tester.pumpAndSettle();
      expect(path(c), '/login');
      c.read(routerProvider).go('/account?origin=link');
      await tester.pumpAndSettle();
      await login(tester);
      expect(
        c.read(routerProvider).state.uri.toString(),
        '/account?origin=link',
      );
    },
  );
  testWidgets(
    'a member sees the family without administrative actions and can open its own entry to leave',
    (tester) async {
      final c = await launch(
        tester,
        SessionRepository(uid: 'u', linked: true, administrator: false),
        location: '/users',
      );
      expect(find.text('Add members'), findsNothing);
      expect(find.byKey(const Key('parental-control')), findsNothing);
      await tester.tap(find.widgetWithText(EntryTile, 'Account'));
      await tester.pumpAndSettle();
      expect(path(c), '/users/member/u');
    },
  );
  testWidgets(
    'late Home responses cannot repopulate Home after its family is removed',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final repo = SessionRepository(uid: 'u', linked: true)
        ..sources = [
          Entry('s', {'name': 'Source', 'version': 'v'}),
        ]
        ..pendingHome = pending;
      await launch(tester, repo, settle: false);
      for (var i = 0; i < 10 && repo.homeReads == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(repo.homeReads, 1);
      repo.linked = false;
      repo.accountEvents.add(repo.account);
      await tester.pumpAndSettle();
      pending.complete({
        'myList': [
          {
            'id': 'removed',
            'title': 'Old family content',
            'kind': 'movie',
            'sourceId': 's',
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Welcome to iPlex'), findsOneWidget);
      expect(find.text('Old family content'), findsNothing);
    },
  );
  testWidgets('welcome remains accessible on a narrow phone with large text', (
    tester,
  ) async {
    await launch(tester, SessionRepository(uid: 'u'));
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Configure IPTV'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });
  testWidgets(
    'Account identifies an unlinked user without inventing a family role',
    (tester) async {
      await launch(tester, SessionRepository(uid: 'u'), location: '/account');
      expect(find.text('No family linked'), findsOneWidget);
      expect(find.text('Member'), findsNothing);
    },
  );
  testWidgets(
    'details page: list actions only with a profile; library writes carry its generation',
    (tester) async {
      final item = {
        'id': 'film',
        'title': 'Available title',
        'kind': 'movie',
        'sourceId': 's',
      };
      final repo = SessionRepository(uid: 'u', linked: true)
        ..sources = [
          Entry('s', {'name': 'Source', 'version': 'v'}),
        ]
        ..home = {
          'recentMovies': [item],
        };
      await launch(tester, repo);
      await tester.tap(find.byKey(const ValueKey('home-card-film')));
      await tester.pumpAndSettle();
      expect(find.text('Watch on TV'), findsOneWidget);
      expect(
        find.byKey(const Key('details-favorite')),
        findsNothing,
        reason: 'no profile, no list write',
      );
      await tester.tap(find.byKey(const Key('details-back')));
      await tester.pumpAndSettle();

      repo.home = {
        'profile': {
          'id': 'admin',
          'name': 'Account',
          'type': 'admin',
          'generations': {'favorites': 3},
        },
        'recentMovies': [item],
      };
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-card-film')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details-favorite')));
      await tester.pumpAndSettle();
      final write = repo.mutationPayloads
          .lastWhere((m) => m.$1 == 'saveLibraryItem')
          .$2;
      expect(write, {
        'profileId': 'admin',
        'generation': 3,
        'list': 'favorites',
        'kind': 'movie',
        'contentId': 'film',
        'sourceId': 's',
        'title': 'Available title',
      });
      expect(
        find.descendant(
          of: find.byKey(const Key('details-favorite')),
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('details-favorite')));
      await tester.pumpAndSettle();
      expect(
        repo.mutationPayloads
            .lastWhere((m) => m.$1 == 'saveLibraryItem')
            .$2['remove'],
        true,
      );
      expect(tester.takeException(), null);
    },
  );
}
