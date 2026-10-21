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
        child: SheetDragDismiss(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
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
      ),
    );
  }
}

/// A scrollable inside a sheet swallows the sheet's own drag gesture. This
/// restores it: pulling the content down past its top closes the sheet.
class SheetDragDismiss extends StatefulWidget {
  const SheetDragDismiss({super.key, required this.child});
  final Widget child;

  @override
  State<SheetDragDismiss> createState() => _SheetDragDismissState();
}

class _SheetDragDismissState extends State<SheetDragDismiss> {
  static const _threshold = 72.0;
  double _pulled = 0;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _pulled = 0;
    } else if (n is OverscrollNotification && n.dragDetails != null) {
      _pulled -= n.overscroll;
    } else if (n is ScrollUpdateNotification &&
        n.dragDetails != null &&
        n.metrics.pixels < 0) {
      _pulled = -n.metrics.pixels;
    } else if (n is ScrollEndNotification) {
      if (_pulled >= _threshold) Navigator.of(context).maybePop();
      _pulled = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
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
  Color backgroundColor = AppColors.surfaceDefault,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    // Every sheet, even a full-screen one, keeps a top margin equal to the
    // device status bar (project rule).
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    backgroundColor: backgroundColor,
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
