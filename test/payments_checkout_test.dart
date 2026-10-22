import 'dart:async';

import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/repository.dart';
import 'package:aliens_syndicate_iplex_control/core/payments/store_billing.dart';
import 'package:aliens_syndicate_iplex_control/core/payments/subscription_checkout.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/subscription_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements ManagerRepository {
  _Repo({required this.checkout});
  bool checkout;
  Object? verifyFailure;
  final calls = <String>[];
  @override
  bool get configured => true;
  @override
  Stream<String?> authChanges() => Stream.value('u');
  @override
  Future<void> initializeAccount(String uid) async {}
  @override
  Stream<Account?> watchAccount(String uid) => Stream.value(
    Account(uid: uid, name: 'Admin', email: 'a@example.invalid', familyId: 'f'),
  );
  @override
  Stream<Family?> watchFamily(String id) =>
      Stream.value(Family(id: id, adminId: 'u', members: const {'u': 'admin'}));
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      Stream.value(const []);
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      Stream.value(Entry('subscription', const {'status': 'notStarted'}));
  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add(action);
    if (action == 'getPaymentsConfig') {
      return {
        'paymentsEnabled': checkout,
        'checkoutAllowed': checkout,
        'productId': 'iplex_playback',
        'basePlans': ['monthly', 'annual'],
        'packageName': 'com.alienssyndicate.iplex_control',
        'obfuscatedAccountId': 'acc',
      };
    }
    if (action == 'verifyPlayPurchase' && verifyFailure != null) {
      throw verifyFailure!;
    }
    return {'status': 'active'};
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

class _Store implements StoreBilling {
  final controller = StreamController<StoreEvent>.broadcast();
  final bought = <String>[];
  int completed = 0;
  int planQueries = 0;
  @override
  bool get supported => true;
  @override
  Stream<StoreEvent> get events => controller.stream;
  @override
  Future<List<StorePlan>> plans(
    String productId,
    List<String> basePlans,
  ) async {
    planQueries++;
    return const [
      StorePlan(basePlanId: 'monthly', price: r'R$ 9,90', native: 0),
      StorePlan(basePlanId: 'annual', price: r'R$ 99,90', native: 1),
    ];
  }

  @override
  Future<void> buy(StorePlan plan, {required String accountId}) async =>
      bought.add('${plan.basePlanId}:$accountId');
  @override
  Future<void> restore() async {}
  @override
  Uri manageUri(String productId, String packageName) => Uri();
  void purchased() => controller.add(
    StorePurchased(
      token: 'token',
      restored: false,
      complete: () async => completed++,
    ),
  );
}

Widget _host(_Repo repo, _Store store) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    storeBillingProvider.overrideWithValue(store),
  ],
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pt', 'BR'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const SubscriptionPage(),
  ),
);

Future<void> _open(WidgetTester tester, _Repo repo, _Store store) async {
  tester.view.physicalSize = const Size(1170, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(repo, store));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'switch off (default): coming soon, no purchase button, no store query',
    (tester) async {
      final repo = _Repo(checkout: false), store = _Store();
      await _open(tester, repo, store);
      expect(find.text('Assinaturas disponíveis em breve.'), findsOneWidget);
      expect(find.byKey(const Key('buy-monthly')), findsNothing);
      expect(store.planQueries, 0);
      expect(repo.calls, isNot(contains('verifyPlayPurchase')));
    },
  );

  testWidgets(
    'switch on: store prices, pending, verified purchase completed only after the backend',
    (tester) async {
      final repo = _Repo(checkout: true), store = _Store();
      await _open(tester, repo, store);
      expect(find.textContaining(r'R$ 9,90'), findsOneWidget);
      expect(find.textContaining(r'R$ 99,90'), findsOneWidget);
      await tester.tap(find.byKey(const Key('buy-annual')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.bought, ['annual:acc']);
      store.controller.add(const StorePending());
      await tester.pumpAndSettle();
      expect(find.textContaining('Pagamento pendente'), findsOneWidget);
      store.purchased();
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c == 'verifyPlayPurchase').length, 1);
      expect(store.completed, 1);
      expect(find.text('Assinatura confirmada.'), findsOneWidget);
    },
  );

  testWidgets(
    'rejected verification never completes the store purchase; cancel is reported',
    (tester) async {
      final repo = _Repo(checkout: true)
            ..verifyFailure = const AppFailure('purchase-invalid'),
          store = _Store();
      await _open(tester, repo, store);
      store.purchased();
      await tester.pumpAndSettle();
      expect(store.completed, 0);
      expect(
        find.textContaining('Não foi possível validar a compra'),
        findsOneWidget,
      );
      store.controller.add(const StoreCanceled());
      await tester.pumpAndSettle();
      expect(find.textContaining('Compra cancelada'), findsOneWidget);
    },
  );
}
