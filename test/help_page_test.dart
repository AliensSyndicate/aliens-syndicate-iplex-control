import 'package:aliens_syndicate_iplex_control/core/config/features.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/help/help_content.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/help/help_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, [Locale locale = const Locale('pt')]) =>
    tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const HelpPage(),
      ),
    );

void main() {
  test('every language has the same topics and questions', () {
    final pt = helpTopics('pt'), en = helpTopics('en'), es = helpTopics('es');
    expect(en.length, pt.length);
    expect(es.length, pt.length);
    for (var i = 0; i < pt.length; i++) {
      expect(en[i].items.length, pt[i].items.length, reason: pt[i].title);
      expect(es[i].items.length, pt[i].items.length, reason: pt[i].title);
    }
    expect(helpTopics('fr'), same(en));
  });

  testWidgets('tapping a question opens its answer below and closes it', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    const question = 'O iPlex fornece canais ou listas IPTV?';
    final answer = helpTopics('pt')
        .expand((t) => t.items)
        .firstWhere((i) => i.question == question)
        .answer;
    expect(find.text(answer), findsNothing);

    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.text(answer), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(answer)).dy,
      greaterThan(tester.getTopLeft(find.text(question)).dy),
    );

    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.text(answer), findsNothing);
  });

  testWidgets('filter matches questions and answers, ignoring accents', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const Key('help-filter')),
      matching: find.byType(EditableText),
    );

    // "pin pessoal" only appears in the personal PIN question.
    await tester.enterText(field, 'pin pessoal');
    await tester.pumpAndSettle();
    expect(find.text('O que é o PIN pessoal?'), findsOneWidget);
    expect(find.text('Como vinculo minha TV?'), findsNothing);

    // Matches inside an answer, without accents: "criptografados".
    await tester.enterText(field, 'criptografados');
    await tester.pumpAndSettle();
    expect(find.text('Minha senha IPTV fica segura?'), findsOneWidget);

    await tester.enterText(field, 'familia');
    await tester.pumpAndSettle();
    expect(find.text('O que é a família?'), findsOneWidget);

    await tester.enterText(field, 'zzzz inexistente');
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma resposta encontrada'), findsOneWidget);
  });

  test('Kids profiles hidden: no Kids answers or mentions in any language', () {
    for (final code in ['pt', 'en', 'es']) {
      final text = [
        for (final t in helpTopics(code)) ...[
          t.title,
          for (final i in t.items) ...[i.question, i.answer],
        ],
      ].join(' ');
      expect(
        RegExp(r'infantil|kids|child', caseSensitive: false).hasMatch(text),
        isFalse,
        reason: code,
      );
    }
  }, skip: Features.kidsProfiles);

  testWidgets('English locale shows the English questions', (tester) async {
    await _pump(tester, const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('What is iPlex?'), findsOneWidget);
    expect(find.text('Help & support'), findsWidgets);
  });
}
