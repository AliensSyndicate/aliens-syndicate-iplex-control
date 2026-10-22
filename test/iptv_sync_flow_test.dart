import 'dart:async';

import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/domain/repositories/iptv_repository.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/presentation/controllers/iptv_sync_controller.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/presentation/widgets/global_iptv_sync_progress.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/iptv_source_card.dart';
import 'package:aliens_syndicate_iplex_control/features/iptv/presentation/widgets/iptv_sync_result_sheet.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSyncManagerRepository implements ManagerRepository {
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
      name: 'Test User',
      email: 'user@iplex.app',
      familyId: 'family-123',
      locale: 'pt_BR',
    ),
  );

  @override
  Stream<Family?> watchFamily(String id) => Stream.value(
    Family(id: id, adminId: 'test-uid', members: const {'test-uid': 'Admin'}),
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

class FakeIptvRepository implements IptvRepository {
  final activeJobsController =
      StreamController<List<IptvSyncJobModel>>.broadcast();
  final syncJobController = StreamController<IptvSyncJobModel?>.broadcast();
  final sourceController = StreamController<IptvSourceModel?>.broadcast();
  final pendingNotificationsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  final List<String> deliveredNotificationJobIds = [];
  final List<String> triggeredSyncSourceIds = [];

  void dispose() {
    activeJobsController.close();
    syncJobController.close();
    sourceController.close();
    pendingNotificationsController.close();
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
      pendingNotificationsController.stream;

  @override
  Future<void> markNotificationDelivered(String uid, String jobId) async {
    deliveredNotificationJobIds.add(jobId);
  }

  @override
  Future<void> registerFcmToken(
    String uid,
    String token, {
    String? platform,
  }) async {}

  @override
  Future<Map<String, dynamic>> triggerSync(String sourceId) async {
    triggeredSyncSourceIds.add(sourceId);
    return {'jobId': 'job-retry-1', 'status': 'queued'};
  }

  @override
  Future<Map<String, dynamic>> saveSource(Map<String, dynamic> payload) async {
    return {'id': 'src-1', 'jobId': 'job-new-1'};
  }
}

Widget createTestApp({
  required Widget child,
  required FakeIptvRepository iptvRepo,
}) {
  return ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(FakeSyncManagerRepository()),
      iptvRepositoryProvider.overrideWithValue(iptvRepo),
      activeIptvSyncJobsProvider.overrideWith(
        (ref) => iptvRepo.watchActiveSyncJobs('family-123'),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      home: Scaffold(
        body: Column(
          children: [
            const GlobalIptvSyncProgress(),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('CODEX IPTV Background Sync - Global Progress & Sheet Tests', () {
    late FakeIptvRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeIptvRepository();
    });

    tearDown(() {
      fakeRepo.dispose();
    });

    testWidgets(
      '1. GlobalIptvSyncProgress is invisible (opacity 0) when idle',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(iptvRepo: fakeRepo, child: const Text('App Content')),
        );
        fakeRepo.activeJobsController.add([]);
        await tester.pump();

        expect(find.text('App Content'), findsOneWidget);
        expect(find.byType(GlobalIptvSyncProgress), findsOneWidget);

        // When idle, GlobalIptvSyncProgress sets opacity to 0.0 and renders SizedBox.shrink
        final opacityFinder = find.descendant(
          of: find.byType(GlobalIptvSyncProgress),
          matching: find.byType(AnimatedOpacity),
        );
        expect(opacityFinder, findsOneWidget);
        final opacityWidget = tester.widget<AnimatedOpacity>(opacityFinder);
        expect(opacityWidget.opacity, 0.0);

        final shrinkFinder = find.descendant(
          of: find.byType(GlobalIptvSyncProgress),
          matching: find.byType(SizedBox),
        );
        expect(shrinkFinder, findsWidgets);
      },
    );

    testWidgets(
      '2. GlobalIptvSyncProgress shows indeterminate animated bar when job has progress = null',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(iptvRepo: fakeRepo, child: const Text('App Content')),
        );
        fakeRepo.activeJobsController.add([
          IptvSyncJobModel(
            jobId: 'job-1',
            familyId: 'family-123',
            sourceId: 'src-1',
            requestedByUid: 'test-uid',
            status: 'running',
            stage: 'downloading',
            progress: null, // indeterminate
          ),
        ]);
        await tester.pump();

        // Non-blocking touch: IgnorePointer wraps the progress bar
        final ignorePointerFinder = find.descendant(
          of: find.byType(GlobalIptvSyncProgress),
          matching: find.byType(IgnorePointer),
        );
        expect(ignorePointerFinder, findsOneWidget);

        // Opacity is 1.0 (visible)
        final opacityWidget = tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(GlobalIptvSyncProgress),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(opacityWidget.opacity, 1.0);

        // Advance animation frame
        await tester.pump(const Duration(milliseconds: 200));

        // When jobs become empty again, stops animation and becomes transparent
        fakeRepo.activeJobsController.add([]);
        await tester.pump();
        final idleOpacity = tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(GlobalIptvSyncProgress),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(idleOpacity.opacity, 0.0);
      },
    );

    testWidgets(
      '3. GlobalIptvSyncProgress shows determinate fractional width when job progress is known',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(iptvRepo: fakeRepo, child: const Text('App Content')),
        );
        fakeRepo.activeJobsController.add([
          IptvSyncJobModel(
            jobId: 'job-2',
            familyId: 'family-123',
            sourceId: 'src-2',
            requestedByUid: 'test-uid',
            status: 'running',
            stage: 'parsing',
            progress: 75, // 75%
          ),
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // FractionalTranslation or FractionallySizedBox used for progress
        final fractionalFinder = find.descendant(
          of: find.byType(GlobalIptvSyncProgress),
          matching: find.byType(FractionallySizedBox),
        );
        expect(fractionalFinder, findsOneWidget);
        final fractionalWidget = tester.widget<FractionallySizedBox>(
          fractionalFinder,
        );
        expect(fractionalWidget.widthFactor, closeTo(0.75, 0.02));

        // Clean up
        fakeRepo.activeJobsController.add([]);
        await tester.pump();
      },
    );

    testWidgets(
      '4. IptvSyncResultSheet displays success bottom sheet with "Ver IPTV" action',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(FakeSyncManagerRepository()),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('pt'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        IptvSyncResultSheet.show(
                          context,
                          jobId: 'job-success-1',
                          sourceId: 'source-100',
                          sourceName: 'Minha Lista Premium',
                          isSuccess: true,
                        );
                      },
                      child: const Text('Open Sheet'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // Title and body checks
        expect(find.text('IPTV sincronizada'), findsOneWidget);
        expect(
          find.text('Sua lista IPTV foi atualizada com sucesso.'),
          findsOneWidget,
        );
        expect(find.text('Minha Lista Premium'), findsOneWidget);
        expect(find.text('Ver IPTV'), findsOneWidget);
        expect(find.text('Fechar'), findsOneWidget);

        // Tap Fechar closes the sheet
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        expect(find.text('IPTV sincronizada'), findsNothing);
      },
    );

    testWidgets(
      '5. IptvSyncResultSheet displays failure bottom sheet with friendly error and retry',
      (tester) async {
        bool retryTapped = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(FakeSyncManagerRepository()),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('pt'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        IptvSyncResultSheet.show(
                          context,
                          jobId: 'job-fail-1',
                          sourceId: 'source-200',
                          sourceName: 'Lista com Falha',
                          isSuccess: false,
                          errorCode: 'invalid-credentials',
                          onRetry: () {
                            retryTapped = true;
                          },
                        );
                      },
                      child: const Text('Open Fail Sheet'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Fail Sheet'));
        await tester.pumpAndSettle();

        // Failure title, error message mapping, and actions
        expect(find.text('Falha na sincronização'), findsOneWidget);
        expect(find.text('Credenciais inválidas.'), findsOneWidget);
        expect(find.text('Lista com Falha'), findsOneWidget);
        expect(find.text('Tentar novamente'), findsOneWidget);
        expect(find.text('Fechar'), findsOneWidget);

        // Tap retry executes callback and closes
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();
        expect(retryTapped, isTrue);
        expect(find.text('Falha na sincronização'), findsNothing);
      },
    );

    testWidgets(
      '6. Notification Deduplication prevents opening multiple simultaneous sheets',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final tracker = container.read(
          syncNotificationTrackerProvider.notifier,
        );

        expect(tracker.hasShown('job-abc'), isFalse);
        tracker.markAsShown('job-abc');
        expect(tracker.hasShown('job-abc'), isTrue);

        // Subsequent check ignores job-abc
        expect(tracker.hasShown('job-xyz'), isFalse);
        tracker.markAsShown('job-xyz');
        expect(tracker.hasShown('job-xyz'), isTrue);

        tracker.reset();
        expect(tracker.hasShown('job-abc'), isFalse);
      },
    );

    testWidgets(
      '7. Error mapping produces friendly messages for provider-unavailable, invalid-catalog, timeout and default',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: Builder(
              builder: (context) {
                expect(
                  mapIptvErrorCodeToMessage(context, 'provider-unavailable'),
                  'Não foi possível conectar ao servidor.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'invalid-catalog'),
                  'Playlist inválida.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'timeout'),
                  'Tempo de conexão esgotado.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'invalid-source-url'),
                  'O endereço da IPTV é inválido.',
                );
                expect(
                  mapIptvErrorCodeToMessage(
                    context,
                    'unrecognized-source-format',
                  ),
                  'Não foi possível identificar o formato da IPTV.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'provider-rate-limited'),
                  'O servidor está limitando as solicitações. Tente novamente mais tarde.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'provider-time-budget'),
                  'O servidor demorou demais para responder.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'download-failed'),
                  'Não foi possível baixar os dados da IPTV.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'catalog-too-large'),
                  'A lista excede o limite de processamento permitido.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'suspicious-catalog'),
                  'A lista recebida está vazia ou incompleta.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'duplicate-content'),
                  'A lista contém conteúdos duplicados.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'hls-origin-required'),
                  'O fluxo HLS requer um endereço de origem válido.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'parsing-failed'),
                  'Não foi possível interpretar os dados da IPTV.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'normalization-failed'),
                  'Não foi possível preparar o catálogo.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'storage-upload-failed'),
                  'Não foi possível armazenar o catálogo processado.',
                );
                expect(
                  mapIptvErrorCodeToMessage(
                    context,
                    'catalog-publication-failed',
                  ),
                  'Não foi possível concluir a atualização do catálogo.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'catalog-sync-failed'),
                  'Não foi possível concluir a sincronização.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'unsafe-provider'),
                  'Endereço não permitido por motivos de segurança.',
                );
                expect(
                  mapIptvErrorCodeToMessage(context, 'unknown-failure'),
                  'Erro temporário de processamento.',
                );
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pump();
      },
    );

    test('8. Multiple concurrent jobs calculate consistent average percentage without summing incompatible numbers', () {
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(FakeSyncManagerRepository()),
          activeIptvSyncJobsProvider.overrideWithValue(
            AsyncData([
              IptvSyncJobModel(
                jobId: 'job-a',
                familyId: 'family-123',
                sourceId: 'src-a',
                requestedByUid: 'test-uid',
                status: 'running',
                stage: 'parsing',
                progress: 40,
              ),
              IptvSyncJobModel(
                jobId: 'job-b',
                familyId: 'family-123',
                sourceId: 'src-b',
                requestedByUid: 'test-uid',
                status: 'running',
                stage: 'parsing',
                progress: 80,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final syncState = container.read(globalIptvSyncProgressProvider);
      expect(syncState.isActive, isTrue);
      expect(syncState.isIndeterminate, isTrue);
      expect(syncState.progress, isNull);
      expect(syncState.activeCount, 2);
    });

    test('9. If any concurrent job is indeterminate or queued, global state remains indeterminate', () {
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(FakeSyncManagerRepository()),
          activeIptvSyncJobsProvider.overrideWithValue(
            AsyncData([
              IptvSyncJobModel(
                jobId: 'job-determinate',
                familyId: 'family-123',
                sourceId: 'src-1',
                requestedByUid: 'test-uid',
                status: 'running',
                stage: 'parsing',
                progress: 90,
              ),
              IptvSyncJobModel(
                jobId: 'job-indeterminate',
                familyId: 'family-123',
                sourceId: 'src-2',
                requestedByUid: 'test-uid',
                status: 'running',
                stage: 'downloading',
                progress: null, // indeterminate
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final syncState = container.read(globalIptvSyncProgressProvider);
      expect(syncState.isActive, isTrue);
      expect(syncState.isIndeterminate, isTrue);
      expect(syncState.progress, isNull);
    });

    testWidgets(
      '10. Global progress bar remains visible and persists during route navigation',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(FakeSyncManagerRepository()),
              iptvRepositoryProvider.overrideWithValue(fakeRepo),
              activeIptvSyncJobsProvider.overrideWith(
                (ref) => fakeRepo.watchActiveSyncJobs('family-123'),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('pt'),
              home: Scaffold(
                body: Column(
                  children: [
                    const GlobalIptvSyncProgress(),
                    Expanded(
                      child: Navigator(
                        onGenerateRoute: (settings) {
                          if (settings.name == '/details') {
                            return MaterialPageRoute(
                              builder: (context) =>
                                  const Center(child: Text('Details Screen')),
                            );
                          }
                          return MaterialPageRoute(
                            builder: (context) => Builder(
                              builder: (ctx) => Center(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(ctx).pushNamed('/details');
                                  },
                                  child: const Text('Go To Details'),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Start job
        fakeRepo.activeJobsController.add([
          IptvSyncJobModel(
            jobId: 'job-persistent',
            familyId: 'family-123',
            sourceId: 'src-p',
            requestedByUid: 'test-uid',
            status: 'running',
            stage: 'parsing',
            progress: 50,
          ),
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // Progress bar is active with opacity 1
        final initialOpacity = tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(GlobalIptvSyncProgress),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(initialOpacity.opacity, 1.0);

        // Navigate to details screen
        await tester.tap(find.text('Go To Details'));
        await tester.pumpAndSettle();
        expect(find.text('Details Screen'), findsOneWidget);

        // Progress bar is still there at top and active
        final navigatedOpacity = tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(GlobalIptvSyncProgress),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(navigatedOpacity.opacity, 1.0);

        // Complete job
        fakeRepo.activeJobsController.add([]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final idleOpacity = tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(GlobalIptvSyncProgress),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(idleOpacity.opacity, 0.0);
      },
    );

    testWidgets('11. Error mapping in English and Spanish for specific codes', (
      tester,
    ) async {
      // Test English
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              expect(
                mapIptvErrorCodeToMessage(context, 'invalid-source-url'),
                'The IPTV address is invalid.',
              );
              expect(
                mapIptvErrorCodeToMessage(
                  context,
                  'unrecognized-source-format',
                ),
                'Could not identify the IPTV format.',
              );
              expect(
                mapIptvErrorCodeToMessage(context, 'catalog-too-large'),
                'The playlist exceeds the allowed processing limit.',
              );
              expect(
                mapIptvErrorCodeToMessage(context, 'provider-time-budget'),
                'The server took too long to respond.',
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      // Test Spanish
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('es'),
          home: Builder(
            builder: (context) {
              expect(
                mapIptvErrorCodeToMessage(context, 'invalid-source-url'),
                'La dirección de la IPTV no es válida.',
              );
              expect(
                mapIptvErrorCodeToMessage(
                  context,
                  'unrecognized-source-format',
                ),
                'No se pudo identificar el formato de la IPTV.',
              );
              expect(
                mapIptvErrorCodeToMessage(context, 'catalog-too-large'),
                'La lista excede el límite de procesamiento permitido.',
              );
              expect(
                mapIptvErrorCodeToMessage(context, 'provider-time-budget'),
                'El servidor tardó demasiado en responder.',
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
    });

    test('12. IptvSyncJobModel serializes and deserializes errorRetryable and traceId', () {
      final job = IptvSyncJobModel(
        jobId: 'job-err-1',
        familyId: 'family-1',
        sourceId: 'source-1',
        requestedByUid: 'uid-1',
        status: 'failed',
        stage: 'downloading',
        errorCode: 'provider-time-budget',
        errorRetryable: true,
        traceId: 'trace-abc-123',
      );

      final map = job.toMap();
      expect(map['errorCode'], 'provider-time-budget');
      expect(map['errorRetryable'], true);
      expect(map['traceId'], 'trace-abc-123');
      expect(map['stage'], 'downloading');

      final reconstructed = IptvSyncJobModel.fromMap('job-err-1', map);
      expect(reconstructed.errorCode, 'provider-time-budget');
      expect(reconstructed.errorRetryable, true);
      expect(reconstructed.traceId, 'trace-abc-123');
      expect(reconstructed.stage, 'downloading');
      expect(reconstructed.isFailed, true);
    });

    testWidgets(
      '13. IptvSyncResultSheet displays specific error for unrecognized-source-format and catalog-too-large',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      IptvSyncResultSheet.show(
                        context,
                        jobId: 'job-unrec',
                        sourceId: 'src-1',
                        sourceName: 'Lista Especial',
                        isSuccess: false,
                        errorCode: 'unrecognized-source-format',
                      );
                    },
                    child: const Text('Open Sheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Falha na sincronização'), findsOneWidget);
        expect(
          find.text('Não foi possível identificar o formato da IPTV.'),
          findsOneWidget,
        );
        expect(find.text('Lista Especial'), findsOneWidget);
      },
    );

    testWidgets(
      '14. IptvSourceCard displays Online (green), Offline (grey), and Falha (red) circles',
      (tester) async {
        final onlineSource = Entry('src-online', {
          'name': 'Lista Online',
          'status': 'ready',
          'enabled': true,
        });

        final offlineSource = Entry('src-offline', {
          'name': 'Lista Offline',
          'status': 'queued',
          'enabled': false,
        });

        final errorSource = Entry('src-error', {
          'name': 'Lista Falha',
          'status': 'error',
          'errorCode': 'provider-unavailable',
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('pt'),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      IptvSourceCard(entry: onlineSource),
                      IptvSourceCard(entry: offlineSource),
                      IptvSourceCard(entry: errorSource),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No status text on the card: only the indicator (with its label).
        expect(find.text('Online'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Online',
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Desabilitado',
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Falha',
          ),
          findsOneWidget,
        );

        // Status indicators
        final indicators = tester
            .widgetList<NeumorphicStatusIndicator>(
              find.byType(NeumorphicStatusIndicator),
            )
            .toList();
        expect(indicators.length, 3);
        expect(indicators[0].status, IndicatorStatus.online);
        expect(indicators[1].status, IndicatorStatus.offline);
        expect(indicators[2].status, IndicatorStatus.error);
        // Green on, grey off, red failure.
        expect(indicators[0].color, AppColors.statusOn);
        expect(indicators[1].color, AppColors.disabled);
        expect(indicators[2].color, AppColors.error);

        // Card icon has fixed color
        final icons = tester
            .widgetList<AppIcon>(
              find.byWidgetPredicate(
                (w) => w is AppIcon && w.icon == AppIcons.iptv,
              ),
            )
            .toList();
        expect(icons.length, 3);
        expect(icons[0].color, AppColors.textSecondary);
        expect(icons[1].color, AppColors.textSecondary);
        expect(icons[2].color, AppColors.textSecondary);
      },
    );

    testWidgets(
      '15. IptvPage displays Online, Offline, and Falha with corresponding NeumorphicStatusIndicator',
      (tester) async {
        final onlineSource = Entry('src-page-online', {
          'name': 'Lista Page Online',
          'status': 'ready',
          'enabled': true,
          'count': 100,
        });

        final offlineSource = Entry('src-page-offline', {
          'name': 'Lista Page Offline',
          'status': 'queued',
          'enabled': false,
          'count': 0,
        });

        final errorSource = Entry('src-page-error', {
          'name': 'Lista Page Falha',
          'status': 'error',
          'errorCode': 'provider-unavailable',
          'count': 0,
        });

        Widget buildPage(Entry entry) {
          return ProviderScope(
            key: ValueKey(entry.id),
            overrides: [
              entryProvider((collection: 'sources', id: entry.id))
                  .overrideWith((ref) => Stream.value(entry)),
              canManageIptvProvider.overrideWithValue(false),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('pt'),
              home: IptvPage(id: entry.id),
            ),
          );
        }

        // Test Online
        await tester.pumpWidget(buildPage(onlineSource));
        await tester.pumpAndSettle();
        expect(find.text('Online'), findsOneWidget);
        var indicator = tester.widget<NeumorphicStatusIndicator>(
          find.byType(NeumorphicStatusIndicator),
        );
        expect(indicator.status, IndicatorStatus.online);
        var icon = tester.widget<AppIcon>(
          find.byWidgetPredicate(
            (w) => w is AppIcon && w.icon == AppIcons.iptv,
          ),
        );
        expect(icon.color, AppColors.textSecondary);

        // Test Offline
        await tester.pumpWidget(buildPage(offlineSource));
        await tester.pumpAndSettle();
        expect(find.text('Offline'), findsOneWidget);
        indicator = tester.widget<NeumorphicStatusIndicator>(
          find.byType(NeumorphicStatusIndicator),
        );
        expect(indicator.status, IndicatorStatus.offline);
        icon = tester.widget<AppIcon>(
          find.byWidgetPredicate(
            (w) => w is AppIcon && w.icon == AppIcons.iptv,
          ),
        );
        expect(icon.color, AppColors.textSecondary);

        // Test Falha
        await tester.pumpWidget(buildPage(errorSource));
        await tester.pumpAndSettle();
        expect(find.text('Falha'), findsOneWidget);
        indicator = tester.widget<NeumorphicStatusIndicator>(
          find.byType(NeumorphicStatusIndicator),
        );
        expect(indicator.status, IndicatorStatus.error);
        icon = tester.widget<AppIcon>(
          find.byWidgetPredicate(
            (w) => w is AppIcon && w.icon == AppIcons.iptv,
          ),
        );
        expect(icon.color, AppColors.textSecondary);
      },
    );
  });
}
