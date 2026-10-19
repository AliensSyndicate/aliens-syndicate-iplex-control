import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../domain/models.dart';
import 'store_billing.dart';

/// Backend-owned checkout switch (`app_config/payments.paymentsEnabled`, false
/// when absent). It only gates checkout; playback rights come exclusively from
/// verified purchases on the server.
@immutable
class PaymentsConfig {
  const PaymentsConfig({
    required this.paymentsEnabled,
    required this.checkoutAllowed,
    required this.productId,
    required this.basePlans,
    required this.packageName,
    required this.accountId,
  });
  factory PaymentsConfig.fromMap(Map<String, dynamic> d) => PaymentsConfig(
        paymentsEnabled: d['paymentsEnabled'] == true,
        checkoutAllowed: d['checkoutAllowed'] == true,
        productId: d['productId'] as String? ?? '',
        basePlans: List<String>.from(d['basePlans'] as List? ?? const []),
        packageName: d['packageName'] as String? ?? '',
        accountId: d['obfuscatedAccountId'] as String? ?? '',
      );
  static const disabled = PaymentsConfig(
      paymentsEnabled: false, checkoutAllowed: false, productId: '', basePlans: [], packageName: '', accountId: '');
  final bool paymentsEnabled, checkoutAllowed;
  final String productId, packageName, accountId;
  final List<String> basePlans;
}

final storeBillingProvider = Provider<StoreBilling>((ref) => defaultStoreBilling());

final paymentsConfigProvider = FutureProvider.autoDispose<PaymentsConfig>((ref) async {
  final uid = ref.watch(accountProvider.select((a) => a.asData?.value?.uid));
  if (uid == null) return PaymentsConfig.disabled;
  try {
    return PaymentsConfig.fromMap(await ref.watch(repositoryProvider).mutate('getPaymentsConfig'));
  } on AppFailure {
    // Fail closed: an unknown switch state never offers checkout.
    return PaymentsConfig.disabled;
  }
});

final storePlansProvider = FutureProvider.autoDispose<List<StorePlan>>((ref) async {
  final config = await ref.watch(paymentsConfigProvider.future);
  final billing = ref.watch(storeBillingProvider);
  if (!config.checkoutAllowed || !billing.supported) return const [];
  return billing.plans(config.productId, config.basePlans);
});

enum CheckoutPhase { idle, purchasing, pending, verifying, confirmed, canceled, failed }

@immutable
class CheckoutState {
  const CheckoutState(this.phase, [this.error]);
  final CheckoutPhase phase;
  final Object? error;
  bool get busy => phase == CheckoutPhase.purchasing || phase == CheckoutPhase.verifying;
}

class CheckoutController extends Notifier<CheckoutState> {
  StreamSubscription<StoreEvent>? _events;

  @override
  CheckoutState build() {
    final billing = ref.watch(storeBillingProvider);
    _events = billing.events.listen(_onEvent);
    ref.onDispose(() => _events?.cancel());
    return const CheckoutState(CheckoutPhase.idle);
  }

  Future<void> _onEvent(StoreEvent event) async {
    switch (event) {
      case StorePending():
        state = const CheckoutState(CheckoutPhase.pending);
      case StoreCanceled():
        state = const CheckoutState(CheckoutPhase.canceled);
      case StoreFailed(:final code):
        state = CheckoutState(CheckoutPhase.failed, AppFailure(code));
      case StorePurchased(:final token, :final complete):
        state = const CheckoutState(CheckoutPhase.verifying);
        try {
          // The backend validates with Google, binds the token to this admin's
          // scope and acknowledges; only then is the store transaction finished.
          await ref.read(repositoryProvider).mutate('verifyPlayPurchase', {'purchaseToken': token});
          await complete();
          state = const CheckoutState(CheckoutPhase.confirmed);
        } catch (e) {
          state = CheckoutState(CheckoutPhase.failed, e);
        }
    }
  }

  Future<void> buy(StorePlan plan) async {
    if (state.busy) return;
    final config = await ref.read(paymentsConfigProvider.future);
    if (!config.checkoutAllowed) {
      state = const CheckoutState(CheckoutPhase.failed, AppFailure('payments-disabled'));
      return;
    }
    state = const CheckoutState(CheckoutPhase.purchasing);
    try {
      await ref.read(storeBillingProvider).buy(plan, accountId: config.accountId);
    } catch (e) {
      state = CheckoutState(CheckoutPhase.failed, e);
    }
  }

  Future<void> restore() async {
    if (state.busy) return;
    try {
      await ref.read(storeBillingProvider).restore();
    } catch (e) {
      state = CheckoutState(CheckoutPhase.failed, e);
    }
  }
}

final checkoutControllerProvider = NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);
