import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import 'family_required_state.dart';

/// Family data is required by these operations, never by the Home route.
class FamilyScope extends ConsumerWidget {
  const FamilyScope({super.key, required this.child, this.onManage});
  final Widget child;
  final VoidCallback? onManage;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(accountProvider)
      .when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const AppLoadingSkeleton(),
        error: (e, s) =>
            ErrorState(onRetry: () => ref.invalidate(accountProvider)),
        data: (account) {
          if (account?.familyId == null) {
            return FamilyRequiredState(onManage: onManage);
          }
          return ref
              .watch(familyProvider)
              .when(
                skipLoadingOnRefresh: false,
                skipLoadingOnReload: false,
                loading: () => const AppLoadingSkeleton(),
                error: (e, s) =>
                    ErrorState(onRetry: () => ref.invalidate(familyProvider)),
                data: (family) => family == null
                    ? EmptyState(
                        title: context.l.familyUnavailable,
                        body: context.l.familyRequiredBody,
                        action: AppButton(
                          label: context.l.retry,
                          onPressed: () => ref.invalidate(familyProvider),
                        ),
                      )
                    : child,
              );
        },
      );
}
