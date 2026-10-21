import 'dart:io';

import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/devices_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/settings_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_details_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_form.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/list_iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_network_image.dart';
import 'widget_test.dart' as fixtures;

/// Data exists only in this test, to inspect real widgets in populated states.
class VisualRepository extends fixtures.TestRepository {
  VisualRepository({this.emptySources = false}) : super(signedIn: true);
  final bool emptySources;
  final tv = Entry('tv', {
    'name': 'Living room',
    'onlineUntil': DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
    'sessionId': 'test-session',
  });
  final source = Entry('s', {
    'name': 'Premiere HD',
    'host': 'iptv.provider.example',
    'format': 'm3u',
    'status': 'ready',
    'count': 350,
    'lastSyncAt': DateTime.now().millisecondsSinceEpoch,
  });
  @override
  Stream<Account?> watchAccount(String uid) => Stream.value(
    Account(
      uid: uid,
      name: 'Alex',
      email: 'alex@example.invalid',
      familyId: 'f',
      photoUrl: 'https://lh3.googleusercontent.com/a/visual',
    ),
  );
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      Stream.value(switch (collection) {
        'devices' => [
          tv,
          Entry('tv2', {'name': 'Bedroom', 'onlineUntil': 0}),
        ],
        'members' => [
          Entry('u', {
            'name': 'Alex',
            'role': 'admin',
            'photoUrl': 'https://lh3.googleusercontent.com/a/visual',
          }),
          Entry('member', {'name': 'Sam', 'role': 'member'}),
        ],
        'profiles' => [
          Entry('p1', {'name': 'Alex'}),
          Entry('p2', {'name': 'Family'}),
        ],
        'sources' => emptySources ? <Entry>[] : [source],
        _ => [],
      });
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      Stream.value(
        collection == 'devices'
            ? tv
            : (collection == 'sources' && !emptySources ? source : null),
      );
}

void main() {
  setUpAll(fixtures.loadTestFont);
  setUp(() => HttpOverrides.global = FakeImageHttpOverrides());
  tearDown(() => HttpOverrides.global = null);
  final pages = <({String name, Widget page, int? tab})>[
    (name: 'home', page: const HomePage(), tab: 0),
    (name: 'users', page: const UsersPage(), tab: 1),
    (name: 'devices', page: const DevicesPage(), tab: 2),
    (name: 'iptv', page: const ListIptvPage(), tab: 3),
    (
      name: 'source-detail',
      page: const IptvSourceDetailsPage(id: 's'),
      tab: null,
    ),
    (name: 'account', page: const AccountPage(), tab: 4),
    (name: 'settings', page: const SettingsPage(), tab: null),
    (name: 'source-form', page: const IptvSourceForm(), tab: null),
  ];
  for (final page in pages) {
    testWidgets('graphite ${page.name} at phone size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        fixtures.host(
          Scaffold(
            body: page.page,
            bottomNavigationBar: page.tab == null
                ? null
                : BottomNavigation(selected: page.tab!, onSelected: (_) {}),
          ),
          repo: VisualRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await loadImages(tester);
      expect(tester.takeException(), null);
      await fixtures.screenshot(tester, page.name);
    });
  }
  testWidgets('graphite iptv-empty at phone size', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      fixtures.host(
        Scaffold(
          body: const ListIptvPage(),
          bottomNavigationBar: BottomNavigation(
            selected: 3,
            onSelected: (_) {},
          ),
        ),
        repo: VisualRepository(emptySources: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await fixtures.screenshot(tester, 'iptv-empty');
  });
}
