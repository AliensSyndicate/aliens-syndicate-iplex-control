import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/about/about_content.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/about/about_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

/// Records the payloads and can list other members in the family.
class _AccountRepository extends fixtures.TestRepository {
  _AccountRepository({this.otherMembers = false}) : super(signedIn: true);
  final bool otherMembers;
  final payloads = <Map<String, dynamic>>[];
  var deletions = 0;
  bool passwordAccount = false;
  String? reauthPassword;

  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      Stream.value(
        collection == 'members'
            ? [
                Entry('u', {'role': 'admin', 'name': 'Test account'}),
                if (otherMembers) Entry('m', {'role': 'member', 'name': 'Ana'}),
              ]
            : [],
      );

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) {
    payloads.add({'action': action, ...payload});
    return super.mutate(action, payload);
  }

  @override
  bool get signedInWithPassword => passwordAccount;

  @override
  Future<void> reauthenticate(String password) async =>
      reauthPassword = password;

  @override
  Future<void> deleteAccount() async => deletions++;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no "My profile" entry and every entry has its own icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.host(const AccountPage(), repo: _AccountRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsNothing);
    final icons = tester
        .widgetList<EntryTile>(find.byType(EntryTile))
        .map((t) => t.icon)
        .toList();
    expect(icons.toSet().length, icons.length);
  });

  testWidgets('language opens a list and saves the chosen option', (
    tester,
  ) async {
    final repo = _AccountRepository();
    await tester.pumpWidget(fixtures.host(const AccountPage(), repo: repo));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsNothing);

    await _tap(tester, find.byKey(const Key('account-language')));
    expect(find.byKey(const Key('language-option-es')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('language-option-es')));

    expect(repo.payloads.last, {'action': 'savePreferences', 'locale': 'es'});
    expect(find.byKey(const Key('language-option-es')), findsNothing);
  });

  testWidgets('administrator with members is told before any new login', (
    tester,
  ) async {
    final repo = _AccountRepository(otherMembers: true);
    await tester.pumpWidget(fixtures.host(const AccountPage(), repo: repo));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Delete account'));
    expect(repo.deletions, 0);
    expect(find.text('Remove'), findsNothing, reason: 'no confirmation sheet');
  });

  testWidgets('social account confirms and deletes without a password', (
    tester,
  ) async {
    final repo = _AccountRepository();
    await tester.pumpWidget(fixtures.host(const AccountPage(), repo: repo));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Delete account'));
    await _tap(tester, find.text('Remove'));
    expect(repo.deletions, 1);
    expect(repo.reauthPassword, isNull);
  });

  testWidgets('e-mail account asks for the password before deleting', (
    tester,
  ) async {
    final repo = _AccountRepository()..passwordAccount = true;
    await tester.pumpWidget(fixtures.host(const AccountPage(), repo: repo));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Delete account'));
    await _tap(tester, find.text('Remove'));
    // A fresh login with the password comes before the deletion.
    expect(repo.deletions, 0);
    await tester.enterText(find.byKey(const Key('delete-password')), 'secret1');
    await tester.pump();
    // The focused field's cursor keeps blinking: no settle before the tap.
    await tester.tap(
      find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.widgetWithText(AppButton, 'Delete account'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.reauthPassword, 'secret1');
    expect(repo.deletions, 1);
  });

  testWidgets('about page shows the iPlex information', (tester) async {
    await tester.pumpWidget(fixtures.host(const AboutPage()));
    await tester.pumpAndSettle();
    final content = aboutContent('en');
    expect(find.text(content.tagline), findsOneWidget);
    expect(find.text('Aliens Syndicate Inc.'), findsOneWidget);
    expect(find.text(content.versionTitle), findsOneWidget);
    for (final (title, _) in content.sections) {
      await tester.ensureVisible(find.text(title));
      expect(find.text(title), findsOneWidget);
    }
  });

  test('about content exists in every language', () {
    for (final code in ['pt', 'en', 'es']) {
      expect(aboutContent(code).sections.length, 6, reason: code);
    }
  });
}
