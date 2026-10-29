import 'package:aliens_syndicate_iplex_control/core/config/features.dart';

import 'dart:async';

import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

class InviteRepository extends navigation.SessionRepository {
  InviteRepository({super.administrator = true})
    : super(uid: 'u', linked: true);
  Completer<void>? pending;

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    await super.mutate(action, payload);
    if (action == 'lookupPublicUser') {
      await pending?.future;
      return {'name': 'Lia', 'code': 'A7K9M2P4X8Q3'};
    }
    return {};
  }
}

void main() {
  setUpAll(fixtures.loadTestFont);

  for (final kids in [false, true]) {
    testWidgets(
      'direct add member sends ${kids ? "kids" : "regular"} invitation',
      (tester) async {
        final repo = InviteRepository();
        final c = await navigation.launch(tester, repo, location: '/users');
        await tester.tap(find.byKey(const Key('add-member-button')));
        await tester.pumpAndSettle();
        expect(navigation.path(c), '/users/invite');
        expect(find.byType(AppModalSheet), findsNothing);
        expect(find.text('Add member'), findsOneWidget);
        final toggle = find.byKey(const Key('kids-account-toggle'));
        // Kids profiles hidden (no children's content yet): no toggle.
        if (!Features.kidsProfiles) expect(toggle, findsNothing);
        if (kids) {
          expect(tester.widget<NeumorphicSwitchTile>(toggle).value, isFalse);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextFormField), 'A7K9M2P4X8Q3');
        await tester.tap(find.widgetWithText(AppButton, 'Search your catalog'));
        await tester.pumpAndSettle();
        if (kids) {
          expect(tester.widget<NeumorphicSwitchTile>(toggle).value, isTrue);
        }
        expect(find.text('Lia'), findsOneWidget);
        final send = find.widgetWithText(AppButton, 'Request membership');
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(
          repo.mutationPayloads
              .where((m) => m.$1 == 'requestMembership')
              .single
              .$2,
          {
            'code': 'A7K9M2P4X8Q3',
            'familyId': 'family',
            'profileType': kids ? 'kids' : 'regular',
          },
        );
        expect(navigation.path(c), '/users');
      },
      // Kept for when Kids profiles come back.
      skip: kids && !Features.kidsProfiles,
    );
  }

  testWidgets('classification is disabled during lookup', (tester) async {
    final repo = InviteRepository()..pending = Completer<void>();
    await navigation.launch(tester, repo, location: '/users/invite');
    await tester.enterText(find.byType(TextFormField), 'A7K9M2P4X8Q3');
    await tester.tap(find.widgetWithText(AppButton, 'Search your catalog'));
    await tester.pump();
    expect(
      tester
          .widget<NeumorphicSwitchTile>(
            find.byKey(const Key('kids-account-toggle')),
          )
          .disabled,
      isTrue,
    );
    repo.pending!.complete();
    await tester.pumpAndSettle();
  }, skip: !Features.kidsProfiles);

  testWidgets('members cannot open add member through a direct route', (
    tester,
  ) async {
    final repo = InviteRepository(administrator: false);
    final c = await navigation.launch(tester, repo, location: '/users/invite');
    expect(navigation.path(c), isNot('/users/invite'));
    expect(find.byKey(const Key('kids-account-toggle')), findsNothing);
    expect(
      repo.mutationPayloads.where((m) => m.$1 == 'requestMembership'),
      isEmpty,
    );
  });
}
