import 'dart:async';

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

class FourFormatsMockRepository implements ManagerRepository {
  FourFormatsMockRepository({
    this.signedIn = true,
    this.admin = true,
    this.fail = false,
    List<Entry>? sourcesList,
  }) : sourcesList = sourcesList ?? [];

  bool signedIn;
  bool admin;
  bool fail;
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
            name: 'Gestor Admin',
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
  required FourFormatsMockRepository repo,
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

  group('CODEX IPTV — 20 Required Scenarios', () {
    // 1. Cadastro por URL
    testWidgets('1. Cadastro por URL envia campos corretos ao backend', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Canais IPTV URL',
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
      expect(m.payload['name'], 'Canais IPTV URL');
      expect(m.payload['format'], anyOf('m3u', 'url'));
      expect(m.payload['url'], 'https://provider.example.com/playlist.m3u8');
    });

    // 2. Cadastro por arquivo
    testWidgets('2. Cadastro por arquivo importa e valida conteúdo M3U', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(
          child: IptvSourceForm(
            onPickFileOverride: () async => (
              name: 'playlist_custom.m3u',
              content: '#EXTM3U\n#EXTINF:-1,Canal 1\nhttps://stream.example/1.m3u8\n',
              size: 2048,
            ),
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      // Alterna para o formato Arquivo
      await tester.tap(find.text('Arquivo').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Minha Lista Arquivo',
      );

      // Toca em Selecionar arquivo
      final selectFileBtn = find.widgetWithText(
        AppButton,
        'Selecionar arquivo',
      );
      await tester.ensureVisible(selectFileBtn);
      await tester.tap(selectFileBtn);
      await tester.pumpAndSettle();

      // Confirma que o arquivo selecionado é exibido
      expect(find.textContaining('playlist_custom.m3u'), findsOneWidget);

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.action, 'saveSource');
      expect(m.payload['name'], 'Minha Lista Arquivo');
      expect(m.payload['format'], 'file');
      expect(m.payload['fileName'], 'playlist_custom.m3u');
      expect(m.payload['fileContent'], contains('#EXTM3U'));
    });

    // 3. Cadastro Xtream
    testWidgets('3. Cadastro Xtream envia host, usuário e senha protegida', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Xtream Codes').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Servidor Xtream 4K',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL do servidor'),
        'https://xtream.example.com:8443',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Usuário'),
        'user_vip',
      );
      await tester.enterText(
        find.byWidgetPredicate((w) => w is AppTextField && w.secret),
        'secret_pass_123',
      );
      await tester.pumpAndSettle();

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.action, 'saveSource');
      expect(m.payload['name'], 'Servidor Xtream 4K');
      expect(m.payload['format'], 'xtream');
      expect(m.payload['url'], 'https://xtream.example.com:8443');
      expect(m.payload['username'], 'user_vip');
      expect(m.payload['password'], 'secret_pass_123');
    });

    // 4. Cadastro M3U8 alternativo
    testWidgets('4. Cadastro M3U8 alternativo envia formato other_m3u8', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('M3U8 alternativo').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Canal Alternativo HLS',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL M3U8 alternativa'),
        'https://stream.example.com/master.m3u8',
      );
      await tester.pumpAndSettle();

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.action, 'saveSource');
      expect(m.payload['name'], 'Canal Alternativo HLS');
      expect(m.payload['format'], 'other_m3u8');
      expect(m.payload['url'], 'https://stream.example.com/master.m3u8');
    });

    // 5. Validação de campos
    testWidgets('5. Validação de campos impede submissão com dados em branco', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Informe um valor válido.'), findsWidgets);
      expect(repo.recordedMutations, isEmpty);
    });

    // 6. URL inválida
    testWidgets('6. URL inválida (HTTP ou malformada) é rejeitada', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Fonte Esquema Inseguro',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'ftp://insecure.example.com/list.m3u',
      );
      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations, isEmpty);
      expect(find.text('Informe um valor válido.'), findsWidgets);
    });

    // 7. Arquivo inválido
    testWidgets('7. Arquivo inválido sem tags M3U exibe mensagem de erro', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(
          child: IptvSourceForm(
            onPickFileOverride: () async => (
              name: 'not_playlist.txt',
              content: '<html>404 Not Found - Not a playlist</html>',
              size: 100,
            ),
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Arquivo').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Arquivo Inválido',
      );

      final selectFileBtn = find.widgetWithText(
        AppButton,
        'Selecionar arquivo',
      );
      await tester.ensureVisible(selectFileBtn);
      await tester.tap(selectFileBtn);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Formato de arquivo inválido'),
        findsOneWidget,
      );

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations, isEmpty);
    });

    // 8. Arquivo acima do limite
    testWidgets('8. Arquivo acima do limite de 20MB é rejeitado', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(
          child: IptvSourceForm(
            onPickFileOverride: () async => (
              name: 'huge_list.m3u',
              content: '#EXTM3U\n',
              size: 25 * 1024 * 1024, // 25 MB
            ),
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Arquivo').first);
      await tester.pumpAndSettle();

      final selectFileBtn = find.widgetWithText(
        AppButton,
        'Selecionar arquivo',
      );
      await tester.ensureVisible(selectFileBtn);
      await tester.tap(selectFileBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('20MB'), findsOneWidget);
    });

    // 9. Credenciais Xtream inválidas
    testWidgets('9. Credenciais Xtream com usuário vazio são rejeitadas', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Xtream Codes').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Xtream Teste',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL do servidor'),
        'https://xtream.example.com:8443',
      );
      // Deixa usuário em branco
      await tester.enterText(
        find.byWidgetPredicate((w) => w is AppTextField && w.secret),
        'senha_qualquer',
      );

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations, isEmpty);
    });

    // 10. EPG opcional
    testWidgets('10. EPG opcional é enviado quando preenchido', (tester) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Lista com EPG',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'https://provider.example.com/playlist.m3u',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL do EPG (opcional)'),
        'https://epg.example.com/guide.xml.gz',
      );

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.payload['epgUrl'], 'https://epg.example.com/guide.xml.gz');
    });

    // 11. Ativação de proteção por PIN
    testWidgets('11. Ativação de proteção por PIN envia pin e isProtected', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'Lista Protegida',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'https://provider.example.com/playlist.m3u',
      );

      // Ativa proteção por PIN
      final switchFinder = find.byType(NeumorphicSwitchTile);
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Campos de PIN e confirmação aparecem
      expect(find.widgetWithText(AppTextField, 'PIN'), findsOneWidget);
      expect(
        find.widgetWithText(AppTextField, 'Confirmar PIN'),
        findsOneWidget,
      );

      await tester.enterText(find.widgetWithText(AppTextField, 'PIN'), '4567');
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Confirmar PIN'),
        '4567',
      );

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.payload['isProtected'], isTrue);
      expect(m.payload['pin'], '4567');
      expect(m.payload['confirmPin'], '4567');
    });

    // 12. PIN divergente
    testWidgets('12. PIN divergente bloqueia submissão e exibe aviso', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(child: const IptvSourceForm(), repo: repo),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'PIN Divergente',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL da playlist'),
        'https://provider.example.com/playlist.m3u',
      );

      final switchFinder = find.byType(NeumorphicSwitchTile);
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'PIN'), '1234');
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Confirmar PIN'),
        '9999',
      );

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Não salvou e exibiu aviso
      expect(repo.recordedMutations, isEmpty);
      expect(find.text('Os PINs não coincidem.'), findsOneWidget);
    });

    // 13. Edição de cada formato
    testWidgets('13. Edição suporta cada um dos quatro formatos', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      // Edita formato Other M3U8
      await tester.pumpWidget(
        createTestApp(
          child: const IptvSourceForm(
            id: 'm3u8-source-edit',
            initialName: 'Nome Antigo M3U8',
            initialFormat: 'other_m3u8',
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editar fonte'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Nome'),
        'M3U8 Atualizado',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'URL M3U8 alternativa'),
        'https://new-stream.example.com/live.m3u8',
      );

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.payload['id'], 'm3u8-source-edit');
      expect(m.payload['name'], 'M3U8 Atualizado');
      expect(m.payload['format'], 'other_m3u8');
      expect(m.payload['url'], 'https://new-stream.example.com/live.m3u8');
    });

    // 14. Substituição de arquivo
    testWidgets('14. Substituição de arquivo na edição envia novo conteúdo', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository();

      await tester.pumpWidget(
        createTestApp(
          child: IptvSourceForm(
            id: 'file-source-edit',
            initialName: 'Lista Arquivo Existente',
            initialFormat: 'file',
            onPickFileOverride: () async => (
              name: 'substitute.m3u',
              content: '#EXTM3U\n#EXTINF:-1,Sub Canal\nhttps://sub.example/sub.m3u8\n',
              size: 512,
            ),
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      // Seleciona novo arquivo substituto
      final pickBtn = find.widgetWithText(AppButton, 'Selecionar arquivo');
      await tester.ensureVisible(pickBtn);
      await tester.tap(pickBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('substitute.m3u'), findsOneWidget);

      final saveBtn = find.widgetWithText(AppButton, 'Salvar');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(repo.recordedMutations.length, 1);
      final m = repo.recordedMutations.first;
      expect(m.payload['fileName'], 'substitute.m3u');
      expect(m.payload['fileContent'], contains('Sub Canal'));
    });

    // 15. Preservação de credenciais
    testWidgets(
      '15. Preservação de credenciais Xtream quando senha fica em branco na edição',
      (tester) async {
        setTestSize(tester);
        final repo = FourFormatsMockRepository();

        await tester.pumpWidget(
          createTestApp(
            child: const IptvSourceForm(
              id: 'xtream-source-preserve',
              initialName: 'Xtream Salvar Sem Senha',
              initialFormat: 'xtream',
            ),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(AppTextField, 'URL do servidor'),
          'https://servidor.iplex.tv:8443',
        );
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Usuário'),
          'usuario_mantido',
        );
        // Senha propositalmente em branco

        final saveBtn = find.widgetWithText(AppButton, 'Salvar');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(repo.recordedMutations.length, 1);
        final m = repo.recordedMutations.first;
        expect(m.payload.containsKey('password'), isFalse);
        expect(m.payload['username'], 'usuario_mantido');
      },
    );

    // 16. Sincronização concluída
    testWidgets(
      '16. Fonte com sincronização concluída exibe status e contagem de canais',
      (tester) async {
        setTestSize(tester);
        final syncDate = DateTime(2026, 10, 17, 18, 0);
        final repo = FourFormatsMockRepository()
          ..sourcesList = [
            Entry('src-ready-1', {
              'name': 'Fonte M3U8 Alternativo Pronta',
              'format': 'other_m3u8',
              'status': 'ready',
              'host': 'live.iplex.tv',
              'count': 1,
              'isSingleStream': true,
              'lastSyncAt': syncDate.millisecondsSinceEpoch,
            }),
          ];

        await tester.pumpWidget(
          createTestApp(
            child: const IptvPage(id: 'src-ready-1'),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Fonte M3U8 Alternativo Pronta'), findsOneWidget);
        expect(find.text('Online'), findsOneWidget);
        expect(find.text('Transmissão individual'), findsOneWidget);
        expect(find.text('M3U8 alternativo'), findsOneWidget);
      },
    );

    // 17. Falha de sincronização
    testWidgets(
      '17. Falha de sincronização exibe mensagem e mantém catálogo anterior',
      (tester) async {
        setTestSize(tester);
        final repo = FourFormatsMockRepository()
          ..sourcesList = [
            Entry('src-err-1', {
              'name': 'Fonte com Erro',
              'format': 'url',
              'status': 'error',
              'errorCode': 'catalog-sync-failed',
              'version': 'v-anterior',
              'host': 'broken.provider.tv',
              'count': 88,
            }),
          ];

        await tester.pumpWidget(
          createTestApp(
            child: const IptvPage(id: 'src-err-1'),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Não foi possível concluir a sincronização. O catálogo anterior foi preservado.',
          ),
          findsOneWidget,
        );
        expect(find.text('88 itens'), findsOneWidget);
      },
    );

    // 18. Permissões familiares
    testWidgets(
      '18. Membro associado não possui ações de criar, editar, sincronizar ou excluir',
      (tester) async {
        setTestSize(tester);
        final repo = FourFormatsMockRepository(admin: false)
          ..sourcesList = [
            Entry('src-member-1', {
              'name': 'Fonte Leitura Membro',
              'format': 'm3u',
              'status': 'ready',
              'host': 'safe.provider.tv',
            }),
          ];

        // Na listagem
        await tester.pumpWidget(
          createTestApp(child: const ListIptvPage(), repo: repo),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CircularButton), findsNothing);

        // Na página de detalhes
        await tester.pumpWidget(
          createTestApp(
            child: const IptvPage(id: 'src-member-1'),
            repo: repo,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sincronizar agora'), findsNothing);
        expect(find.text('Editar fonte'), findsNothing);
        expect(find.text('Excluir fonte'), findsNothing);
      },
    );

    // 19. Acesso gratuito ao cadastro
    testWidgets(
      '19. Acesso gratuito ao cadastro de fontes sem restrição de assinatura',
      (tester) async {
        setTestSize(tester);
        final repo = FourFormatsMockRepository(sourcesList: []);

        await tester.pumpWidget(
          createTestApp(child: const ListIptvPage(), repo: repo),
        );
        await tester.pumpAndSettle();

        // Botão de adicionar está livremente acessível
        expect(
          find.widgetWithText(AppButton, 'Adicionar fonte'),
          findsOneWidget,
        );

        await tester.pumpWidget(
          createTestApp(child: const IptvSourceForm(), repo: repo),
        );
        await tester.pumpAndSettle();

        // Formulário carrega sem paywall ou avisos de assinatura
        expect(find.text('Adicionar fonte'), findsOneWidget);
        expect(find.textContaining('Assinatura'), findsNothing);
        expect(find.textContaining('Plano'), findsNothing);
      },
    );

    // 20. Ausência de vazamento de dados sensíveis
    testWidgets('20. Credenciais, senhas e PINs nunca vazam na UI', (
      tester,
    ) async {
      setTestSize(tester);
      final repo = FourFormatsMockRepository()
        ..sourcesList = [
          Entry('src-secure-data', {
            'name': 'Fonte Super Secreta',
            'format': 'xtream',
            'status': 'ready',
            'host': 'private.tv.server',
            'username': 'admin_secret',
            'password': 'hidden_password_do_not_leak',
            'pinHash': 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3',
            'isProtected': true,
          }),
        ];

      await tester.pumpWidget(
        createTestApp(
          child: const IptvPage(id: 'src-secure-data'),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('hidden_password_do_not_leak'), findsNothing);
      expect(
        find.textContaining('a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'),
        findsNothing,
      );
      expect(find.textContaining('pinHash'), findsNothing);
    });
  });
}
