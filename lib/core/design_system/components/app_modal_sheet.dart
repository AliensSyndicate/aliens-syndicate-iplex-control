import 'package:flutter/material.dart';

import '../tokens.dart';

/// Standard Reusable App Modal Bottom Sheet
class AppModalSheet extends StatelessWidget {
  const AppModalSheet({
    super.key,
    this.title,
    this.description,
    this.content,
    this.leading,
    this.actions,
    this.padding,
    this.child,
  });

  final String? title;
  final String? description;
  final Widget? content;
  final Widget? leading;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding:
                padding ??
                const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
            child:
                child ??
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leading != null) ...[
                      Center(child: leading!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (title != null && title!.isNotEmpty) ...[
                      Text(
                        title!,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        description!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (content != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      content!,
                    ],
                    if (actions != null && actions!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      for (int i = 0; i < actions!.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        actions![i],
                      ],
                    ],
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

/// Displays a standard modal bottom sheet matching the app design system:
/// - Occupies only the necessary height
/// - Animated slide-up
/// - Reusable with title, description, content, and fill buttons
/// - Without pill indicator
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  String? title,
  String? description,
  Widget? content,
  Widget? leading,
  List<Widget>? actions,
  Widget? child,
  WidgetBuilder? builder,
  bool isDismissible = true,
  bool enableDrag = true,
  EdgeInsetsGeometry? padding,
  bool useRootNavigator = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    backgroundColor: AppColors.surfaceDefault,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      side: BorderSide(
        color: AppColors.borderLight,
        width: AppDimensions.borderWidth,
      ),
    ),
    builder:
        builder ??
        (sheetContext) => AppModalSheet(
          title: title,
          description: description,
          content: content,
          leading: leading,
          actions: actions,
          padding: padding,
          child: child,
        ),
  );
}
