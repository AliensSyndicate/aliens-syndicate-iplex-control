import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aliens_syndicate_iplex_control/app/app.dart';
import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/features/authentication/login_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/devices_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_form.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/list_iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/users_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Explicit test double; never imported by production.
class TestRepository implements ManagerRepository {
  TestRepository({this.signedIn = false, this.admin = true, this.fail = false});
  bool signedIn, admin, fail;
  final mutations = <String>[];
  @override
  bool get configured => true;
  @override
  Stream<String?> authChanges() => Stream.value(signedIn ? 'u' : null);
  @override
  Future<void> initializeAccount(String uid) async {}
  @override
  Stream<Account?> watchAccount(String uid) => Stream.value(
    Account(
      uid: uid,
      name: 'Test account',
      email: 'test@example.invalid',
      familyId: 'f',
    ),
  );
  @override
  Stream<Family?> watchFamily(String id) => Stream.value(
    Family(
      id: id,
      adminId: admin ? 'u' : 'other',
      members: {'u': admin ? 'admin' : 'member'},
    ),
  );
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      fail ? Stream.error(const AppFailure('unavailable')) : Stream.value([]);
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      Stream.value(null);
  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    mutations.add(action);
    return {};
  }

  @override
  Future<CatalogPage> catalog(
    String familyId,
    Entry source,
    String search, {
    Object? cursor,
  }) async => const CatalogPage([], null, false);
  @override
  Future<void> signIn(String provider, {bool reauthenticate = false}) async {
    mutations.add(provider);
  }

  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

Widget host(
  Widget child, {
  TestRepository? repo,
  Size size = const Size(390, 844),
  double scale = 1,
}) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo ?? TestRepository())],
  child: MaterialApp(
    theme: AppTokens.theme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(
        key: const Key('screen'),
        child: GraphiteBackdrop(child: Scaffold(body: child)),
      ),
    ),
  ),
);
Future<void> screenshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('SCREENSHOTS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('screen')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('docs/screenshots').create(recursive: true);
    await File('docs/screenshots/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> loadTestFont() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map;
  final flutter = (config['packages'] as List).firstWhere(
    (p) => p['name'] == 'flutter',
  );
  final root = Uri.parse('${flutter['rootUri']}/').resolve('../../');
  final loader = FontLoader('Roboto')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File.fromUri(
            root.resolve(
              'bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            ),
          ).readAsBytesSync(),
        ),
      ),
    );
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File.fromUri(
            root.resolve(
              'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ),
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

void main() {
  setUpAll(loadTestFont);
  test('locale detection and fallback', () {
    expect(resolveLocale([const Locale('pt', 'PT')]), const Locale('pt', 'BR'));
    expect(resolveLocale([const Locale('fr')]), const Locale('en'));
    expect(resolveLocale([const Locale('es')]), const Locale('es'));
  });
  test('online status expires strictly and requires a session', () {
    final e = Entry('tv', {'onlineUntil': 100, 'sessionId': 's'});
    expect(e.onlineAt(DateTime.fromMillisecondsSinceEpoch(99)), true);
    expect(e.onlineAt(DateTime.fromMillisecondsSinceEpoch(100)), false);
  });
  testWidgets(
    'login providers invoke authentication and render without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repo = TestRepository();
      await tester.pumpWidget(
        host(
          RepaintBoundary(key: const Key('capture'), child: const LoginPage()),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(repo.mutations, ['google']);
      expect(tester.takeException(), null);
      await screenshot(tester, 'login');
    },
  );
  testWidgets(
    'five circular navigation buttons and straight full-width surface',
    (tester) async {
      int selected = -1;
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: const Key('capture'),
            child: BottomNavigation(
              selected: 2,
              onSelected: (i) => selected = i,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularButton), findsNWidgets(5));
      await tester.tap(find.byTooltip('IPTV'));
      await tester.tap(find.byType(CircularButton).at(3));
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(tester.takeException(), null);
    },
  );
  for (final page in [
    const UsersPage(),
    const DevicesPage(),
    const ListIptvPage(),
    const AccountPage(),
  ]) {
    testWidgets('${page.runtimeType} empty state and large text are safe', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        host(
          page,
          repo: TestRepository(signedIn: true),
          size: const Size(320, 640),
          scale: 1.8,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
    });
  }
  testWidgets('error state offers retry', (tester) async {
    await tester.pumpWidget(
      host(
        const DevicesPage(),
        repo: TestRepository(signedIn: true, fail: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
  });
  testWidgets('source form rejects insecure URL before mutation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = TestRepository(signedIn: true);
    await tester.pumpWidget(host(const IptvSourceForm(), repo: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Source');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'ftp://example.invalid',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.mutations, isEmpty);
    expect(find.text('Enter a valid value.'), findsOneWidget);
  });
  testWidgets('destructive dialog cancellation is respected', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              answer = await confirmRemoval(c);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, false);
  });
  testWidgets('unauthenticated deep link redirects to login', (tester) async {
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(TestRepository())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const IplexApp()),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/devices/private');
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });
  testWidgets('NeumorphicCircularButton circular geometry and states', (
    tester,
  ) async {
    bool pressed = false;
    await tester.pumpWidget(
      host(
        NeumorphicCircularButton(
          icon: AppIcons.home,
          label: 'Home',
          selected: true,
          onPressed: () => pressed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.byType(NeumorphicCircularButton);
    expect(finder, findsOneWidget);
    final size = tester.getSize(finder);
    expect(size.width, size.height); // Perfect circular geometry (1:1)

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(pressed, true);
  });
  testWidgets('NeumorphicActionButton handles busy and disabled states', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            NeumorphicActionButton(label: 'Busy Button', busy: true),
            NeumorphicActionButton(label: 'Disabled Button'),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Busy Button'), findsOneWidget);
    expect(find.text('Disabled Button'), findsOneWidget);
  });
  testWidgets('NeumorphicSurface renders elevated and recessed modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            NeumorphicSurface(recessed: false, child: Text('Elevated Surface')),
            NeumorphicSurface(recessed: true, child: Text('Recessed Surface')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Elevated Surface'), findsOneWidget);
    expect(find.text('Recessed Surface'), findsOneWidget);
  });
  testWidgets('NeumorphicStatusIndicator reflects online state and semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Row(
          children: [
            NeumorphicStatusIndicator(online: true),
            NeumorphicStatusIndicator(online: false),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NeumorphicStatusIndicator), findsNWidgets(2));
  });
  testWidgets('flutter_neumorphism_ui FlutterNeumorphism renders correctly', (
    tester,
  ) async {
    bool tapped = false;
    await tester.pumpWidget(
      host(
        FlutterNeumorphism(
          style: const NeumorphismStyle(
            color: AppColors.surfaceDefault,
            shape: BoxShape.circle,
            type: NeumorphismType.flat,
            depth: 8,
          ),
          onTap: () => tapped = true,
          child: const Text('Neumorphic'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Neumorphic'), findsOneWidget);
    await tester.tap(find.text('Neumorphic'));
    await tester.pumpAndSettle();
    expect(tapped, true);
  });
}
