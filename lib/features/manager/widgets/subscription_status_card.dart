import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import '../../../core/domain/models.dart';

/// Displays server-owned metadata. Playback authorization stays on the server.
class SubscriptionStatusCard extends ConsumerWidget {
  const SubscriptionStatusCard({super.key, required this.subscription});
  final Entry? subscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final entry = subscription;
    final rawStatus = entry?.text('status');
    final end =
        entry?.number(rawStatus == 'trial' ? 'trialEndsAt' : 'paidUntil') ?? 0;
    final expired =
        ['trial', 'active', 'cancelled'].contains(rawStatus) &&
        end <= now.millisecondsSinceEpoch;
    final status = expired ? 'expired' : rawStatus;
    final plan = (entry?.text('basePlanId') ?? '').isNotEmpty
        ? entry!.text('basePlanId')
        : entry?.text('plan');
    return AppSurface(
      child: Column(
        children: [
          Text(switch (status) {
            'notStarted' => l.trialNotStarted,
            'trial' => l.trialActive,
            'active' => l.subscriptionActive,
            'cancelled' => l.subscriptionCancelled,
            'expired' => l.subscriptionExpired,
            'pending' => l.subscriptionPending,
            'lifetime' => l.subscriptionLifetime,
            _ => l.unavailable,
          }, style: Theme.of(context).textTheme.titleLarge),
          if (plan == 'monthly') Text(l.monthly),
          if (plan == 'annual') Text(l.annual),
          if (status == 'lifetime') Text(l.lifetime),
          if (end > 0 && status != 'lifetime')
            Text(
              DateFormat.yMMMd(Localizations.localeOf(context).toString())
                  .format(DateTime.fromMillisecondsSinceEpoch(end)),
            ),
        ],
      ),
    );
  }
}
