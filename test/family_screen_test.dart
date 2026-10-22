import 'dart:async';
import 'dart:io';

import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'navigation_test.dart' as navigation;
import 'support/fake_network_image.dart';
import 'widget_test.dart' as fixtures;

/// Family tab fixture: the entries the Firebase repository would stream.
class FamilyRepository extends navigation.SessionRepository {
  FamilyRepository({super.administrator = true})
    : super(uid: 'u', linked: true);
  List<Entry> members = [
    Entry('u', {
      'name': 'Account',
      'role': 'admin',
      'photoUrl': 'https://lh3.googleusercontent.com/a/admin',
    }),
  ];
  List<Entry> sent = [], received = [];
  bool membersFailure = false;
  Completer<List<Entry>>? pendingMembers;
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) async* {
    switch (collection) {
      case 'members':
        if (membersFailure) throw const AppFailure('unavailable');
        yield pendingMembers == null ? members : await pendingMembers!.future;
      case 'sentInvitations':
        yield sent;
      case 'invitations':
        yield received;
      default:
        yield [
          if (collection == 'profiles')
            Entry('admin', {'name': 'Account', 'type': 'admin'}),
        ];
    }
  }
}

final soon = DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch;

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(() => HttpOverrides.global = FakeImageHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  testWidgets(
    'administrator alone: the member list directly, like Devices and IPTV',
    (tester) async {
      final repo = FamilyRepository();
      final c = await navigation.launch(tester, repo, location: '/users');
      // The account that created the family is a member: no empty state.
      expect(find.byKey(const ValueKey('member-u')), findsOneWidget);
      expect(find.text('No additional members yet.'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Add members'), findsNothing);
      expect(find.text('Create a family'), findsNothing);
      await loadImages(tester);
      await fixtures.screenshot(tester, 'family-alone');
      // Adding: the "+" of the top bar → Invite.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CircularButton && w.icon == AppIcons.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-profile')), findsNothing);
      expect(find.byType(AppModalSheet), findsNothing);
      expect(navigation.path(c), '/users/invite');
    },
  );

  testWidgets(
    'administrator with members: avatar, name, role and pending invitations',
    (tester) async {
      final repo = FamilyRepository()
        ..members = [
          ...FamilyRepository().members,
          Entry('m1', {
            'name': 'Sam',
            'role': 'member',
            'photoUrl': 'https://lh3.googleusercontent.com/a/sam',
          }),
        ]
        ..sent = [
          Entry('r1', {
            'recipientName': 'Robin',
            'expiresAt': soon,
            'status': 'pending',
          }),
          Entry('r0', {'recipientName': 'Old', 'expiresAt': 1}),
        ];
      final c = await navigation.launch(tester, repo, location: '/users');
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Sam'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('member-u')),
          matching: find.text('Administrator'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('member-m1')),
          matching: find.text('Member'),
        ),
        findsOneWidget,
      );
      expect(find.text('Robin'), findsOneWidget);
      expect(
        find.text('Old'),
        findsNothing,
        reason: 'expired invitations are not listed',
      );
      expect(find.text('Invitation pending'), findsOneWidget);
      expect(find.byType(AppAvatar), findsNWidgets(3));
      expect(find.byKey(const Key('parental-control')), findsOneWidget);
      await loadImages(tester);
      await fixtures.screenshot(tester, 'family-members');
      // The administrator's own entry has no management; a member opens its detail.
      await tester.tap(find.widgetWithText(EntryTile, 'Sam'));
      await tester.pumpAndSettle();
      expect(navigation.path(c), '/users/member/m1');
    },
  );

  testWidgets(
    'a pending invitation is cancelled by the administrator after confirmation',
    (tester) async {
      final repo = FamilyRepository()
        ..sent = [
          Entry('r1', {'recipientName': 'Robin', 'expiresAt': soon}),
        ];
      await navigation.launch(tester, repo, location: '/users');
      await tester.tap(find.widgetWithText(EntryTile, 'Robin'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel invitation'), findsWidgets);
      await tester.tap(find.widgetWithText(AppButton, 'Cancel invitation'));
      await tester.pumpAndSettle();
      expect(
        repo.mutationPayloads.any(
          (m) => m.$1 == 'cancelMembershipRequest' && m.$2['id'] == 'r1',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'a member: no administrative actions, only its own entry opens (to leave)',
    (tester) async {
      final repo = FamilyRepository(administrator: false)
        ..members = [
          Entry('admin', {'name': 'Dana', 'role': 'admin'}),
          Entry('u', {'name': 'Account', 'role': 'member'}),
          Entry('m2', {'name': 'Pat', 'role': 'member'}),
        ];
      final c = await navigation.launch(tester, repo, location: '/users');
      expect(find.widgetWithText(AppButton, 'Add members'), findsNothing);
      expect(find.byKey(const Key('parental-control')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PageTemplate),
          matching: find.byIcon(Icons.add),
        ),
        findsNothing,
      );
      expect(find.text('Dana'), findsOneWidget);
      expect(find.text('Pat'), findsOneWidget);
      await tester.tap(find.widgetWithText(EntryTile, 'Pat'));
      await tester.pumpAndSettle();
      expect(
        navigation.path(c),
        '/users',
        reason: 'other members are read-only',
      );
      await tester.tap(find.byKey(const ValueKey('member-u')));
      await tester.pumpAndSettle();
      expect(navigation.path(c), '/users/member/u');
    },
  );

  testWidgets('a received invitation is decided by the invitee', (
    tester,
  ) async {
    final repo = FamilyRepository()
      ..received = [
        Entry('inv', {'familyName': 'Silva', 'status': 'pending'}),
      ];
    await navigation.launch(tester, repo, location: '/users');
    expect(find.text('Silva'), findsOneWidget);
    await tester.tap(find.widgetWithText(EntryTile, 'Silva'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Accept'));
    await tester.pumpAndSettle();
    expect(
      repo.mutationPayloads.any(
        (m) =>
            m.$1 == 'respondMembership' &&
            m.$2['id'] == 'inv' &&
            m.$2['accept'] == true,
      ),
      isTrue,
    );
  });

  testWidgets('member cards: on / off and the date it was last on', (
    tester,
  ) async {
    final recent = DateTime.now().subtract(const Duration(minutes: 1));
    final repo = FamilyRepository()
      ..members = [
        ...FamilyRepository().members,
        Entry('m1', {
          'name': 'Sam',
          'role': 'member',
          'lastActiveAt': recent.millisecondsSinceEpoch,
        }),
        Entry('m2', {
          'name': 'Lia',
          'role': 'member',
          'lastActiveAt': DateTime(2026, 1, 2, 10, 30).millisecondsSinceEpoch,
        }),
        Entry('m3', {'name': 'Noa', 'role': 'member'}),
      ];
    await navigation.launch(tester, repo, location: '/users');
    Color? dot(String id) => tester
        .widget<NeumorphicStatusIndicator>(
          find.descendant(
            of: find.byKey(ValueKey('member-$id')),
            matching: find.byType(NeumorphicStatusIndicator),
          ),
        )
        .color;
    // The account using the app is on; Sam reported a minute ago.
    expect(dot('u'), AppColors.statusOn);
    expect(dot('m1'), AppColors.statusOn);
    // Lia: off, with the last time on; Noa never was.
    expect(dot('m2'), AppColors.disabled);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('member-m2')),
        matching: find.text('1/2/2026 10:30'),
      ),
      findsOneWidget,
    );
    expect(dot('m3'), AppColors.disabled);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('member-m3')),
        matching: find.text('Never on'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('while loading, the page frame stays and a skeleton shows', (
    tester,
  ) async {
    final pending = Completer<List<Entry>>();
    final loading = FamilyRepository()..pendingMembers = pending;
    await navigation.launch(tester, loading, location: '/users', settle: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AppLoadingSkeleton), findsWidgets);
    expect(find.text('Family'), findsWidgets);
    pending.complete(loading.members);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('member-u')), findsOneWidget);
  });

  testWidgets('a failing member stream shows the error state with retry', (
    tester,
  ) async {
    final failing = FamilyRepository()..membersFailure = true;
    await navigation.launch(tester, failing, location: '/users');
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Family'), findsWidgets);
  });

  for (final size in const [Size(320, 640), Size(390, 844), Size(768, 1024)]) {
    testWidgets(
      'family screen fits ${size.width.toInt()}x${size.height.toInt()} without overflow',
      (tester) async {
        final repo = FamilyRepository()
          ..members = [
            ...FamilyRepository().members,
            Entry('m1', {
              'name': 'A very long member name that must wrap',
              'role': 'member',
            }),
          ];
        await navigation.launch(tester, repo, location: '/users');
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('very long'), findsOneWidget);
      },
    );
  }
}
