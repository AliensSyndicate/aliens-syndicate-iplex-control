import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/devices_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/list_iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/users_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/home_welcome_state.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/iptv_empty_state.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

void main() {
  setUpAll(fixtures.loadTestFont);

  group('App bar button sizes and empty states tests', () {
    testWidgets(
      'Add buttons in app bar and back buttons have the exact same size as main menu buttons',
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

        // Find a bottom menu button size
        final bottomButtons = find.descendant(
          of: find.byType(BottomNavigation),
          matching: find.byType(CircularButton),
        );
        expect(bottomButtons, findsNWidgets(5));
        final menuBtnSize = tester.getSize(bottomButtons.first);
        expect(menuBtnSize.width, equals(AppDimensions.touch));
        expect(menuBtnSize.height, equals(AppDimensions.touch));

        // 1. Users page add button size
        router.go('/users');
        await tester.pumpAndSettle();
        final usersAdd = find.descendant(
          of: find.byType(UsersPage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(usersAdd, findsOneWidget);
        final usersAddBtn = tester.widget<CircularButton>(usersAdd);
        expect(usersAddBtn.size, equals(AppDimensions.touch));
        final usersAddSize = tester.getSize(usersAdd);
        expect(usersAddSize, equals(menuBtnSize));

        // 2. Devices page add button size
        router.go('/devices');
        await tester.pumpAndSettle();
        final devicesAdd = find.descendant(
          of: find.byType(DevicesPage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(devicesAdd, findsOneWidget);
        final devicesAddBtn = tester.widget<CircularButton>(devicesAdd);
        expect(devicesAddBtn.size, equals(AppDimensions.touch));
        final devicesAddSize = tester.getSize(devicesAdd);
        expect(devicesAddSize, equals(menuBtnSize));

        // 3. IPTV page add button size
        router.go('/iptv');
        await tester.pumpAndSettle();
        final iptvAdd = find.descendant(
          of: find.byType(ListIptvPage),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.add,
          ),
        );
        expect(iptvAdd, findsOneWidget);
        final iptvAddBtn = tester.widget<CircularButton>(iptvAdd);
        expect(iptvAddBtn.size, equals(AppDimensions.touch));
        final iptvAddSize = tester.getSize(iptvAdd);
        expect(iptvAddSize, equals(menuBtnSize));

        // 4. Back button in PageTemplate (navigate to child screen /account/settings)
        router.go('/account/settings');
        await tester.pumpAndSettle();
        final backButton = find.descendant(
          of: find.byType(PageTemplate),
          matching: find.byWidgetPredicate(
            (w) => w is CircularButton && w.icon == AppIcons.left,
          ),
        );
        expect(backButton, findsOneWidget);
        final backBtnWidget = tester.widget<CircularButton>(backButton);
        expect(backBtnWidget.size, equals(AppDimensions.touch));
        final backBtnSize = tester.getSize(backButton);
        expect(backBtnSize, equals(menuBtnSize));
      },
    );

    testWidgets('Main screens do not display subtitles below titles', (
      tester,
    ) async {
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
        tester.element(find.byKey(const Key('home-search'))),
      );

      // Home has no subtitle
      expect(find.text(l10n.catalogSubtitle), findsNothing);

      // IPTV has no subtitle
      router.go('/iptv');
      await tester.pumpAndSettle();
      expect(find.text(l10n.iptvSubtitle), findsNothing);
    });

    testWidgets(
      'Empty states on main screens do not display circular screen icon in the center',
      (tester) async {
        // Test HomeWelcomeState
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: HomeWelcomeState()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final homeEmptyState = find.byType(EmptyState);
        expect(homeEmptyState, findsOneWidget);
        // NeumorphicSurface circle should NOT be rendered
        final homeCircle = find.descendant(
          of: homeEmptyState,
          matching: find.byWidgetPredicate(
            (w) => w is NeumorphicSurface && w.circle,
          ),
        );
        expect(homeCircle, findsNothing);

        // Test IptvEmptyState
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: IptvEmptyState()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final sourcesEmptyState = find.byType(EmptyState);
        expect(sourcesEmptyState, findsOneWidget);
        final sourcesCircle = find.descendant(
          of: sourcesEmptyState,
          matching: find.byWidgetPredicate(
            (w) => w is NeumorphicSurface && w.circle,
          ),
        );
        expect(sourcesCircle, findsNothing);
      },
    );

    testWidgets(
      'NeumorphicTextField has fixed top label, 56px height box, and white label and border on focus',
      (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: NeumorphicTextField(
                  label: 'Nome da Fonte',
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Label is fixed at top as Text widget
        final labelFinder = find.text('Nome da Fonte');
        expect(labelFinder, findsOneWidget);
        Text labelText = tester.widget<Text>(labelFinder);
        expect(labelText.style?.color, equals(AppColors.textSecondary));

        // 2. Input box has fixed height of 56 pixels (AppDimensions.button)
        final surfaceFinder = find.byType(GraphiteSurface);
        expect(surfaceFinder, findsOneWidget);
        final surfaceSize = tester.getSize(surfaceFinder);
        expect(surfaceSize.height, equals(56.0));

        // Unfocused border
        final containerFinder = find.descendant(
          of: surfaceFinder,
          matching: find.byType(AnimatedContainer),
        );
        expect(containerFinder, findsOneWidget);
        AnimatedContainer container = tester.widget<AnimatedContainer>(
          containerFinder,
        );
        BoxDecoration dec = container.decoration as BoxDecoration;
        Border border = dec.border as Border;
        expect(border.top.color, equals(AppColors.borderLight));

        // 3. Focus the field
        focusNode.requestFocus();
        await tester.pumpAndSettle();

        // Label turns WHITE
        labelText = tester.widget<Text>(labelFinder);
        expect(labelText.style?.color, equals(Colors.white));

        // Border turns WHITE
        container = tester.widget<AnimatedContainer>(containerFinder);
        dec = container.decoration as BoxDecoration;
        border = dec.border as Border;
        expect(border.top.color, equals(Colors.white));
      },
    );
  });
}
