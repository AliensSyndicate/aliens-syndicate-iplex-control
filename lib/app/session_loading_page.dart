import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/providers.dart';
import '../core/domain/models.dart';
import '../core/design_system/components.dart';

class SessionLoadingPage extends ConsumerWidget {
  const SessionLoadingPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final account = ref.watch(accountProvider);
    final family = ref.watch(familyProvider);
    final failed = auth.hasError || account.hasError || family.hasError;
    final accountError = account.error;
    final appVerificationFailed = accountError is AppFailure &&
        accountError.code == 'app-verification-failed';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppDimensions.maxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  const IplexWordmark(fontSize: 54),
                  const SizedBox(height: AppSpacing.xl),
                  if (failed) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        appVerificationFailed
                            ? failureText(context, accountError)
                            : context.l.sessionLoadError,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: context.l.retry,
                      onPressed: () {
                        if (auth.hasError) ref.invalidate(authProvider);
                        if (account.hasError) ref.invalidate(accountProvider);
                        if (family.hasError) ref.invalidate(familyProvider);
                      },
                    ),
                    if (auth.asData?.value != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppButton.red(
                        label: context.l.logout,
                        onPressed: () async {
                          try {
                            await ref.read(repositoryProvider).signOut();
                          } catch (error) {
                            if (context.mounted) showFailure(context, error);
                          }
                        },
                      ),
                    ],
                  ] else ...[
                    const SizedBox.square(
                      dimension: AppTokens.icon,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        auth.isLoading
                            ? context.l.restoringSession
                            : context.l.loadingAccount,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
