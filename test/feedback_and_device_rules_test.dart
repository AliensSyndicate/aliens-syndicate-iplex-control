import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_add_page.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/presentation/controllers/iptv_sync_controller.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/public_identity_sheet.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildApp({required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pt', 'BR'),
        theme: AppTheme.darkTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'DeviceAddPage does not have AppSurface card or TV icon container',
    (tester) async {
      await tester.pumpWidget(buildApp(child: const DeviceAddPage()));
      await tester.pumpAndSettle();

      // AppSurface should NOT be used on DeviceAddPage
      expect(
        find.descendant(
          of: find.byType(DeviceAddPage),
          matching: find.byType(AppSurface),
        ),
        findsNothing,
      );

      // TV icon should NOT be present on DeviceAddPage
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.icon == AppIcons.devices,
        ),
        findsNothing,
      );

      // Instructions and buttons remain intact
      expect(find.text('Como conectar sua TV'), findsOneWidget);
      expect(find.text('Ler QR Code'), findsOneWidget);
      expect(find.text('Digitar código manualmente'), findsOneWidget);
    },
  );

  testWidgets('showDeviceConnectionFailure displays a SnackBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDeviceConnectionFailure(
              context,
              const AppFailure('invalid-token'),
            ),
            child: const Text('Trigger Error'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trigger Error'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(AppModalSheet), findsNothing);
  });

  testWidgets('showFailure displays an AppModalSheet instead of SnackBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showFailure(context, const AppFailure('permission-denied')),
            child: const Text('Trigger Failure'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trigger Failure'));
    await tester.pumpAndSettle();

    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('showPublicIdentity displays user public code and QR code', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPublicIdentity(context, 'A7K9M2P4X8Q3'),
            child: const Text('Show QR'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show QR'));
    await tester.pumpAndSettle();

    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(find.text('A7K9M2P4X8Q3'), findsOneWidget);
    expect(find.text('Copiar código'), findsOneWidget);

    await tester.tap(find.text('Copiar código'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Código copiado'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'pairing and IPTV backend codes keep their specific localized messages',
    (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        buildApp(
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final l = AppLocalizations.of(captured);
      expect(
        failureText(captured, const AppFailure('pairing-expired')),
        l.pairingExpired,
      );
      expect(
        failureText(
          captured,
          const AppFailure('device-already-linked-elsewhere'),
        ),
        l.deviceLinkedElsewhere,
      );
      expect(
        failureText(captured, const AppFailure('invalid-token')),
        l.invalidCode,
      );
      for (final entry in {
        'catalog-publication-failed': l.errorCatalogPublicationFailed,
        'invalid-epg': l.errorInvalidEpg,
        'catalog-integrity': l.errorCatalogIntegrity,
        'worker-retries-exhausted': l.errorWorkerRetriesExhausted,
        'source-secret-unavailable': l.errorSourceSecretUnavailable,
        'provider-unavailable': l.errorCannotConnect,
      }.entries) {
        expect(
          mapIptvErrorCodeToMessage(captured, entry.key),
          entry.value,
          reason: entry.key,
        );
        expect(
          entry.value,
          isNot(l.errorTemporaryProcessing),
          reason: entry.key,
        );
      }
    },
  );
}
