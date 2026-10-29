import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/domain/entities/device_entity.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/domain/entities/pairing_session_entity.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/domain/repositories/device_repository.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/controllers/device_controller.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_confirm_pairing_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_detail_page.dart';
import 'package:aliens_syndicate_iplex_control/features/devices/presentation/pages/device_pairing_success_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _device = DeviceEntity(
  id: 'd1',
  familyId: 'f',
  displayName: 'Living room',
  platform: 'tizen',
  status: 'linked',
);

class _Pairing extends DevicePairingNotifier {
  String? linkedName;
  @override
  DevicePairingState build() => const DevicePairingState(
    session: PairingSessionEntity(
      token: 't',
      deviceId: 'd1',
      displayName: 'Samsung TV',
      platform: 'tizen',
    ),
  );

  @override
  Future<DeviceEntity> confirmLink({String? customName}) async {
    linkedName = customName;
    return _device;
  }
}

class _Devices implements DeviceRepository {
  final renamed = <String>[];
  var unlinked = 0;
  @override
  Future<void> renameDevice(String deviceId, String newName) async =>
      renamed.add(newName);
  @override
  Future<void> unlinkDevice(String deviceId) async => unlinked++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(GoRouter router, List<dynamic> overrides) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp.router(
    routerConfig: router,
    theme: AppTheme.darkTheme,
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  ),
);

GoRouter _router(String initial, Widget Function(String path) page) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/devices',
      builder: (c, s) => const Scaffold(body: Text('device list')),
      routes: [
        for (final path in ['confirm', 'success', 'd1'])
          GoRoute(
            path: path,
            builder: (c, s) => Scaffold(body: page(path)),
          ),
      ],
    ),
  ],
);

void main() {
  testWidgets('confirmation lets the TV be renamed before linking', (
    tester,
  ) async {
    final pairing = _Pairing();
    final router = _router(
      '/devices',
      (path) => path == 'confirm'
          ? const DeviceConfirmPairingPage()
          : const DevicePairingSuccessPage(),
    );
    await tester.pumpWidget(
      _app(router, [devicePairingProvider.overrideWith(() => pairing)]),
    );
    router.push('/devices/confirm');
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byKey(const Key('pairing-device-name')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).controller.text, 'Samsung TV');

    await tester.enterText(field, '  ');
    await tester.tap(find.text('Vincular dispositivo'));
    await tester.pumpAndSettle();
    expect(pairing.linkedName, isNull, reason: 'empty name is not sent');

    await tester.enterText(field, 'Quarto');
    await tester.tap(find.text('Vincular dispositivo'));
    await tester.pumpAndSettle();
    expect(pairing.linkedName, 'Quarto');
    expect(find.text('Vinculação concluída'), findsOneWidget);
  });

  testWidgets('back on the success page always returns to the device list', (
    tester,
  ) async {
    for (final system in [false, true]) {
      final router = _router(
        '/devices',
        (_) => const DevicePairingSuccessPage(deviceName: 'TV'),
      );
      await tester.pumpWidget(_app(router, []));
      router.push('/devices/confirm');
      await tester.pumpAndSettle();
      router.push('/devices/success');
      await tester.pumpAndSettle();

      if (system) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.bySemanticsLabel('Voltar'));
      }
      await tester.pumpAndSettle();
      expect(find.text('device list'), findsOneWidget, reason: '$system');
      expect(router.state.uri.path, '/devices');
    }
  });

  testWidgets('detail page edits the name in place and unlinks via sheet', (
    tester,
  ) async {
    final devices = _Devices();
    final router = _router(
      '/devices',
      (_) => const DeviceDetailPage(deviceId: 'd1'),
    );
    await tester.pumpWidget(
      _app(router, [
        deviceRepositoryProvider.overrideWithValue(devices),
        deviceDetailStreamProvider('d1')
            .overrideWith((ref) => Stream.value(_device)),
        canManageResourcesProvider.overrideWithValue(true),
      ]),
    );
    router.push('/devices/d1');
    await tester.pumpAndSettle();
    expect(find.text('Editar nome da TV'), findsNothing);

    final field = find.descendant(
      of: find.byKey(const Key('device-name-field')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).controller.text, 'Living room');
    await tester.enterText(field, 'Sala');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(devices.renamed, ['Sala']);

    await tester.ensureVisible(find.byKey(const Key('device-unlink')));
    await tester.tap(find.byKey(const Key('device-unlink')));
    await tester.pumpAndSettle();
    expect(find.text('Desvincular esta TV?'), findsOneWidget);
    // The sheet's red confirm button.
    await tester.tap(
      find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.text('Desvincular dispositivo'),
      ),
    );
    await tester.pumpAndSettle();
    expect(devices.unlinked, 1);
    expect(find.text('device list'), findsOneWidget);
  });
}
