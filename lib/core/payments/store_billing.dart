import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// A store plan as priced by the store itself (never a hard-coded price).
@immutable
class StorePlan {
  const StorePlan({
    required this.basePlanId,
    required this.price,
    required this.native,
  });
  final String basePlanId;
  final String price;
  final Object native;
}

/// Store events the subscription controller reacts to.
sealed class StoreEvent {
  const StoreEvent();
}

class StorePending extends StoreEvent {
  const StorePending();
}

class StoreCanceled extends StoreEvent {
  const StoreCanceled();
}

class StoreFailed extends StoreEvent {
  const StoreFailed(this.code);
  final String code;
}

/// A purchase the backend must verify before it is completed (acknowledged).
class StorePurchased extends StoreEvent {
  const StorePurchased({
    required this.token,
    required this.complete,
    required this.restored,
  });
  final String token;
  final Future<void> Function() complete;
  final bool restored;
}

/// Multiplatform seam: Google Play now, App Store later, nothing else changes.
abstract interface class StoreBilling {
  bool get supported;
  Stream<StoreEvent> get events;
  Future<List<StorePlan>> plans(String productId, List<String> basePlans);
  Future<void> buy(StorePlan plan, {required String accountId});
  Future<void> restore();
  Uri manageUri(String productId, String packageName);
}

class UnsupportedStoreBilling implements StoreBilling {
  const UnsupportedStoreBilling();
  @override
  bool get supported => false;
  @override
  Stream<StoreEvent> get events => const Stream.empty();
  @override
  Future<List<StorePlan>> plans(
    String productId,
    List<String> basePlans,
  ) async => const [];
  @override
  Future<void> buy(StorePlan plan, {required String accountId}) async =>
      throw UnsupportedError('store-unavailable');
  @override
  Future<void> restore() async {}
  @override
  Uri manageUri(String productId, String packageName) => Uri();
}

/// Google Play Billing through the official in_app_purchase plugin.
class GooglePlayStoreBilling implements StoreBilling {
  GooglePlayStoreBilling([InAppPurchase? iap])
    : _iap = iap ?? InAppPurchase.instance;
  final InAppPurchase _iap;
  GooglePlayPurchaseDetails? _active;

  @override
  bool get supported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<StoreEvent> get events =>
      _iap.purchaseStream.expand((list) => list.map(_map));

  StoreEvent _map(PurchaseDetails p) {
    switch (p.status) {
      case PurchaseStatus.pending:
        return const StorePending();
      case PurchaseStatus.canceled:
        return const StoreCanceled();
      case PurchaseStatus.error:
        return StoreFailed(p.error?.code ?? 'store-error');
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        if (p is GooglePlayPurchaseDetails) _active = p;
        return StorePurchased(
          token: p.verificationData.serverVerificationData,
          restored: p.status == PurchaseStatus.restored,
          complete: () async {
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          },
        );
    }
  }

  @override
  Future<List<StorePlan>> plans(
    String productId,
    List<String> basePlans,
  ) async {
    if (!supported || !await _iap.isAvailable()) return const [];
    final response = await _iap.queryProductDetails({productId});
    final plans = <StorePlan>[];
    for (final details
        in response.productDetails.whereType<GooglePlayProductDetails>()) {
      final offers = details.productDetails.subscriptionOfferDetails;
      final index = details.subscriptionIndex;
      if (offers == null || index == null) continue;
      final offer = offers[index];
      // Only the base plans themselves: no promotional or free-trial offers.
      if (offer.offerId != null || !basePlans.contains(offer.basePlanId)) {
        continue;
      }
      plans.add(
        StorePlan(
          basePlanId: offer.basePlanId,
          price: details.price,
          native: details,
        ),
      );
    }
    plans.sort(
      (a, b) => basePlans
          .indexOf(a.basePlanId)
          .compareTo(basePlans.indexOf(b.basePlanId)),
    );
    return plans;
  }

  @override
  Future<void> buy(StorePlan plan, {required String accountId}) async {
    final details = plan.native as GooglePlayProductDetails;
    final current = _active;
    await _iap.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: details,
        applicationUserName: accountId,
        // Monthly <-> annual: replace the running subscription instead of stacking two.
        changeSubscriptionParam:
            current == null ||
                current.billingClientPurchase.isAutoRenewing == false
            ? null
            : ChangeSubscriptionParam(
                oldPurchaseDetails: current,
                replacementMode: ReplacementMode.withTimeProration,
              ),
      ),
    );
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Uri manageUri(String productId, String packageName) => Uri.https(
    'play.google.com',
    '/store/account/subscriptions',
    {'sku': productId, 'package': packageName},
  );
}

StoreBilling defaultStoreBilling() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? GooglePlayStoreBilling()
    : const UnsupportedStoreBilling();
