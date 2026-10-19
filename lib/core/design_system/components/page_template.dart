import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../icons.dart';
import '../tokens.dart';
import 'neumorphic_circular_button.dart';

/// Page Template applying the Dark Industrial Graphite layout
class PageTemplate extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final bool? showBack;
  final VoidCallback? onBack;
  final EdgeInsetsGeometry? padding;
  final bool hasBottomNav;

  const PageTemplate({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.subtitle,
    this.showBack,
    this.onBack,
    this.padding,
    this.hasBottomNav = false,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? (ModalRoute.of(context)?.canPop ?? false);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppDimensions.maxWidth),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppDimensions.touch,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (canPop) ...[
                              CircularButton(
                                label: AppLocalizations.of(context).back,
                                icon: AppIcons.left,
                                size: AppDimensions.touch,
                                onPressed:
                                    onBack ??
                                    () => Navigator.of(context).maybePop(),
                              ),
                              const SizedBox(width: AppSpacing.md),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                style: AppTypography.headlineMedium,
                              ),
                            ),
                            ?action,
                          ],
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: padding ??
                    EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      hasBottomNav
                          ? (AppSpacing.xl + AppDimensions.bottomNav)
                          : AppSpacing.xl,
                    ),
                sliver: SliverToBoxAdapter(child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
