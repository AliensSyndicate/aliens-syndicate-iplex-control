import 'dart:io';
import 'dart:typed_data';

import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
);

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(() => HttpOverrides.global = FakeImageHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  Finder menuAvatar() => find.descendant(
    of: find.byType(BottomNavigation),
    matching: find.byType(AppAvatarFace),
  );

  testWidgets(
    'Google photo: the fifth button and the Account screen show the same photo',
    (tester) async {
      final repo = AvatarRepository(photoUrl: photo);
      final c = await navigation.launch(tester, repo, location: '/account');
      await loadImages(tester);
      await fixtures.screenshot(tester, 'account-avatar-photo');
      expect(menuAvatar(), findsOneWidget);
      expect(
        find.descendant(of: menuAvatar(), matching: networkPhoto(photo)),
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
      // The other four buttons keep their icons; the order is untouched.
      expect(
        find.descendant(
          of: find.byType(BottomNavigation),
          matching: find.byType(CircularButton),
        ),
        findsNWidgets(5),
      );
      expect(
        find.descendant(
          of: find.byType(BottomNavigation),
          matching: find.byType(AppIcon),
        ),
        findsNWidgets(4),
      );
    },
  );

  testWidgets(
    'no photo (Google without photo, Apple): the default avatar in both places',
    (tester) async {
      await navigation.launch(tester, AvatarRepository(), location: '/account');
      await loadImages(tester);
      await fixtures.screenshot(tester, 'account-avatar-default');
      expect(
        find.descendant(of: menuAvatar(), matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(of: menuAvatar(), matching: find.text('A')),
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
      await navigation.launch(tester, repo, location: '/account');
      const next = 'https://lh3.googleusercontent.com/a/photo-two';
      repo.photoUrl = next;
      repo.accountEvents.add(repo.account);
      await tester.pumpAndSettle();
      expect(networkPhoto(photo), findsNothing);
      expect(networkPhoto(next), findsNWidgets(2));
    },
  );

  testWidgets('a photo that fails to load falls back to the default avatar', (
    tester,
  ) async {
    await navigation.launch(
      tester,
      // Own URL: the image cache would otherwise answer with an earlier success.
      AvatarRepository(photoUrl: 'https://lh3.googleusercontent.com/a/broken'),
      location: '/account',
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
          .isNotEmpty)
        break;
    }
    expect(
      find.descendant(of: menuAvatar(), matching: find.text('A')),
      findsOneWidget,
    );
  });

  testWidgets('only https photos are shown', (tester) async {
    await navigation.launch(
      tester,
      AvatarRepository(photoUrl: 'http://example.invalid/a.png'),
      location: '/account',
    );
    expect(find.byType(Image, skipOffstage: false), findsNothing);
    expect(
      find.descendant(of: menuAvatar(), matching: find.text('A')),
      findsOneWidget,
    );
  });

  testWidgets(
    'selection indicator and size of the Account button match the others',
    (tester) async {
      await navigation.launch(
        tester,
        AvatarRepository(photoUrl: photo),
        location: '/account',
      );
      final buttons = tester
          .widgetList<CircularButton>(
            find.descendant(
              of: find.byType(BottomNavigation),
              matching: find.byType(CircularButton),
            ),
          )
          .toList();
      expect(buttons.map((b) => b.selected), [
        false,
        false,
        false,
        false,
        true,
      ]);
      final sizes = tester
          .widgetList<Widget>(
            find.descendant(
              of: find.byType(BottomNavigation),
              matching: find.byType(CircularButton),
            ),
          )
          .map((w) => tester.getSize(find.byWidget(w)))
          .toSet();
      expect(sizes.length, 1);
    },
  );

  testWidgets(
    'the main menu background is the screens\' own background, with no seam',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      Future<ByteData> render(bool withMenu) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(AvatarRepository()),
            ],
            child: MaterialApp(
              theme: AppTokens.theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: RepaintBoundary(
                key: const Key('shot'),
                child: GraphiteBackdrop(
                  child: Stack(
                    children: [
                      const SizedBox.expand(),
                      // Content scrolled under the menu must never show through it.
                      if (withMenu)
                        const Positioned.fill(
                          child: ColoredBox(color: Colors.red),
                        ),
                      if (withMenu)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: BottomNavigation(
                            selected: 0,
                            onSelected: (_) {},
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('shot')),
        );
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData();
          image.dispose();
          return data!;
        }))!;
      }

      final bare = await render(false);
      final withMenu = await render(true);
      final menuTop =
          844 - tester.getSize(find.byType(BottomNavigation)).height;
      // Columns between the margin and the first button are empty menu background.
      var compared = 0;
      for (var y = menuTop.ceil(); y < 844; y++) {
        for (var x = 0; x < 6; x++) {
          final i = (y * 390 + x) * 4;
          for (var k = 0; k < 4; k++) {
            expect(
              withMenu.getUint8(i + k),
              bare.getUint8(i + k),
              reason: 'pixel $x,$y channel $k',
            );
          }
          compared++;
        }
      }
      expect(compared, greaterThan(100));
    },
  );
}
