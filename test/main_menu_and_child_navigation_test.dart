import 'package:flutter/material.dart';
import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_list_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/about/about_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_form.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/list_iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/users_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_add_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

void main() {
  setUpAll(fixtures.loadTestFont);

  group('CircularButton Gesture Tests', () {
    testWidgets(
      'CircularButton responds to touch gestures reliably near edges',
      (tester) async {
        bool tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: CircularButton(
                  label: 'Add',
                  icon: AppIcons.add,
                  onPressed: () => tapped = true,
                ),
              ),
            ),
          ),
        );

        final button = find.byType(CircularButton);
        // Touch near edge (offset 5, 5 from top left)
        final gesture = await tester.startGesture(
          tester.getTopLeft(button) + const Offset(5, 5),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
      },
    );

    testWidgets('CircularButton tap after 550ms press', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CircularButton(
                label: 'Add',
                icon: AppIcons.add,
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      final button = find.byType(CircularButton);
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 550));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('CircularButton tap with micro-movement', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CircularButton(
                label: 'Add',
                icon: AppIcons.add,
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      final button = find.byType(CircularButton);
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveBy(const Offset(3, 3));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('Main Menu & Header Alignment', () {
    testWidgets(
      'Users, Devices and IPTV have + button; Home and Account do not',
      (tester) async {
        final container = await navigation.launch(
          tester,
          navigation.SessionRepository(
            uid: 'u',
            linked: true,
            administrator: true,
          ),
          location: '/home',
        );
        final router = container.read(routerProvider);

        // 1. Home - No + button
        expect(find.byType(HomePage), findsOneWidget);
        final homeAdd = find.descendant(
          of: find.byType(HomePage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(homeAdd, findsNothing);

        // 2. Users - Has + button at top
        router.go('/users');
        await tester.pumpAndSettle();
        expect(find.byType(UsersPage), findsOneWidget);
        final usersAdd = find.descendant(
          of: find.byType(UsersPage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(usersAdd, findsOneWidget);
        await tester.tap(usersAdd);
        await tester.pumpAndSettle();
        expect(navigation.path(container), '/users/invite');
        router.pop();
        await tester.pumpAndSettle();

        // 3. Devices - Has + button at top
        router.go('/devices');
        await tester.pumpAndSettle();
        expect(find.byType(DeviceListPage), findsOneWidget);
        final devicesAdd = find.descendant(
          of: find.byType(DeviceListPage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(devicesAdd, findsOneWidget);
        await tester.tap(devicesAdd);
        await tester.pumpAndSettle();
        expect(find.byType(DeviceAddPage), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();

        // 4. IPTV - Has + button at top
        router.go('/iptv');
        await tester.pumpAndSettle();
        expect(find.byType(ListIptvPage), findsOneWidget);
        final iptvAdd = find.descendant(
          of: find.byType(ListIptvPage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(iptvAdd, findsOneWidget);
        await tester.tap(iptvAdd);
        await tester.pumpAndSettle();
        expect(find.byType(IptvSourceForm), findsOneWidget);

        // 5. Account - No + button
        router.go('/account');
        await tester.pumpAndSettle();
        expect(find.byType(AccountPage), findsOneWidget);
        final accountAdd = find.descendant(
          of: find.byType(AccountPage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(accountAdd, findsNothing);
      },
    );

    testWidgets(
      'Home starts at the top; management screens retain title alignment',
      (tester) async {
        final container = await navigation.launch(
          tester,
          navigation.SessionRepository(
            uid: 'u',
            linked: true,
            administrator: true,
          ),
          location: '/home',
        );
        final router = container.read(routerProvider);
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('home-title'))),
        );

        // Top of each main screen's header row: the title row of PageTemplate;
        // on Home, the compact app bar.
        double headerTop(Finder inHeader) {
          expect(inHeader, findsAtLeastNWidgets(1));
          return tester
              .getTopLeft(
                find
                    .ancestor(of: inHeader.first, matching: find.byType(Row))
                    .first,
              )
              .dy;
        }

        double titleY(String text) => headerTop(
          find.descendant(
            of: find.byType(PageTemplate),
            matching: find.text(text),
          ),
        );

        final homeY = headerTop(find.byKey(const Key('home-title')));

        router.go('/users');
        await tester.pumpAndSettle();
        final usersY = titleY(l10n.familyTitle);
        expect(usersY, greaterThan(homeY));

        router.go('/devices');
        await tester.pumpAndSettle();
        final devicesY = titleY(l10n.devices);
        expect(devicesY, equals(usersY));

        router.go('/iptv');
        await tester.pumpAndSettle();
        final iptvY = titleY(l10n.iptv);
        expect(iptvY, equals(usersY));

        router.go('/account');
        await tester.pumpAndSettle();
        final accountY = titleY(l10n.account);
        expect(accountY, equals(usersY));
      },
    );
  });

  group('Child Screens Menu Visibility & Back Button', () {
    testWidgets('Child screens do NOT show the main menu bottom navigation', (
      tester,
    ) async {
      final container = await navigation.launch(
        tester,
        navigation.SessionRepository(
          uid: 'u',
          linked: true,
          administrator: true,
        ),
        location: '/account',
      );
      final router = container.read(routerProvider);

      // On parent screen (/account): BottomNavigation is visible
      expect(find.byType(BottomNavigation), findsOneWidget);

      // Navigate to child screen (/account/about)
      router.push('/account/about');
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);

      // BottomNavigation MUST NOT be visible on child screen
      expect(find.byType(BottomNavigation), findsNothing);

      // Pop back to /account
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(AccountPage), findsOneWidget);

      // BottomNavigation is visible again
      expect(find.byType(BottomNavigation), findsOneWidget);
    });

    testWidgets(
      'Child screen has circular back button on the left of title and same top alignment',
      (tester) async {
        final container = await navigation.launch(
          tester,
          navigation.SessionRepository(
            uid: 'u',
            linked: true,
            administrator: true,
          ),
          location: '/account',
        );
        final router = container.read(routerProvider);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(PageTemplate).first),
        );

        final accountTitle = find.descendant(
          of: find.byType(PageTemplate),
          matching: find.text(l10n.account),
        );
        final accountTitleY = tester.getTopLeft(accountTitle.first).dy;

        router.push('/account/about');
        await tester.pumpAndSettle();

        final settingsTitle = find.descendant(
          of: find.byType(PageTemplate),
          matching: find.text(l10n.about),
        );
        expect(settingsTitle, findsOneWidget);
        final settingsTitleY = tester.getTopLeft(settingsTitle).dy;

        // Same vertical alignment as main screens
        expect(settingsTitleY, equals(accountTitleY));

        // Circular back button is present on the left
        final backBtn = find.byWidgetPredicate(
          (w) => w is CircularButton && w.icon == AppIcons.left,
        );
        expect(backBtn, findsOneWidget);

        // Verify back button is to the left of the title
        final backBtnX = tester.getTopLeft(backBtn).dx;
        final titleX = tester.getTopLeft(settingsTitle).dx;
        expect(backBtnX, lessThan(titleX));

        // Tapping circular back button pops back to parent
        await tester.tap(backBtn);
        await tester.pumpAndSettle();

        expect(find.byType(AboutPage), findsNothing);
        expect(find.byType(AccountPage), findsOneWidget);
        expect(find.byType(BottomNavigation), findsOneWidget);
      },
    );

    testWidgets(
      'IPTV child screens (details & edit) hide main menu and have circular back button',
      (tester) async {
        final container = await navigation.launch(
          tester,
          navigation.SessionRepository(
            uid: 'u',
            linked: true,
            administrator: true,
          ),
          location: '/iptv',
        );
        final router = container.read(routerProvider);

        // On /iptv: BottomNavigation is visible
        expect(find.byType(BottomNavigation), findsOneWidget);

        // Navigate to /iptv/add
        router.push('/iptv/add');
        await tester.pumpAndSettle();
        expect(find.byType(IptvSourceForm), findsOneWidget);

        // BottomNavigation is NOT visible on /iptv/add
        expect(find.byType(BottomNavigation), findsNothing);

        // Back button on the left
        final backBtn = find.byWidgetPredicate(
          (w) => w is CircularButton && w.icon == AppIcons.left,
        );
        expect(backBtn, findsOneWidget);

        // Tap back button
        await tester.tap(backBtn);
        await tester.pumpAndSettle();

        expect(find.byType(IptvSourceForm), findsNothing);
        expect(find.byType(ListIptvPage), findsOneWidget);
        expect(find.byType(BottomNavigation), findsOneWidget);
      },
    );
  });
}
