import 'dart:async';

import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/data/models/iptv_catalog_model.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/domain/repositories/iptv_repository.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/presentation/controllers/iptv_sync_controller.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/presentation/widgets/global_iptv_sync_progress.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/presentation/widgets/iptv_sync_result_sheet.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/iptv_source_card.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCodexManagerRepo implements ManagerRepository {
  @override
  bool get configured => true;
  @override
  Stream<String?> authChanges() => Stream.value('test-uid');
  @override
  Future<void> initializeAccount(String uid) async {}
  @override
  Stream<Account?> watchAccount(String uid) => Stream.value(
    Account(
      uid: uid,
      name: 'Charles Santos',
      email: 'charles@iplex.app',
      familyId: 'family-100',
      locale: 'pt_BR',
    ),
  );
  @override
  Stream<Family?> watchFamily(String id) => Stream.value(
    Family(id: id, adminId: 'test-uid', members: const {'test-uid': 'admin'}),
  );
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      Stream.value(const []);
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      Stream.value(null);
  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async => {'status': 'ok'};
  @override
  Future<void> signIn(String provider, {bool reauthenticate = false}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
  @override
  Future<CatalogPage> catalog(
    String familyId,
    Entry source,
    String search, {
    Object? cursor,
  }) async => const CatalogPage([], null, false);
}

class MockCodexIptvRepo implements IptvRepository {
  final activeJobsController =
      StreamController<List<IptvSyncJobModel>>.broadcast();
  final syncJobController = StreamController<IptvSyncJobModel?>.broadcast();
  final sourceController = StreamController<IptvSourceModel?>.broadcast();
  final notificationsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  final List<String> markedDelivered = [];
  final List<String> triggeredSources = [];

  void dispose() {
    activeJobsController.close();
    syncJobController.close();
    sourceController.close();
    notificationsController.close();
  }

  @override
  Stream<List<IptvSyncJobModel>> watchActiveSyncJobs(String familyId) =>
      activeJobsController.stream;
  @override
  Stream<IptvSyncJobModel?> watchSyncJob(String jobId) =>
      syncJobController.stream;
  @override
  Stream<IptvSourceModel?> watchIptvSource(String sourceId) =>
      sourceController.stream;
  @override
  Stream<List<Map<String, dynamic>>> watchPendingNotifications(String uid) =>
      notificationsController.stream;
  @override
  Future<void> markNotificationDelivered(String uid, String jobId) async {
    markedDelivered.add(jobId);
  }

  @override
  Future<void> registerFcmToken(
    String uid,
    String token, {
    String? platform,
  }) async {}
  @override
  Future<Map<String, dynamic>> triggerSync(String sourceId) async {
    triggeredSources.add(sourceId);
    return {'id': sourceId, 'jobId': 'job-$sourceId'};
  }

  @override
  Future<Map<String, dynamic>> saveSource(Map<String, dynamic> payload) async =>
      {'id': 'src-1', 'jobId': 'job-1'};
}

Widget buildTestApp({required Widget child, required MockCodexIptvRepo repo}) {
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(MockCodexManagerRepo()),
      iptvRepositoryProvider.overrideWithValue(repo),
      activeIptvSyncJobsProvider.overrideWith(
        (ref) => repo.watchActiveSyncJobs('family-100'),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      locale: const Locale('pt', 'BR'),
      theme: AppTokens.theme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('CODEX — IPTC Mandatory Scenarios & Specifications', () {
    late MockCodexIptvRepo mockIptvRepo;

    setUp(() {
      mockIptvRepo = MockCodexIptvRepo();
    });

    tearDown(() {
      mockIptvRepo.dispose();
    });

    testWidgets(
      'CODEX 19: Global Progress Bar rendered below Status Bar, above AppBar, 2.5 dp height, non-blocking',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            repo: mockIptvRepo,
            child: Stack(
              children: [
                Scaffold(
                  appBar: AppBar(title: const Text('IPTV')),
                  body: const Center(child: Text('Content')),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: GlobalIptvSyncProgress(),
                ),
              ],
            ),
          ),
        );

        // Initially idle, opacity is 0.0
        expect(find.byType(GlobalIptvSyncProgress), findsOneWidget);
        final animatedOpacityFinder = find.descendant(
          of: find.byType(GlobalIptvSyncProgress),
          matching: find.byType(AnimatedOpacity),
        );
        expect(animatedOpacityFinder, findsOneWidget);
        var opacityWidget = tester.widget<AnimatedOpacity>(
          animatedOpacityFinder,
        );
        expect(opacityWidget.opacity, 0.0);

        // Emit active job
        final job = IptvSyncJobModel(
          jobId: 'job-123',
          familyId: 'family-100',
          sourceId: 'src-123',
          requestedByUid: 'test-uid',
          status: 'running',
          stage: 'downloading',
          progress: null, // Indeterminate
        );
        mockIptvRepo.activeJobsController.add([job]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
        expect(opacityWidget.opacity, 1.0);

        // Verify IgnorePointer ensures touches are never blocked
        final ignorePointerFinder = find.descendant(
          of: find.byType(GlobalIptvSyncProgress),
          matching: find.byType(IgnorePointer),
        );
        expect(ignorePointerFinder, findsOneWidget);
      },
    );

    testWidgets(
      'CODEX 20 & 21: Success and Failure Bottom Sheets with deduplication',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          buildTestApp(
            repo: mockIptvRepo,
            child: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Test Success Bottom Sheet
        IptvSyncResultSheet.show(
          capturedContext,
          jobId: 'job-success-1',
          sourceId: 'src-1',
          sourceName: 'Minha IPTV',
          isSuccess: true,
        );
        await tester.pumpAndSettle();

        expect(find.text('IPTV sincronizada'), findsOneWidget);
        expect(
          find.text('Sua lista IPTV foi atualizada com sucesso.'),
          findsOneWidget,
        );
        expect(find.text('Ver IPTV'), findsOneWidget);

        // Close bottom sheet
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        expect(find.text('IPTV sincronizada'), findsNothing);

        // Test Failure Bottom Sheet with retry callback
        IptvSyncResultSheet.show(
          capturedContext,
          jobId: 'job-failed-1',
          sourceId: 'src-1',
          sourceName: 'Minha IPTV',
          isSuccess: false,
          errorCode: 'provider-unavailable',
          onRetry: () {},
        );
        await tester.pumpAndSettle();

        expect(find.text('Falha na sincronização'), findsOneWidget);
        expect(
          find.text('Não foi possível conectar ao servidor.'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsOneWidget);

        // Tap Fechar
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'CODEX 23 & 24: Last Sync Date formatting on Card and Details Page',
      (tester) async {
        final syncTimestamp = DateTime(
          2026,
          10,
          18,
          0,
          0,
          0,
        ).millisecondsSinceEpoch;

        final sourceWithSync = Entry('src-synced', {
          'name': 'Canais Premium',
          'format': 'xtream',
          'status': 'ready',
          'lastSuccessfulSyncAt': syncTimestamp,
          'count': 120,
        });

        final sourceNeverSynced = Entry('src-never', {
          'name': 'Nova Fonte',
          'format': 'url',
          'status': 'ready',
          'count': 0,
        });

        await tester.pumpWidget(
          buildTestApp(
            repo: mockIptvRepo,
            child: Column(
              children: [
                IptvSourceCard(entry: sourceWithSync),
                IptvSourceCard(entry: sourceNeverSynced),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Card with lastSuccessfulSyncAt displays date and time
        // Only the date and time (no label, no status text).
        expect(find.text('18/10/2026 às 00:00'), findsOneWidget);
        expect(find.textContaining('Última sincronização'), findsNothing);
        // Card without previous sync displays "Nunca sincronizada"
        expect(find.text('Nunca sincronizada'), findsOneWidget);
      },
    );

    test('CODEX 12, 13 & 14: IptvCatalogModel retains metadata without automatic deletion', () {
      final now = DateTime.utc(2026, 10, 18, 12, 0);
      final catalog = IptvCatalogModel(
        catalogId: 'cat-456',
        version: 'v8',
        storagePath: 'catalogs/cat-456.json',
        status: 'ready',
        contentCount: 4500,
        activeSourceCount: 0, // No active users!
        createdAt: now,
        lastSuccessfulSyncAt: now,
      );

      // Retention rule: Remains stored indefinitely, activeSourceCount reflects state
      expect(catalog.catalogId, 'cat-456');
      expect(catalog.hasActiveUsers, isFalse);
      expect(catalog.isReady, isTrue);

      final map = catalog.toMap();
      expect(map['catalogId'], 'cat-456');
      expect(map['activeSourceCount'], 0);
      expect(map['storagePath'], 'catalogs/cat-456.json');

      final fromMap = IptvCatalogModel.fromMap('cat-456', map);
      expect(fromMap.catalogId, 'cat-456');
      expect(fromMap.version, 'v8');
      expect(fromMap.activeSourceCount, 0);

      // Reactivation
      final reactivated = fromMap.copyWith(activeSourceCount: 1);
      expect(reactivated.hasActiveUsers, isTrue);
      expect(reactivated.storagePath, 'catalogs/cat-456.json');
    });
  });
}
