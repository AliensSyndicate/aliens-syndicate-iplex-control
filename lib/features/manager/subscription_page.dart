import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/data/subscription_provider.dart';
import '../../core/design_system/components.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/payments/subscription_checkout.dart';
import 'widgets/subscription_status_card.dart';

/// Informational plans are available to every authenticated Manager user.
/// Private family billing metadata remains restricted to its administrator.
class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final hasFamily =
        ref.watch(accountProvider).asData?.value?.resourceScopeId != null;
    final admin = ref.watch(canManageResourcesProvider);
    final lifetime =
        ref.watch(subscriptionProvider).asData?.value?.text('status') ==
        'lifetime';
    return Scaffold(
      body: PageTemplate(
        title: l.subscription,
        showBack: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.managerAccessTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(l.managerAccessBody),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (!hasFamily)
              Text(l.trialNotStarted)
            else if (!admin)
              Text(l.subscriptionManagedByAdmin)
            else
              ref
                  .watch(subscriptionProvider)
                  .when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => const AppLoadingSkeleton(rows: 1),
                    error: (e, s) => ErrorState(
                      onRetry: () => ref.invalidate(subscriptionProvider),
                    ),
                    data: (entry) =>
                        SubscriptionStatusCard(subscription: entry),
                  ),
            const SizedBox(height: AppSpacing.xl),
            const _Plans(),
            if (hasFamily && admin && !lifetime) ...[
              const SizedBox(height: AppSpacing.xl),
              const _CouponRedeem(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plans come from the store with the store's own prices. While the central
/// switch is off (default) nothing is purchasable and no store call is made.
class _Plans extends ConsumerWidget {
  const _Plans();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final admin = ref.watch(canManageResourcesProvider);
    final config = ref.watch(paymentsConfigProvider);
    final allowed = config.asData?.value.checkoutAllowed == true;
    if (!allowed || !admin) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EntryTile(title: l.trialPlan, subtitle: l.trialPlanBody),
          EntryTile(title: l.monthly, subtitle: l.comingSoon),
          EntryTile(title: l.annual, subtitle: l.comingSoon),
          EntryTile(title: l.lifetime, subtitle: l.lifetimeViaCoupon),
          Text(
            l.subscriptionsComingSoon,
            key: const Key('subscriptions-coming-soon'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      );
    }
    final lifetime =
        ref.watch(subscriptionProvider).asData?.value?.text('status') ==
        'lifetime';
    if (lifetime) {
      return EntryTile(title: l.lifetime, subtitle: l.subscriptionLifetime);
    }
    final checkout = ref.watch(checkoutControllerProvider);
    final cfg = config.requireValue;
    final message = switch (checkout.phase) {
      CheckoutPhase.pending => l.purchasePending,
      CheckoutPhase.verifying => l.purchaseVerifying,
      CheckoutPhase.confirmed => l.purchaseConfirmed,
      CheckoutPhase.canceled => l.purchaseCanceled,
      CheckoutPhase.failed => failureText(
        context,
        checkout.error ?? const Object(),
      ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.playbackSubscriptionNote,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        EntryTile(title: l.trialPlan, subtitle: l.trialPlanBody),
        const SizedBox(height: AppSpacing.sm),
        ref
            .watch(storePlansProvider)
            .when(
              loading: () => const AppLoadingSkeleton(rows: 2),
              error: (e, s) =>
                  ErrorState(onRetry: () => ref.invalidate(storePlansProvider)),
              data: (plans) => plans.isEmpty
                  ? Text(l.storeUnavailable)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final plan in plans) ...[
                          AppButton(
                            key: Key('buy-${plan.basePlanId}'),
                            label:
                                '${plan.basePlanId == 'annual' ? l.annual : l.monthly} · ${plan.price}',
                            busy: checkout.busy,
                            onPressed: checkout.busy
                                ? null
                                : () => ref
                                      .read(checkoutControllerProvider.notifier)
                                      .buy(plan),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
            ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            key: const Key('checkout-message'),
            textAlign: TextAlign.center,
          ),
        ],
        EntryTile(title: l.lifetime, subtitle: l.lifetimeViaCoupon),
        const SizedBox(height: AppSpacing.md),
        EntryTile(
          title: l.restorePurchases,
          icon: AppIcons.refresh,
          onTap: checkout.busy
              ? null
              : () => ref.read(checkoutControllerProvider.notifier).restore(),
        ),
        EntryTile(
          title: l.manageSubscriptionPlay,
          icon: AppIcons.link,
          onTap: () => launchUrl(
            ref
                .read(storeBillingProvider)
                .manageUri(cfg.productId, cfg.packageName),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
    );
  }
}

/// Lifetime access is unlocked only by a coupon validated on the server
/// (`redeemCoupon`); the subscription card updates from Firestore afterwards.
class _CouponRedeem extends ConsumerStatefulWidget {
  const _CouponRedeem();

  @override
  ConsumerState<_CouponRedeem> createState() => _CouponRedeemState();
}

class _CouponRedeemState extends ConsumerState<_CouponRedeem> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    final l = context.l;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(repositoryProvider).mutate('redeemCoupon', {'code': code});
      if (!mounted) return;
      _code.clear();
      setState(() {
        _failed = false;
        _message = l.couponRedeemed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = failureText(context, e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          key: const Key('coupon-code'),
          label: l.couponCode,
          controller: _code,
          hintText: 'IPLEX-XXXX-XXXX-XXXX',
        ),
        AppButton(
          key: const Key('redeem-coupon'),
          label: l.redeemCoupon,
          busy: _busy,
          onPressed: _busy ? null : _redeem,
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _message!,
            key: const Key('coupon-message'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _failed ? AppColors.error : null),
          ),
        ],
      ],
    );
  }
}
