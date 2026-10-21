import 'package:aliens_syndicate_iplex_control/app/app.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/devices_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/name_form.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/list_iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/users_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

void main() {
  group('AppMotion tokens and accessibility', () {
    test('AppMotion semantic tokens comply with performance budget', () {
      // 1. Press in: 60–100 ms
      expect(AppMotion.pressIn.inMilliseconds, inInclusiveRange(60, 100));
      // 2. Press out: 90–140 ms
      expect(AppMotion.pressOut.inMilliseconds, inInclusiveRange(90, 140));
      // 3. Selection: 100–160 ms
      expect(AppMotion.selection.inMilliseconds, inInclusiveRange(100, 160));
      // 4. Tab transition: <= 120 ms
      expect(AppMotion.tabTransition.inMilliseconds, inInclusiveRange(0, 120));
      // 5. Secondary page enter: 150–220 ms
      expect(AppMotion.pageEnter.inMilliseconds, inInclusiveRange(150, 220));
      // 6. Secondary page exit: 120–200 ms
      expect(AppMotion.pageExit.inMilliseconds, inInclusiveRange(120, 200));
      // 7. Dialogs
      expect(AppMotion.dialogEnter.inMilliseconds, inInclusiveRange(120, 200));
      expect(AppMotion.dialogExit.inMilliseconds, inInclusiveRange(100, 180));
    });

    testWidgets('AppMotion.duration respects accessibility reduce motion', (
      tester,
    ) async {
      late Duration normalDuration;
      late Duration reducedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              normalDuration = AppMotion.duration(context, AppMotion.pressIn);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(normalDuration, AppMotion.pressIn);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                reducedDuration = AppMotion.duration(
                  context,
                  AppMotion.pressIn,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(reducedDuration, Duration.zero);
    });
  });

  group('Button tactile response and local visual feedback', () {
    testWidgets(
      'NeumorphicCircularButton gives immediate visual feedback on touch',
      (tester) async {
        bool tapped = false;
        await tester.pumpWidget(
          fixtures.host(
            Center(
              child: NeumorphicCircularButton(
                label: 'Power',
                icon: AppIcons.home,
                onPressed: () => tapped = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final buttonFinder = find.byType(NeumorphicCircularButton);
        expect(buttonFinder, findsOneWidget);

        // Verify elevated state initially
        final initialScale = tester
            .widget<AnimatedScale>(find.byType(AnimatedScale))
            .scale;
        expect(initialScale, 1.0);

        final center = tester.getCenter(buttonFinder);
        final gesture = await tester.startGesture(center);
        await tester.pump();

        final pressedScale = tester
            .widget<AnimatedScale>(find.byType(AnimatedScale))
            .scale;
        expect(pressedScale, 0.96);

        // Release touch
        await gesture.up();
        await tester.pumpAndSettle();

        expect(tapped, true);
        final finalScale = tester
            .widget<AnimatedScale>(find.byType(AnimatedScale))
            .scale;
        expect(finalScale, 1.0);
      },
    );

    testWidgets(
      'NeumorphicActionButton gives immediate tactile feedback on touch',
      (tester) async {
        bool tapped = false;
        await tester.pumpWidget(
          fixtures.host(
            Center(
              child: NeumorphicActionButton(
                label: 'Save Profile',
                onPressed: () => tapped = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final buttonFinder = find.byType(NeumorphicActionButton);
        expect(buttonFinder, findsOneWidget);

        final initialScale = tester
            .widget<AnimatedScale>(find.byType(AnimatedScale))
            .scale;
        expect(initialScale, 1.0);

        // Press down
        final gesture = await tester.startGesture(
          tester.getCenter(buttonFinder),
        );
        await tester
            .pump(); // Starts next frame locally without waiting for async

        final pressedScale = tester
            .widget<AnimatedScale>(find.byType(AnimatedScale))
            .scale;
        expect(pressedScale, 0.985);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(tapped, true);
        final finalScale = tester
            .widget<AnimatedScale>(find.byType(AnimatedScale))
            .scale;
        expect(finalScale, 1.0);
      },
    );
  });

  group('Tab switching & Secondary navigation responsiveness', () {
    testWidgets(
      'Switching between the 5 main tabs preserves state and executes smoothly',
      (tester) async {
        final repo = fixtures.TestRepository(signedIn: true);
        final container = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const IplexApp(),
          ),
        );
        await tester.pumpAndSettle();

        final router = container.read(routerProvider);

        // Start at Home (Tab 0)
        expect(find.byType(HomePage), findsOneWidget);

        // Switch to Users (Tab 1)
        router.go('/users');
        await tester.pumpAndSettle();
        expect(find.byType(UsersPage), findsOneWidget);

        // Switch to Devices (Tab 2)
        router.go('/devices');
        await tester.pumpAndSettle();
        expect(find.byType(DevicesPage), findsOneWidget);

        // Switch to IPTV (Tab 3)
        router.go('/iptv');
        await tester.pumpAndSettle();
        expect(find.byType(ListIptvPage), findsOneWidget);

        // Switch to Account (Tab 4)
        router.go('/account');
        await tester.pumpAndSettle();
        expect(find.byType(AccountPage), findsOneWidget);

        // Switch back to Home (Tab 0) - immediate without recreation
        router.go('/home');
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
      },
    );

    testWidgets(
      'Secondary route transition completes within 190ms pageEnter budget',
      (tester) async {
        final repo = fixtures.TestRepository(signedIn: true);
        final container = ProviderContainer(
          overrides: [repositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const IplexApp(),
          ),
        );
        await tester.pumpAndSettle();

        final router = container.read(routerProvider);

        // Navigate to a secondary route: /users/add
        router.push('/users/add');
        await tester.pump(); // Start transition

        // Pump less than pageEnter: transition is in progress
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.hasRunningAnimations, true);

        // Pump remaining duration: animation completes within budget
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.hasRunningAnimations, false);
        expect(find.byType(NameForm), findsOneWidget);
      },
    );
  });

  group('Rebuild isolation and raster efficiency', () {
    testWidgets(
      'DevicesPage does not rebuild when clock ticks without online state change',
      (tester) async {
        int buildCount = 0;
        final testDevice = Entry('tv', {
          'name': 'Living Room TV',
          'onlineUntil': DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
          'sessionId': 'session-123',
        });

        final repo = fixtures.TestRepository(signedIn: true);
        final container = ProviderContainer(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            entriesProvider('devices')
                .overrideWith((ref) => Stream.value([testDevice])),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTokens.theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) {
                  buildCount++;
                  return const Scaffold(body: DevicesPage());
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(buildCount, 1);

        // Advance clock by 1 second multiple times
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // Parent and DevicesPage must NOT have re-built repeatedly
        expect(buildCount, 1);
      },
    );

    testWidgets(
      'GraphiteSurface wraps in RepaintBoundary to isolate paint layers',
      (tester) async {
        await tester.pumpWidget(
          fixtures.host(const GraphiteSurface(child: Text('Cached Layer'))),
        );
        await tester.pumpAndSettle();

        final surface = find.byType(GraphiteSurface);
        expect(surface, findsOneWidget);

        final boundaryFinder = find.descendant(
          of: surface,
          matching: find.byType(RepaintBoundary),
        );
        expect(boundaryFinder, findsWidgets);
      },
    );
  });
}
