import 'dart:async';

import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/data/subscription_provider.dart';
import 'package:aliens_syndicate_iplex_control/features/authentication/login_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/subscription_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

class AccessRepository extends navigation.SessionRepository {
  AccessRepository({
    super.linked = true,
    super.administrator,
    this.status = 'notStarted',
  }) : super(uid: 'u');
  final String status;
  int subscriptionReads = 0;
  bool subscriptionFailure = false;
  Completer<void>? pendingSubscription;
  Map<String, dynamic> dates = {};

  @override
  Stream<Entry?> watchEntry(
    String familyId,
    String collection,
    String id,
  ) async* {
    if (collection == 'private') {
      subscriptionReads++;
      if (subscriptionFailure) throw const AppFailure('unavailable');
      await pendingSubscription?.future;
      yield Entry(id, {'status': status, ...dates});
    } else if (collection == 'sources') {
      yield Entry(id, {
        'name': 'Free source',
        'format': 'm3u',
        'host': 'example.com',
        'status': 'ready',
      });
    } else {
      yield null;
    }
  }
}

Future<void> go(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  container.read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(AppButton, 'Save');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(fixtures.loadTestFont);

  for (final status in ['notStarted', 'expired']) {
    testWidgets(
      '$status subscription does not gate Home, catalog or any of the five tabs',
      (tester) async {
        final repo = AccessRepository(status: status);
        repo.sources = [
          Entry('source', {
            'status': 'ready',
            'version': 'v',
            'name': 'Free catalog',
          }),
        ];
        final container = await navigation.launch(tester, repo);
        // Home rows and catalog search are reachable without a subscription.
        expect(repo.homeReads, 1);
        await go(tester, container, '/search');
        await tester.enterText(find.byType(TextFormField), 'avail');
        await tester.pump(const Duration(milliseconds: 351));
        await tester.pumpAndSettle();
        expect(find.text('Available title'), findsOneWidget);
        for (final location in [
          '/search',
          '/users',
          '/devices',
          '/iptv',
          '/account',
          '/home',
        ]) {
          await go(tester, container, location);
          expect(navigation.path(container), location);
        }
        expect(repo.subscriptionReads, 0);
      },
    );

    testWidgets(
      '$status subscription permits profile creation and IPTV creation/editing',
      (tester) async {
        final repo = AccessRepository(status: status);
        final container = await navigation.launch(tester, repo);
        await go(tester, container, '/users/add');
        await tester.enterText(find.byType(TextFormField), 'Free profile');
        await save(tester);
        expect(repo.mutations, contains('saveProfile'));
        for (final location in ['/iptv/add', '/iptv/source/edit']) {
          await go(tester, container, location);
          await tester.enterText(
            find.byType(TextFormField).at(0),
            'Free source',
          );
          await tester.enterText(
            find.byType(TextFormField).at(1),
            'https://example.com/list',
          );
          await save(tester);
          expect(navigation.path(container), isNot('/account/subscription'));
        }
        expect(
          repo.mutations.where((action) => action == 'saveSource'),
          hasLength(2),
        );
        expect(repo.subscriptionReads, 0);
      },
    );
  }

  testWidgets(
    'a new account has its family already: no creation, no subscription',
    (tester) async {
      final repo = AccessRepository(linked: true);
      final container = await navigation.launch(tester, repo);
      await go(tester, container, '/users');
      // The account is already a member of its own family.
      expect(find.byKey(const Key('family-list')), findsOneWidget);
      expect(find.text('Create a family'), findsNothing);
      expect(repo.mutations, isNot(contains('createFamily')));
      expect(repo.subscriptionReads, 0);
    },
  );

  testWidgets('expired subscription does not prevent requesting an IPTV sync', (
    tester,
  ) async {
    final repo = AccessRepository(status: 'expired');
    final container = await navigation.launch(
      tester,
      repo,
      location: '/iptv/source',
    );
    final sync = find.widgetWithText(AppButton, 'Sync now');
    await tester.ensureVisible(sync);
    await tester.pumpAndSettle();
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expect(repo.mutations, contains('syncSource'));
    expect(repo.subscriptionReads, 0);
    expect(navigation.path(container), '/iptv/source');
  });

  testWidgets(
    'unlinked account can open plans through Account without a family guard',
    (tester) async {
      final repo = AccessRepository(linked: false);
      final container = await navigation.launch(
        tester,
        repo,
        location: '/account',
      );
      await tester.tap(find.text('Player subscription'));
      await tester.pumpAndSettle();
      expect(navigation.path(container), '/account/subscription');
      expect(find.byType(SubscriptionPage), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Annual'), findsOneWidget);
      expect(find.text('Free iPlex Gestor'), findsOneWidget);
      expect(repo.subscriptionReads, 0);
      await fixtures.screenshot(tester, 'subscription-plans');
    },
  );

  testWidgets(
    'family member consults plans without reading private billing or gaining admin access',
    (tester) async {
      final repo = AccessRepository(administrator: false);
      final container = await navigation.launch(
        tester,
        repo,
        location: '/account/subscription',
      );
      expect(find.text('Monthly'), findsOneWidget);
      expect(
        find.textContaining('available to its administrator'),
        findsOneWidget,
      );
      expect(repo.subscriptionReads, 0);
      for (final location in ['/users/add', '/iptv/add', '/devices/add']) {
        await go(tester, container, location);
        expect(navigation.path(container), '/access');
      }
    },
  );

  for (final status in ['trial', 'active', 'cancelled']) {
    testWidgets(
      'past $status deadline is informational expiry and never claims active access',
      (tester) async {
        final repo = AccessRepository(status: status)
          ..dates = {'trialEndsAt': 1, 'paidUntil': 1};
        final container = await navigation.launch(
          tester,
          repo,
          location: '/account/subscription',
        );
        expect(find.text('Subscription expired'), findsOneWidget);
        expect(find.text('Subscription active'), findsNothing);
        expect(find.text('Monthly'), findsOneWidget);
        await go(tester, container, '/home');
        expect(navigation.path(container), '/home');
      },
    );
  }

  testWidgets(
    'pending private billing shows skeleton while informational plans remain available',
    (tester) async {
      // Skeletons pulse; with reduced motion they stay still and the test
      // can settle.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final pending = Completer<void>();
      final repo = AccessRepository()..pendingSubscription = pending;
      await navigation.launch(tester, repo, location: '/account/subscription');
      expect(find.byType(AppLoadingSkeleton), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AppLoadingSkeleton), findsNothing);
    },
  );

  testWidgets(
    'billing failure offers retry while retaining plans and free Manager explanation',
    (tester) async {
      final repo = AccessRepository()..subscriptionFailure = true;
      await navigation.launch(tester, repo, location: '/account/subscription');
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Free iPlex Gestor'), findsOneWidget);
      expect(find.text('Annual'), findsOneWidget);
      repo.subscriptionFailure = false;
      final retry = find.widgetWithText(AppButton, 'Try again');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsNothing);
    },
  );

  testWidgets(
    'losing administrator role removes private status while preserving access to plans',
    (tester) async {
      final repo = AccessRepository(status: 'active')
        ..dates = {
          'paidUntil': DateTime.now()
              .add(const Duration(days: 30))
              .millisecondsSinceEpoch,
        };
      final container = await navigation.launch(
        tester,
        repo,
        location: '/account/subscription',
      );
      final privateStatus = container.listen(subscriptionProvider, (_, _) {});
      addTearDown(privateStatus.close);
      expect(find.text('Subscription active'), findsOneWidget);
      repo.familyEvents.add(
        const Family(id: 'family', adminId: 'other', members: {'u': 'member'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subscription active'), findsNothing);
      expect(find.text('Monthly'), findsOneWidget);
      expect(navigation.path(container), '/account/subscription');
      // Even direct consumers cannot retain billing data after the role change.
      expect(container.read(subscriptionProvider).asData?.value, isNull);
      expect(container.read(subscriptionProvider).hasValue, isTrue);
    },
  );

  testWidgets(
    'anonymous visitor cannot enter the plans route or private Manager',
    (tester) async {
      final repo = navigation.SessionRepository();
      final container = await navigation.launch(
        tester,
        repo,
        location: '/account/subscription',
      );
      expect(navigation.path(container), '/login');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(repo.entryReads, 0);
    },
  );
}
