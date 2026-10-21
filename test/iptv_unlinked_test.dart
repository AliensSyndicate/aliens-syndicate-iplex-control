import 'package:aliens_syndicate_iplex_control/app/bottom_navigation.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/list_iptv_page.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/iptv_source_form.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/family_required_state.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/widgets/iptv_empty_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'navigation_test.dart' as navigation;
import 'widget_test.dart' as fixtures;

class UnlinkedIptvRepository extends navigation.SessionRepository {
  UnlinkedIptvRepository({this.workspaceId}) : super(uid: 'u');
  String? workspaceId, currentFamilyId;
  bool saveFailure = false;
  final scopes = <String>[];
  final payloads = <Map<String, dynamic>>[];

  @override
  Account get account => Account(
    uid: 'u',
    locale: 'pt_BR',
    familyId: currentFamilyId,
    iptvWorkspaceId: workspaceId,
  );

  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) {
    if (collection == 'sources') scopes.add(familyId);
    return super.watchEntries(familyId, collection);
  }

  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      Stream.value(
        collection == 'sources'
            ? sources.where((e) => e.id == id).firstOrNull
            : null,
      );

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'saveSource') {
      if (saveFailure) throw const AppFailure('unavailable');
      workspaceId ??= 'private-iptv';
      payloads.add(Map.of(payload));
      sources = [
        Entry('source', {
          'name': payload['name'],
          'format': payload['format'],
          'host': 'example.com',
          'status': 'queued',
        }),
      ];
      accountEvents.add(account);
      sourcesEvents.add(sources);
    }
    mutations.add(action);
    return {'id': 'source'};
  }
}

void main() {
  setUpAll(fixtures.loadTestFont);

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(AppButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'IPTV without a family displays IPTV empty state instead of family setup',
    (tester) async {
      final container = await navigation.launch(
        tester,
        UnlinkedIptvRepository(),
        location: '/iptv',
      );
      expect(navigation.path(container), '/iptv');
      expect(find.byType(ListIptvPage), findsOneWidget);
      expect(find.byType(IptvEmptyState), findsOneWidget);
      expect(find.text('IPTV'), findsOneWidget);
      expect(find.text('Nenhuma fonte IPTV'), findsOneWidget);
      expect(find.text('Contas familiares'), findsNothing);
      expect(find.byType(FamilyRequiredState), findsNothing);
      expect(find.widgetWithText(AppButton, 'Adicionar fonte'), findsOneWidget);
      expect(
        tester.widget<BottomNavigation>(find.byType(BottomNavigation)).selected,
        3,
      );
      await fixtures.screenshot(tester, 'iptv-unlinked');
    },
  );

  testWidgets(
    'first source can be saved and managed without creating a family',
    (tester) async {
      final repo = UnlinkedIptvRepository();
      final container = await navigation.launch(
        tester,
        repo,
        location: '/iptv',
      );
      await tapButton(tester, 'Adicionar fonte');
      expect(navigation.path(container), '/iptv/add');
      expect(find.byType(IptvSourceForm), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'Minha IPTV');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'https://example.com/list.m3u',
      );
      await tapButton(tester, 'Salvar');
      expect(navigation.path(container), '/iptv');
      expect(find.text('Minha IPTV'), findsOneWidget);
      expect(repo.account.familyId, isNull);
      expect(repo.mutations.where((m) => m != 'getPaymentsConfig'), [
        'saveSource',
      ]);
      expect(repo.scopes, contains('private-iptv'));
      expect(find.text('Contas familiares'), findsNothing);
      container.read(routerProvider).go('/iptv/source');
      await tester.pumpAndSettle();
      await tapButton(tester, 'Sincronizar agora');
      expect(repo.mutations, contains('syncSource'));
      await tapButton(tester, 'Editar fonte');
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'IPTV atualizada',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'https://example.com/updated.m3u',
      );
      await tapButton(tester, 'Salvar');
      expect(repo.payloads.last['id'], 'source');
      expect(repo.payloads.last['name'], 'IPTV atualizada');
    },
  );

  testWidgets(
    'failed first save retains the form and allows retry without family setup',
    (tester) async {
      final repo = UnlinkedIptvRepository()..saveFailure = true;
      final container = await navigation.launch(
        tester,
        repo,
        location: '/iptv/add',
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Minha IPTV');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'https://example.com/list',
      );
      await tapButton(tester, 'Salvar');
      expect(navigation.path(container), '/iptv/add');
      expect(repo.workspaceId, isNull);
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(
        find.text(
          'Não foi possível conectar ao serviço. Verifique sua conexão e tente novamente.',
        ),
        findsOneWidget,
      );
      expect(find.text('https://example.com/list'), findsOneWidget);
      expect(find.byType(FamilyRequiredState), findsNothing);
      await tapButton(tester, 'Fechar');
      repo.saveFailure = false;
      await tapButton(tester, 'Salvar');
      expect(navigation.path(container), '/iptv');
      expect(find.text('Minha IPTV'), findsOneWidget);
    },
  );

  testWidgets(
    'personal IPTV remains editable after joining a family as a member',
    (tester) async {
      final repo = UnlinkedIptvRepository(workspaceId: 'private-iptv')
        ..sources = [
          Entry('source', {
            'name': 'Minha IPTV',
            'format': 'm3u',
            'host': 'example.com',
          }),
        ];
      final container = await navigation.launch(
        tester,
        repo,
        location: '/iptv',
      );
      repo.administrator = false;
      repo.currentFamilyId = 'family';
      repo.accountEvents.add(repo.account);
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/iptv/source/edit');
      await tester.pumpAndSettle();
      expect(navigation.path(container), '/iptv/source/edit');
      expect(find.byType(IptvSourceForm), findsOneWidget);
      expect(repo.scopes, everyElement('private-iptv'));
      container.read(routerProvider).go('/users/add');
      await tester.pumpAndSettle();
      expect(navigation.path(container), '/access');
    },
  );

  testWidgets(
    'personal catalog and search are available on Home without family',
    (tester) async {
      final repo = UnlinkedIptvRepository(workspaceId: 'private-iptv')
        ..sources = [
          Entry('source', {
            'name': 'Minha IPTV',
            'status': 'ready',
            'version': 'v',
          }),
        ];
      await navigation.launch(tester, repo);
      expect(find.text('Sua Home ainda está vazia'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'avail');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Available title'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'sem resultado');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Available title'), findsNothing);
      expect(repo.account.familyId, isNull);
    },
  );

  testWidgets(
    'Home configure IPTV action does not replace IPTV with family accounts',
    (tester) async {
      final container = await navigation.launch(
        tester,
        UnlinkedIptvRepository(),
      );
      await tester.tap(find.text('Configurar IPTV'));
      await tester.pumpAndSettle();
      expect(navigation.path(container), '/iptv');
      expect(find.text('Nenhuma fonte IPTV'), findsOneWidget);
      expect(find.text('Gerenciar contas familiares'), findsNothing);
      expect(find.byType(FamilyRequiredState), findsNothing);
    },
  );
}
