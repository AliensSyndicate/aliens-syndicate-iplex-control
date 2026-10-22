import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The source page shows the real sync result: specific failure, technical
/// reason, automatic retry and counts per content type (no generic message).
Widget _page(Entry entry) => ProviderScope(
  key: ValueKey(entry.data.toString()),
  overrides: [
    entryProvider((collection: 'sources', id: entry.id))
        .overrideWith((ref) => Stream.value(entry)),
    canManageIptvProvider.overrideWithValue(false),
  ],
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: IptvPage(id: entry.id),
  ),
);

void main() {
  setUp(() {});
  testWidgets(
    'final failure: specific message, technical detail, previous catalog kept',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _page(
          Entry('s1', const {
            'name': 'Lista',
            'format': 'xtream',
            'status': 'error',
            'errorCode': 'invalid-credentials',
            'errorReason': 'xtream-auth-empty',
            'version': 'abc',
            'count': 6,
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Credenciais inválidas. O catálogo anterior foi preservado.'),
        findsOneWidget,
      );
      expect(find.text('Detalhe técnico: xtream-auth-empty'), findsOneWidget);
      expect(find.text('Falha'), findsOneWidget);
    },
  );

  testWidgets('retryable failure: shown as automatic retry, not as failure', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _page(
        Entry('s2', const {
          'name': 'Lista',
          'format': 'm3u',
          'status': 'queued',
          'errorCode': 'provider-unavailable',
          'errorReason': 'connection-failed',
        }),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nova tentativa automática em breve'), findsOneWidget);
    expect(find.text('Falha'), findsNothing);
    expect(find.text('Não foi possível conectar ao servidor.'), findsOneWidget);
    expect(find.text('Detalhe técnico: connection-failed'), findsOneWidget);
  });

  testWidgets('ready: totals per content type from the last real sync', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _page(
        Entry('s3', const {
          'name': 'Lista',
          'format': 'm3u',
          'status': 'ready',
          'enabled': true,
          'count': 5,
          'channelCount': 2,
          'movieCount': 2,
          'seriesCount': 1,
          'version': 'v',
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 ao vivo · 2 filmes · 1 séries'), findsOneWidget);
    expect(find.byKey(const Key('source-error-message')), findsNothing);
  });
}
