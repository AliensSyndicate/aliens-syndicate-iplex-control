import 'dart:async';

import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

/// Session with one linked TV and one IPTV source: every main screen and
/// shared component of the Design System, captured with
/// `--dart-define=SCREENSHOTS=true`.
class _Repo extends navigation.SessionRepository {
  _Repo() : super(uid: 'u', linked: true) {
    sources = [
      Entry('s', {
        'name': 'Minha IPTV',
        'version': 'v',
        'status': 'ready',
        'format': 'xtream',
        'channelCount': 120,
        'movieCount': 340,
        'seriesCount': 45,
        'lastSuccessfulSyncAt': DateTime(
          2026,
          10,
          22,
          9,
        ).millisecondsSinceEpoch,
      }),
    ];
    home = {
      'recentMovies': [
        {
          'id': 'm1',
          'title': 'Missão Fictícia',
          'kind': 'movie',
          'sourceId': 's',
        },
      ],
    };
  }

  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) {
    if (collection != 'devices') {
      return super.watchEntries(familyId, collection);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return Stream.value([
      Entry('tv1', {
        'name': 'Sala de Estar',
        'status': 'linked',
        'platform': 'tizen',
        'model': 'Samsung QN90',
        'lastSeenAt': now,
        'onlineUntil': now + 3600000,
        'nowPlaying': {
          'itemId': 'm1',
          'sourceId': 's',
          'title': 'Missão Fictícia',
          'kind': 'movie',
          'state': 'playing',
          'updatedAt': now,
          'positionSec': 30,
          'durationSec': 100,
        },
      }),
      Entry('tv2', {
        'name': 'Quarto',
        'status': 'linked',
        'platform': 'android_tv',
        'lastSeenAt': now - 86400000,
      }),
    ]);
  }
}

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets('every main screen uses the new Design System', (tester) async {
    final c = await navigation.launch(tester, _Repo());
    final router = c.read(routerProvider);
    Future<void> shot(String location, String name) async {
      router.go(location);
      await tester.pumpAndSettle();
      await fixtures.screenshot(tester, 'design-system/$name');
    }

    // Home tabs = Busca tabs (same component).
    expect(find.byType(AppTabs<int>), findsOneWidget);
    await fixtures.screenshot(tester, 'design-system/home');
    await shot('/search', 'search');
    expect(find.byWidgetPredicate((w) => w is AppTabs), findsOneWidget);
    await shot('/devices', 'devices');
    await shot('/iptv', 'iptv');
    await shot('/users', 'family');
    await shot('/iptv/add', 'iptv-form');
    expect(
      find.byWidgetPredicate((w) => w is AppTabs),
      findsOneWidget,
      reason: 'IPTV format selector = shared tabs',
    );
    await shot('/account', 'account');

    // Bottom sheet (IPTV list picker).
    router.go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-source-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet-handle')), findsOneWidget);
    await fixtures.screenshot(tester, 'design-system/sheet');

    Navigator.of(tester.element(find.byKey(const Key('sheet-handle')))).pop();
    await tester.pumpAndSettle();

    // Content options (⋮ on a poster card).
    await tester.tap(find.byKey(const ValueKey('home-card-more-m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('content-options')), findsOneWidget);
    // No profile linked here: watch, share and details (lists need one).
    expect(find.byType(SheetActionRow), findsNWidgets(3));
    await fixtures.screenshot(tester, 'design-system/sheet-options');

    // Device selection (Assistir na TV).
    await tester.tap(find.byKey(const Key('option-watch')));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionRow), findsNWidgets(2));
    expect(
      tester.widget<AppButton>(find.byKey(const Key('send-to-tv'))).primary,
      isTrue,
    );
    await fixtures.screenshot(tester, 'design-system/sheet-devices');
    Navigator.of(tester.element(find.byKey(const Key('send-to-tv')))).pop();
    await tester.pumpAndSettle();

    // Destructive confirmation.
    unawaited(
      confirmRemoval(tester.element(find.byKey(const Key('home-title')))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DangerMark), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Remove'))
          .destructive,
      isTrue,
    );
    await fixtures.screenshot(tester, 'design-system/sheet-confirm');
    Navigator.of(tester.element(find.byType(DangerMark))).pop(false);
    await tester.pumpAndSettle();

    // No graphite material is painted anywhere: flat fills only.
    for (final finish in GraphiteFinish.values) {
      for (final recessed in [false, true]) {
        expect([
          AppColors.surfaceDefault,
          AppColors.surfaceElevated,
          AppColors.surfacePressed,
        ], contains(GraphiteMaterialPainter.fill(finish, recessed)));
      }
    }
    // Menu: translucent background, icons only.
    final menu = tester
        .widgetList<ColoredBox>(
          find.descendant(
            of: find.byType(BottomNavigation),
            matching: find.byType(ColoredBox),
          ),
        )
        .first;
    expect(menu.color, AppColors.navigationBar);
  });

  testWidgets('list skeleton: flat blocks, same pulse as the other skeletons', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = _Repo()..pendingSources = Completer<List<Entry>>();
    await navigation.launch(tester, repo, settle: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppLoadingSkeleton),
        matching: find.byType(AppSkeletonPulse),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AppLoadingSkeleton),
        matching: find.byType(GraphiteSurface),
      ),
      findsNothing,
      reason: 'no card around the bones',
    );
    await fixtures.screenshot(tester, 'design-system/skeleton');
  });

  testWidgets('horizontal scrollers run edge to edge with inner padding', (
    tester,
  ) async {
    final repo = _Repo()
      ..home = {
        'continueWatching': [
          {
            'id': 'm1',
            'title': 'Missão Fictícia',
            'kind': 'movie',
            'sourceId': 's',
            'progress': {'position': 30, 'duration': 100},
          },
        ],
        'recentMovies': [
          {'id': 'm2', 'title': 'Filme Novo', 'kind': 'movie', 'sourceId': 's'},
        ],
      };
    final c = await navigation.launch(tester, repo);
    void edgeToEdge(Finder scroller) {
      final rect = tester.getRect(scroller);
      expect([rect.left, rect.right], [0, 390], reason: 'no side margin');
    }

    // Tabs: start at the screen edge; the first pill is the padding away.
    void tabsEdgeToEdge(Finder tabs, Object firstValue) {
      expect(
        tester
            .getRect(
              find.descendant(
                of: tabs,
                matching: find.byType(SingleChildScrollView),
              ),
            )
            .left,
        0,
      );
      expect(
        tester.getTopLeft(find.byKey(ValueKey('tab-$firstValue'))).dx,
        AppSpacing.lg,
      );
    }

    // Home tabs and rows.
    tabsEdgeToEdge(find.byKey(const Key('home-tabs')), 0);
    final row = find.byKey(
      const PageStorageKey('home-row-New releases'),
    );
    edgeToEdge(row);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home-card-m2'))).dx,
      AppSpacing.lg,
      reason: 'same amount as inner padding',
    );
    // "Now playing" item: same side margins as the device cards.
    final playing = tester.getRect(find.byKey(const Key('now-playing-bar')));
    c.read(routerProvider).go('/devices');
    await tester.pumpAndSettle();
    final device = tester.getRect(find.byType(InfoCard).first);
    expect([playing.left, playing.right], [device.left, device.right]);
    // Busca filters.
    c.read(routerProvider).go('/search');
    await tester.pumpAndSettle();
    tabsEdgeToEdge(
      find.byWidgetPredicate((w) => w is AppTabs),
      'SearchFilter.all',
    );
  });
}
