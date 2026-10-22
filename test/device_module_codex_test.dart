import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models/device_model.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/domain/entities/device_entity.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/domain/entities/pairing_session_entity.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/controllers/device_controller.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_add_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_confirm_pairing_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_manual_code_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_pairing_success_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/widgets/device_card.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildTestApp({
  required Widget child,
  List<dynamic> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      locale: const Locale('pt'),
      theme: AppTokens.theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('CODEX — Device Module Domain & Entity Tests', () {
    test(
      '1. DeviceModel serialization and deserialization retains all fields',
      () {
        final now = DateTime.now();
        final model = DeviceModel(
          id: 'dev_test1234567890abcdef',
          familyId: 'fam_abc',
          displayName: 'Living Room TV',
          platform: 'tizen',
          status: 'linked',
          manufacturer: 'Samsung',
          model: 'QN90B',
          nativeIdentityFingerprint: 'tiz_1a2b3c4d',
          identitySource: 'tizen_duid_api',
          identityScope: 'vendor_scoped',
          identityStability: 'hardware_stable',
          onlineUntil: now.add(const Duration(minutes: 5)),
          sessionId: 'sess_1',
          linkedAt: now,
          lastSeenAt: now,
        );

        final map = model.toMap();
        final restored = DeviceModel.fromMap(model.id, map);

        expect(restored.id, model.id);
        expect(restored.displayName, 'Living Room TV');
        expect(restored.platform, 'tizen');
        expect(restored.platformLabel, 'Samsung Tizen');
        expect(restored.manufacturer, 'Samsung');
        expect(restored.model, 'QN90B');
        expect(restored.maskedId, 'dev_••••cdef');
        expect(restored.isOnline(now), isTrue);
        expect(
          restored.isOnline(now.add(const Duration(minutes: 10))),
          isFalse,
        );
      },
    );

    test(
      '2. DeviceEntity platformLabel maps android_tv, tizen, webos correctly',
      () {
        const androidTv = DeviceEntity(
          id: '1',
          familyId: 'f',
          displayName: 'TV 1',
          platform: 'android_tv',
        );
        const tizen = DeviceEntity(
          id: '2',
          familyId: 'f',
          displayName: 'TV 2',
          platform: 'tizen',
        );
        const webos = DeviceEntity(
          id: '3',
          familyId: 'f',
          displayName: 'TV 3',
          platform: 'webos',
        );

        expect(androidTv.platformLabel, 'Android TV');
        expect(tizen.platformLabel, 'Samsung Tizen');
        expect(webos.platformLabel, 'LG webOS');
      },
    );

    test('3. PairingSessionEntity parses session from backend correctly', () {
      final session = PairingSessionEntity.fromMap({
        'token': 'tok_123',
        'deviceId': 'dev_canonical_9999',
        'displayName': 'Bedroom TV',
        'platform': 'webos',
        'manufacturer': 'LG',
        'model': 'OLED65C2',
        'nativeIdentityMasked': 'dev_••••9999',
        'fingerprint': 'web_abcdef',
        'isAlreadyLinked': false,
        'isSameFamily': false,
      });

      expect(session.token, 'tok_123');
      expect(session.deviceId, 'dev_canonical_9999');
      expect(session.displayName, 'Bedroom TV');
      expect(session.platform, 'webos');
      expect(session.platformLabel, 'LG webOS');
      expect(session.manufacturer, 'LG');
      expect(session.model, 'OLED65C2');
      expect(session.nativeIdentityMasked, 'dev_••••9999');
      expect(session.isAlreadyLinked, isFalse);
    });
  });

  group('CODEX — Device Module Presentation UI Tests', () {
    testWidgets(
      '4. DeviceCard renders platform, display name and online status',
      (tester) async {
        final now = DateTime.now();
        final device = DeviceEntity(
          id: 'dev_12345678',
          familyId: 'fam_1',
          displayName: 'Family TV',
          platform: 'android_tv',
          manufacturer: 'Sony',
          model: 'Bravia',
          linkedAt: now,
          onlineUntil: now.add(const Duration(minutes: 5)),
          lastSeenAt: DateTime(2026, 10, 22, 9),
          sessionId: 'sess_live',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: DeviceCard(device: device, onTap: () {}),
          ),
        );
        await tester.pumpAndSettle();

        // Same card as IPTV: name, date/time last on, green dot (no text).
        expect(find.text('Family TV'), findsOneWidget);
        expect(find.text('22/10/2026 às 09:00'), findsOneWidget);
        expect(find.text('Sony • Bravia'), findsNothing);
        expect(find.text('Conectado'), findsNothing);
        expect(
          tester
              .widget<NeumorphicStatusIndicator>(
                find.byType(NeumorphicStatusIndicator),
              )
              .color,
          AppColors.statusOn,
        );
      },
    );

    testWidgets(
      '5. DeviceAddPage renders 4 step instructions and action buttons',
      (tester) async {
        await tester.pumpWidget(_buildTestApp(child: const DeviceAddPage()));
        await tester.pumpAndSettle();

        expect(find.text('Como conectar sua TV'), findsOneWidget);
        expect(
          find.textContaining('Abra o aplicativo iPlex Player'),
          findsOneWidget,
        );
        expect(find.textContaining('Aguarde o QR Code'), findsOneWidget);
        expect(find.text('Ler QR Code'), findsOneWidget);
        expect(find.text('Digitar código manualmente'), findsOneWidget);
      },
    );

    testWidgets('6. DeviceManualCodePage validates empty code submission', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(child: const DeviceManualCodePage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Código de pareamento'), findsWidgets);
      // Tap save without entering code
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe um valor válido.'), findsOneWidget);
    });

    testWidgets(
      '7. DeviceConfirmPairingPage renders TV metadata before link confirmation',
      (tester) async {
        const session = PairingSessionEntity(
          token: 'test_token',
          deviceId: 'dev_canon_1234',
          displayName: 'LG OLED Living Room',
          platform: 'webos',
          manufacturer: 'LG Electronics',
          model: 'OLED55G3',
          nativeIdentityMasked: 'dev_••••1234',
        );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              devicePairingProvider.overrideWith(
                () => _StaticDevicePairingNotifier(
                  DevicePairingState(session: session),
                ),
              ),
            ],
            child: const DeviceConfirmPairingPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Confirmar vinculação'), findsOneWidget);
        expect(find.text('LG OLED Living Room'), findsWidgets);
        expect(find.text('LG webOS'), findsWidgets);
        expect(find.text('LG Electronics'), findsOneWidget);
        expect(find.text('OLED55G3'), findsOneWidget);
        expect(find.text('dev_••••1234'), findsOneWidget);
        expect(find.text('Vincular dispositivo'), findsOneWidget);
      },
    );

    testWidgets(
      '8. DeviceConfirmPairingPage displays warning if TV is linked to another family',
      (tester) async {
        const session = PairingSessionEntity(
          token: 'test_token_foreign',
          deviceId: 'dev_canon_foreign',
          displayName: 'Foreign TV',
          platform: 'android_tv',
          isAlreadyLinked: true,
          isSameFamily: false,
        );

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              devicePairingProvider.overrideWith(
                () => _StaticDevicePairingNotifier(
                  DevicePairingState(session: session),
                ),
              ),
            ],
            child: const DeviceConfirmPairingPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('já está vinculada a outra família'),
          findsOneWidget,
        );
        expect(find.text('Vincular dispositivo'), findsNothing);
      },
    );

    testWidgets(
      '9. DevicePairingSuccessPage shows confirmation and navigation actions',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            child: const DevicePairingSuccessPage(deviceName: 'Cinema TV'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Vinculação concluída'), findsOneWidget);
        expect(find.text('Dispositivo vinculado'), findsOneWidget);
        expect(find.textContaining('Cinema TV'), findsOneWidget);
        expect(find.text('Voltar aos dispositivos'), findsOneWidget);
      },
    );
  });
}

class _StaticDevicePairingNotifier extends DevicePairingNotifier {
  _StaticDevicePairingNotifier(this._initialState);
  final DevicePairingState _initialState;

  @override
  DevicePairingState build() => _initialState;
}
