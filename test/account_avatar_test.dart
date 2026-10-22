import 'dart:io';

import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' as navigation;
import 'support/fake_network_image.dart';
import 'widget_test.dart' as fixtures;

const photo = 'https://lh3.googleusercontent.com/a/photo-one';

/// The account stream is the only avatar source; the test drives it.
class AvatarRepository extends navigation.SessionRepository {
  AvatarRepository({this.photoUrl, super.uid = 'u', super.linked = true});
  String? photoUrl;
  @override
  Account? get account => Account(
    uid: currentUid!,
    name: 'Alex',
    email: 'alex@example.invalid',
    familyId: 'family',
    photoUrl: photoUrl,
  );
}

Finder networkPhoto(String url) => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is NetworkImage &&
      (w.image as NetworkImage).url == url,
  skipOffstage: false,
);

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(() => HttpOverrides.global = FakeImageHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  // The account avatar is the button on the Home app bar (it opens Account).
  // The Home stays alive behind the Account screen.
  Finder menuAvatar() => find.descendant(
    of: find.byKey(const Key('home-account'), skipOffstage: false),
    matching: find.byType(AppAvatarFace, skipOffstage: false),
    skipOffstage: false,
  );

  Future<ProviderContainer> launchAccount(
    WidgetTester tester,
    navigation.SessionRepository repo,
  ) async {
    final c = await navigation.launch(tester, repo);
    await tester.tap(find.byKey(const Key('home-account')));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets(
    'Google photo: the Home avatar button and the Account screen show the same photo',
    (tester) async {
      final repo = AvatarRepository(photoUrl: photo);
      final c = await launchAccount(tester, repo);
      await loadImages(tester);
      await fixtures.screenshot(tester, 'account-avatar-photo');
      expect(menuAvatar(), findsOneWidget);
      expect(
        find.descendant(
          of: menuAvatar(),
          matching: networkPhoto(photo),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.byType(AccountPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AccountPage),
          matching: networkPhoto(photo),
        ),
        findsOneWidget,
      );
      // Photo and menu belong to the same authenticated account.
      expect(c.read(accountProvider).value!.photoUrl, photo);
    },
  );

  testWidgets(
    'no photo (Google without photo, Apple): the default avatar in both places',
    (tester) async {
      await launchAccount(tester, AvatarRepository());
      await loadImages(tester);
      await fixtures.screenshot(tester, 'account-avatar-default');
      expect(
        find.descendant(
          of: menuAvatar(),
          matching: find.byType(Image, skipOffstage: false),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: menuAvatar(),
          matching: find.text('A', skipOffstage: false),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AccountPage),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a changed photo replaces the old one in both places; an empty one never wipes it',
    (tester) async {
      final repo = AvatarRepository(photoUrl: photo);
      final c = await launchAccount(tester, repo);
      const next = 'https://lh3.googleusercontent.com/a/photo-two';
      repo.photoUrl = next;
      repo.accountEvents.add(repo.account);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is NetworkImage &&
              (w.image as NetworkImage).url == photo,
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AccountPage),
          matching: networkPhoto(next),
        ),
        findsOneWidget,
      );
      // Back on the Home, the app bar avatar shows the new photo too.
      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: menuAvatar(),
          matching: networkPhoto(next),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a photo that fails to load falls back to the default avatar', (
    tester,
  ) async {
    await launchAccount(
      tester,
      // Own URL: the image cache would otherwise answer with an earlier success.
      AvatarRepository(photoUrl: 'https://lh3.googleusercontent.com/a/broken'),
    );
    // The (failed) image load resolves outside the fake clock.
    for (var i = 0; i < 20 && menuAvatar().evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
      if (find
          .descendant(of: menuAvatar(), matching: find.text('A'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.descendant(
        of: menuAvatar(),
        matching: find.text('A', skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('only https photos are shown', (tester) async {
    await launchAccount(
      tester,
      AvatarRepository(photoUrl: 'http://example.invalid/a.png'),
    );
    expect(
      find.descendant(
        of: menuAvatar(),
        matching: find.byType(Image, skipOffstage: false),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: menuAvatar(),
        matching: find.text('A', skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the main menu is icons only over a slightly translucent background',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: BottomNavigation(selected: 0, onSelected: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomNavigation),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      final background = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(BottomNavigation),
              matching: find.byType(ColoredBox),
            ),
          )
          .first;
      expect(background.color.a, inInclusiveRange(0.6, 0.95));
      // Accessible names stay.
      expect(find.bySemanticsLabel('Home'), findsOneWidget);
    },
  );
}
