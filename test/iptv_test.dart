import 'dart:async';

import 'package:aliens_syndicate_iplex_control/app/app.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_details_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_form.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/list_iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' as fixtures;

class IptvMockRepository implements ManagerRepository {
  IptvMockRepository({
    this.signedIn = true,
    this.admin = true,
    this.fail = false,
    List<Entry>? sourcesList,
  }) : sourcesList = sourcesList ?? [];

  bool signedIn;
  bool admin;
  bool fail;
  Completer<void>? mutateCompleter;
  final List<({String action, Map<String, dynamic> payload})>
  recordedMutations = [];
  List<Entry> sourcesList = [];
  final sourcesController = StreamController<List<Entry>>.broadcast(sync: true);

  @override
  bool get configured => true;

  @override
  Stream<String?> authChanges() =>
      Stream.value(signedIn ? 'test-user-id' : null);

  @override
  Future<void> initializeAccount(String uid) async {}

  @override
  Stream<Account?> watchAccount(String uid) => Stream.value(
    signedIn
        ? Account(
            uid: uid,
            name: 'Test Admin',
            email: 'admin@iplex.app',
            familyId: 'family-1',
            locale: 'pt_BR',
          )
        : null,
  );

  @override
  Stream<Family?> watchFamily(String id) => Stream.value(
    Family(
      id: id,
      adminId: admin ? 'test-user-id' : 'another-admin-id',
      members: {'test-user-id': admin ? 'admin' : 'member'},
    ),
  );

  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) async* {
    if (fail) throw const AppFailure('unavailable');
    if (collection == 'sources') {
      yield sourcesList;
      yield* sourcesController.stream;
    } else {
      yield [];
    }
  }

  @override
  Stream<Entry?> watchEntry(
    String familyId,
    String collection,
    String id,
  ) async* {
    if (fail) throw const AppFailure('unavailable');
    if (collection == 'sources') {
      final match = sourcesList.cast<Entry?>().firstWhere(
        (e) => e?.id == id,
        orElse: () => null,
      );
      yield match;
    } else {
      yield null;
    }
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!signedIn) throw const AppFailure('unauthenticated');
    if (fail) throw const AppFailure('unavailable');
    if (mutateCompleter != null) {
      await mutateCompleter!.future;
    }
    recordedMutations.add((action: action, payload: Map.from(payload)));
    return {'id': payload['id'] ?? 'generated-source-id', 'ok': true};
  }

  @override
  Future<CatalogPage> catalog(
    String familyId,
    Entry source,
    String search, {
    Object? cursor,
  }) async => const CatalogPage([], null, false);

  @override
  Future<void> signIn(String provider, {bool reauthenticate = false}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

Widget createTestApp({
  required Widget child,
  required IptvMockRepository repo,
  Locale locale = const Locale('pt', 'BR'),
}) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(fixtures.loadTestFont);

  void setTestSize(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('IPTV Suite — 24 Required Scenarios', () {
    // 1. Listagem vazia
    testWidgets('1. Listagem vazia exibe mensagem e botão de adicionar', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository(sourcesList: []);
      await tester.pumpWidget(
        createTestApp(child: const ListIptvPage(), repo: repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('IPTV'), findsOneWidget);
      expect(find.text('Gerencie suas fontes de conteúdo'), findsNothing);
      expect(find.text('Nenhuma fonte IPTV'), findsOneWidget);
      expect(
        find.text(
          'Adicione sua primeira fonte para disponibilizar conteúdos no iPlex.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(AppButton, 'Adicionar fonte'), findsOneWidget);
    });

    // 2. Listagem com fontes
    testWidgets(
      '2. Listagem com fontes exibe nome, formato, status e última sincronização',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository()
          ..sourcesList = [
            Entry('s1', {
              'name': 'Lista Esportes M3U',
              'format': 'm3u',
              'status': 'ready',
              'host': 'iptv.sports.example',
              'count': 120,
              'lastSyncAt': DateTime(
                2026,
                10,
                17,
                14,
                30,
              ).millisecondsSinceEpoch,
            }),
            Entry('s2', {
              'name': 'Servidor Cinema Xtream',
              'format': 'xtream',
              'status': 'syncing',
              'host': 'xtream.cinema.example',
              'count': 540,
              'lastSyncAt': 0,
            }),
          ];

        await tester.pumpWidget(
          createTestApp(child: const ListIptvPage(), repo: repo),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.text('Lista Esportes M3U'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Online',
          ),
          findsOneWidget,
        );

        expect(find.text('Servidor Cinema Xtream'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Sincronizando',
          ),
          findsOneWidget,
        );
        expect(find.text('Nunca sincronizada'), findsOneWidget);

        // Credenciais ou tokens nunca devem ser vazados
        expect(find.textContaining('password'), findsNothing);
        expect(find.textContaining('token'), findsNothing);
      },
    );

    // 3. Cadastro M3U válido
    testWidgets('3. Cadastro M3U válido envia dados corretos ao backend', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository();
      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Minha Playlist M3U',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'https://provider.example.com/playlist.m3u8',
      );
      await tester.pumpAndSettle();

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.action, 'saveSource');
      expect(m.payload['name'], 'Minha Playlist M3U');
      expect(m.payload['format'], 'm3u');
      expect(m.payload['url'], 'https://provider.example.com/playlist.m3u8');
    });

    // 4. Cadastro Xtream válido
    testWidgets(
      '4. Cadastro Xtream válido envia dados e credenciais protegidas',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository();
        await tester.pumpWidget(
          createTestApp(child: const IptvSourceForm(), repo: repo),
        );
        await tester.pumpAndSettle();

        // Muda formato para Xtream
        await tester.tap(find.text('Xtream Codes').first);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(AppTextField, 'Nome'),
          'Servidor Xtream Pro',
        );
        await tester.enterText(
          find.widgetWithText(AppTextField, 'URL do servidor'),
          'https://xtream.example.com:8443',
        );
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Usuário'),
          'cliente_123',
        );
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Senha'),
          'senha_super_secreta',
        );
        await tester.pumpAndSettle();

        final saveBtn = find.widgetWithText(AppButton, 'Salvar');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(repo.recordedMutations.length, 1);
        final m = repo.recordedMutations.first;
        expect(m.action, 'saveSource');
        expect(m.payload['name'], 'Servidor Xtream Pro');
        expect(m.payload['format'], 'xtream');
        expect(m.payload['url'], 'https://xtream.example.com:8443');
        expect(m.payload['username'], 'cliente_123');
        expect(m.payload['password'], 'senha_super_secreta');
      },
    );

    // 5. Campos inválidos
    testWidgets('5. Campos inválidos impedem submissão do formulário', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository();
      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      // Tenta salvar com campos vazios
      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Informe um valor válido.'), findsWidgets);
      expect(repo.recordedMutations, isEmpty);
    });

    // 6. URL inválida
    testWidgets('6. URL com esquema inválido ou com userInfo é rejeitada', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository();
      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Fonte Insegura',
      );
      // Esquema inválido (ftp em vez de http/https)
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'ftp://insecure.example.com/list.m3u',
      );
      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(repo.recordedMutations, isEmpty);

      // URL com credenciais embutidas (userInfo)
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'https://user:pass@example.com/list.m3u',
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(repo.recordedMutations, isEmpty);
    });

    // 7. Erro de autenticação
    testWidgets('7. Erro de autenticação é tratado com falha explicativa', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository(signedIn: false);
      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Teste',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'https://example.com/playlist.m3u',
      );
      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Entre novamente para continuar.'), findsOneWidget);
    });

    // 8. Erro de autorização
    testWidgets(
      '8. Membro associado não possui ações administrativas na lista',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository(admin: false);
        await tester.pumpWidget(
          createTestApp(child: const ListIptvPage(), repo: repo),
        );
        await tester.pumpAndSettle();

        // Botão circular "+" no cabeçalho não deve existir para associado
        expect(find.byType(CircularButton), findsNothing);
        // Botão de adicionar no estado vazio não deve existir para associado
        expect(find.widgetWithText(AppButton, 'Adicionar fonte'), findsNothing);
      },
    );

    // 9. Erro de conexão
    testWidgets(
      '9. Erro de conexão exibe tela de erro com botão de repetição',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository(fail: true);
        await tester.pumpWidget(
          createTestApp(child: const ListIptvPage(), repo: repo),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Não foi possível concluir esta solicitação.'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsOneWidget);

        // Ao clicar em tentar novamente, refaz a consulta
        repo.fail = false;
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();
        expect(find.text('Nenhuma fonte IPTV'), findsOneWidget);
      },
    );

    // 10. Salvamento duplicado
    testWidgets(
      '10. Botão de salvar fica ocupado (busy) e previne duplo clique',
      (tester) async {
        setTestSize(tester);

        final completer = Completer<void>();
        final repo = IptvMockRepository()..mutateCompleter = completer;

        await tester.pumpWidget(
          createTestApp(child: const IptvSourceForm(), repo: repo),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(AppTextField, 'Nome'),
          'Fonte Única',
        );
        await tester.enterText(
          find.widgetWithText(AppTextField, 'URL da playlist'),
          'https://provider.example.com/list.m3u',
        );
        await tester.pumpAndSettle();

        final saveBtn = find.widgetWithText(AppButton, 'Salvar');
        await tester.ensureVisible(saveBtn);
        // Primeiro clique inicia mutação assíncrona
        await tester.tap(saveBtn);
        await tester.pump(); // Inicia estado busy

        // Segundo clique enquanto está busy não deve gerar nova mutação
        await tester.tap(saveBtn, warnIfMissed: false);
        await tester.pump();

        // Libera mutação
        completer.complete();
        await tester.pumpAndSettle();

        // Apenas uma mutação foi registrada
        expect(repo.recordedMutations.length, 1);
      },
    );

    // 11. Edição de nome
    testWidgets('11. Edição de nome envia identificador e novo nome', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository();
      await tester.pumpWidget(
        createTestApp(
          child: const IptvSourceForm(
            id: 'source-123',
            initialName: 'Nome Velho',
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editar fonte'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Nome Novo e Atualizado',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'https://provider.example.com/new.m3u',
      );
      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.payload['id'], 'source-123');
      expect(m.payload['name'], 'Nome Novo e Atualizado');
    });

    // 12. Alteração de credenciais
    testWidgets('12. Edição de Xtream permite atualizar credenciais', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository();
      await tester.pumpWidget(
        createTestApp(
          child: const IptvSourceForm(
            id: 'xtream-source-1',
            initialName: 'Servidor TV',
            initialFormat: 'xtream',
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL do servidor'),
        'https://novo.servidor.com:8443',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Usuário'),
        'novo_usuario',
      );
      await tester.enterText(
        find.byWidgetPredicate((w) => w is AppTextField && w.secret),
        'nova_senha_123',
      );
      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.payload['username'], 'novo_usuario');
      expect(m.payload['password'], 'nova_senha_123');
    });

    // 13. Preservação de senha não alterada
    testWidgets(
      '13. Deixar senha em branco na edição preserva a senha anterior',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository();
        await tester.pumpWidget(
          createTestApp(
            child: const IptvSourceForm(
              id: 'xtream-source-2',
              initialName: 'Servidor Manter Senha',
              initialFormat: 'xtream',
            ),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(AppTextField, 'URL do servidor'),
          'https://servidor.com:8443',
        );
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Usuário'),
          'usuario_existente',
        );
        // Senha deixada intencionalmente em branco!

        final saveBtn = find.widgetWithText(AppButton, 'Salvar');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // A validação PASSOU sem exigir senha na edição
        expect(repo.recordedMutations.length, 1);
        final m = repo.recordedMutations.first;
        expect(m.payload.containsKey('password'), isFalse);
        expect(m.payload['username'], 'usuario_existente');
      },
    );

    // 14. Sincronização solicitada
    testWidgets('14. Tela de detalhes permite solicitar sincronização manual', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository()
        ..sourcesList = [
          Entry('source-abc', {
            'name': 'Fonte Teste',
            'format': 'm3u',
            'status': 'ready',
            'host': 'live.example.com',
            'count': 50,
          }),
        ];

      await tester.pumpWidget(
        createTestApp(
          child: const IptvPage(id: 'source-abc'),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fonte Teste'), findsOneWidget);
      expect(find.text('Sincronizar agora'), findsOneWidget);

      final syncBtn = find.widgetWithText(AppButton, 'Sincronizar agora');
      await tester.ensureVisible(syncBtn);
      await tester.tap(syncBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      expect(repo.recordedMutations.first.action, 'syncSource');
      expect(repo.recordedMutations.first.payload['id'], 'source-abc');
    });

    // 15. Sincronização em andamento
    testWidgets(
      '15. Estado de sincronização em andamento é exibido adequadamente',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository()
          ..sourcesList = [
            Entry('source-sync', {
              'name': 'Fonte Sincronizando',
              'format': 'm3u',
              'status': 'syncing',
              'host': 'live.example.com',
              'count': 100,
            }),
          ];

        await tester.pumpWidget(
          createTestApp(
            child: const IptvPage(id: 'source-sync'),
            repo: repo,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Sincronizando'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    // 16. Sincronização concluída
    testWidgets('16. Fonte com sincronização concluída exibe resumo e data', (
      tester,
    ) async {
      setTestSize(tester);

      final syncDate = DateTime(2026, 10, 17, 10, 15);
      final repo = IptvMockRepository()
        ..sourcesList = [
          Entry('source-ready', {
            'name': 'Fonte Pronta',
            'format': 'xtream',
            'status': 'ready',
            'host': 'cdn.example.com',
            'count': 350,
            'lastSyncAt': syncDate.millisecondsSinceEpoch,
          }),
        ];

      await tester.pumpWidget(
        createTestApp(
          child: const IptvPage(id: 'source-ready'),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Online'), findsOneWidget);
      expect(find.text('350 itens'), findsOneWidget);
      expect(find.text('cdn.example.com'), findsOneWidget);
    });

    // 17. Falha de sincronização
    testWidgets('17. Falha de sincronização exibe mensagem compreensível', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository()
        ..sourcesList = [
          Entry('source-err', {
            'name': 'Fonte com Falha',
            'format': 'm3u',
            'status': 'error',
            'errorCode': 'catalog-sync-failed',
            'host': 'broken.example.com',
            'count': 45,
          }),
        ];

      await tester.pumpWidget(
        createTestApp(
          child: const IptvPage(id: 'source-err'),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          // Specific message for the backend code (no catalog published yet: nothing to keep).
          'Não foi possível concluir a sincronização.',
        ),
        findsOneWidget,
      );
    });

    // 18. Preservação do catálogo anterior
    testWidgets('18. Fonte com falha preserva contagem do catálogo anterior', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository()
        ..sourcesList = [
          Entry('source-err-count', {
            'name': 'Fonte Mantida',
            'format': 'm3u',
            'status': 'error',
            'errorCode': 'catalog-sync-failed',
            'host': 'prior.example.com',
            'count': 99,
          }),
        ];

      await tester.pumpWidget(
        createTestApp(
          child: const IptvPage(id: 'source-err-count'),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('99 itens'), findsOneWidget);
    });

    // 19. Exclusão confirmada
    testWidgets('19. Diálogo de exclusão confirmado executa deleteSource', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository()
        ..sourcesList = [
          Entry('source-del', {
            'name': 'Fonte Para Excluir',
            'format': 'm3u',
            'status': 'ready',
            'host': 'del.example.com',
          }),
        ];

      await tester.pumpWidget(
        createTestApp(
          child: const IptvPage(id: 'source-del'),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      final deleteBtn = find.widgetWithText(AppButton, 'Excluir fonte');
      await tester.ensureVisible(deleteBtn);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Excluir fonte IPTV?'), findsOneWidget);
      expect(
        find.text(
          'Esta ação removerá a fonte e os conteúdos vinculados no seu catálogo. Deseja continuar?',
        ),
        findsOneWidget,
      );

      // Confirma exclusão
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      expect(repo.recordedMutations.first.action, 'deleteSource');
      expect(repo.recordedMutations.first.payload['id'], 'source-del');
    });

    // 20. Exclusão cancelada
    testWidgets('20. Cancelar diálogo de exclusão não dispara exclusão', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository()
        ..sourcesList = [
          Entry('source-cancel', {
            'name': 'Fonte Segura',
            'format': 'm3u',
            'status': 'ready',
            'host': 'safe.example.com',
          }),
        ];

      await tester.pumpWidget(
        createTestApp(
          child: const IptvPage(id: 'source-cancel'),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      final deleteBtn = find.widgetWithText(AppButton, 'Excluir fonte');
      await tester.ensureVisible(deleteBtn);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Cancela
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.recordedMutations, isEmpty);
      expect(find.text('Fonte Segura'), findsOneWidget);
    });

    // 21. Restrições de permissões familiares
    testWidgets(
      '21. Membro associado na tela de detalhes não visualiza ações de sync/edit/delete',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository(admin: false)
          ..sourcesList = [
            Entry('source-view-only', {
              'name': 'Fonte Apenas Leitura',
              'format': 'm3u',
              'status': 'ready',
              'host': 'readonly.example.com',
              'count': 12,
            }),
          ];

        await tester.pumpWidget(
          createTestApp(
            child: const IptvPage(id: 'source-view-only'),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Fonte Apenas Leitura'), findsOneWidget);
        expect(find.text('Sincronizar agora'), findsNothing);
        expect(find.text('Editar fonte'), findsNothing);
        expect(find.text('Excluir fonte'), findsNothing);
      },
    );

    // 22. Atualização da lista após operações
    testWidgets('22. Lista atualiza em tempo real após inserção via stream', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository(sourcesList: []);
      await tester.pumpWidget(
        createTestApp(child: const ListIptvPage(), repo: repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma fonte IPTV'), findsOneWidget);

      // Emite nova fonte no stream
      repo.sourcesController.add([
        Entry('s-novo', {
          'name': 'Nova Fonte Transmitida',
          'format': 'm3u',
          'status': 'ready',
          'host': 'stream.example.com',
        }),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Nova Fonte Transmitida'), findsOneWidget);
      expect(find.text('Nenhuma fonte IPTV'), findsNothing);
    });

    // 23. Navegação entre telas
    testWidgets('23. Navegação da lista para detalhes e para edição', (
      tester,
    ) async {
      setTestSize(tester);

      final repo = IptvMockRepository()
        ..sourcesList = [
          Entry('source-nav', {
            'name': 'Fonte Navegação',
            'format': 'm3u',
            'status': 'ready',
            'host': 'nav.example.com',
          }),
        ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            initialRouteProvider.overrideWithValue('/iptv'),
          ],
          child: const IplexApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fonte Navegação'), findsOneWidget);

      // Toca na fonte para abrir detalhes
      await tester.tap(find.text('Fonte Navegação'));
      await tester.pumpAndSettle();

      expect(find.text('Fonte Navegação'), findsWidgets);
      expect(find.text('Sincronizar agora'), findsOneWidget);
    });

    // 24. Ausência de vazamento de credenciais
    testWidgets(
      '24. Credenciais de fontes nunca são exibidas na interface ou textos',
      (tester) async {
        setTestSize(tester);

        final repo = IptvMockRepository()
          ..sourcesList = [
            Entry('source-secret-check', {
              'name': 'Fonte Segura Sem Vazamentos',
              'format': 'xtream',
              'status': 'ready',
              'host': 'safe-server.example.com',
              'count': 100,
            }),
          ];

        await tester.pumpWidget(
          createTestApp(
            child: const IptvPage(id: 'source-secret-check'),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('password'), findsNothing);
        expect(find.textContaining('senha'), findsNothing);
        expect(find.textContaining('token'), findsNothing);
        expect(find.textContaining('username'), findsNothing);
        expect(find.textContaining('player_api.php'), findsNothing);
      },
    );
  });
}
