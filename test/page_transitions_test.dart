import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/about/about_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_details_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_form.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

void main() {
  setUpAll(fixtures.loadTestFont);

  testWidgets(
    'main menu still changes tabs without horizontal page transitions',
    (tester) async {
      final container = await navigation.launch(
        tester,
        navigation.SessionRepository(uid: 'u', linked: true),
      );
      final router = container.read(routerProvider);
      router.go('/users');
      await tester.pump();
      expect(find.byType(UsersPage), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(UsersPage),
          matching: find.byType(HorizontalPageTransition),
        ),
        findsNothing,
      );
      expect(tester.getTopLeft(find.byType(UsersPage)).dx, 0);
      router.go('/account');
      await tester.pump();
      expect(find.byType(AccountPage), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(AccountPage),
          matching: find.byType(HorizontalPageTransition),
        ),
        findsNothing,
      );
      expect(tester.getTopLeft(find.byType(AccountPage)).dx, 0);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'child enters from the right while parent moves left, and returns when popped',
    (tester) async {
      final container = await navigation.launch(
        tester,
        navigation.SessionRepository(uid: 'u', linked: true),
        location: '/account',
      );
      final router = container.read(routerProvider);
      router.push('/account/about');
      await tester.pump();
      await tester.pump();
      final page = find.byType(AboutPage);
      final parent = find.byType(AccountPage, skipOffstage: false);
      final initial = tester.getTopLeft(page);
      await tester.pump(const Duration(milliseconds: 50));
      final entering = tester.getTopLeft(page);
      expect(entering.dx, greaterThan(0));
      expect(entering.dx, lessThan(initial.dx));
      expect(entering.dy, initial.dy);
      expect(tester.getTopLeft(parent).dx, lessThan(0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(page).dx, closeTo(0, 0.01));
      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final leaving = tester.getTopLeft(page);
      expect(leaving.dx, greaterThan(0));
      expect(leaving.dy, initial.dy);
      expect(tester.getTopLeft(parent).dx, lessThan(0));
      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(tester.getTopLeft(parent).dx, closeTo(0, 0.01));
      expect(navigation.path(container), '/account');
    },
  );

  testWidgets(
    'nested child slides horizontally while its parent moves left and returns',
    (tester) async {
      final container = await navigation.launch(
        tester,
        navigation.SessionRepository(uid: 'u', linked: true),
        location: '/iptv/source',
      );
      final router = container.read(routerProvider);
      router.push('/iptv/source/edit');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final parent = find.byType(IptvPage, skipOffstage: false);
      final child = find.byType(IptvSourceForm);
      expect(tester.getTopLeft(parent).dx, lessThan(0));
      expect(tester.getTopLeft(child).dx, greaterThan(0));
      expect(tester.getTopLeft(child).dy, 0);
      await tester.pumpAndSettle();
      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(child).dx, greaterThan(0));
      expect(tester.getTopLeft(parent).dx, lessThan(0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(parent).dx, closeTo(0, 0.01));
      expect(navigation.path(container), '/iptv/source');
    },
  );

  testWidgets(
    'reduce motion keeps secondary pages still when opening and returning',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final container = await navigation.launch(
        tester,
        navigation.SessionRepository(uid: 'u', linked: true),
        location: '/account',
      );
      final router = container.read(routerProvider);
      router.push('/account/about');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final child = find.byType(AboutPage);
      expect(tester.getTopLeft(child).dx, 0);
      expect(
        find.ancestor(of: child, matching: find.byType(SlideTransition)),
        findsNothing,
      );
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsNothing);
      expect(tester.getTopLeft(find.byType(AccountPage)).dx, 0);
      expect(navigation.path(container), '/account');
    },
  );

  testWidgets(
    'Navigator routes use the same horizontal motion as go_router children',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Parent')),
        ),
      );
      await tester.pumpAndSettle();
      const key = Key('navigator-child');
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(key: key, body: Text('Child')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(find.byKey(key)).dx, greaterThan(0));
      expect(tester.getTopLeft(find.byKey(key)).dy, 0);
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(find.byKey(key)).dx, greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsNothing);
    },
  );
}
