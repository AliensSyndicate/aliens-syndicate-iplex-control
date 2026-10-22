import 'package:flutter/widgets.dart';

import '../tokens.dart';

/// Horizontal scrollers of the app run from screen edge to screen edge: no
/// side margin, the same amount ([AppSpacing.lg]) as inner padding. Page
/// layouts that pad their children ([DetailsLayout], Busca…) leave children
/// wrapped in [EdgeToEdge] unpadded; [padded] wraps the others.
class EdgeToEdge extends StatelessWidget {
  const EdgeToEdge({super.key, required this.child});
  final Widget child;

  /// Side padding every horizontal scroller uses inside.
  static const inset = EdgeInsets.symmetric(horizontal: AppSpacing.lg);

  /// [children] with the page side margin, except the [EdgeToEdge] ones.
  static List<Widget> padded(List<Widget> children) => [
    for (final c in children)
      c is EdgeToEdge ? c : Padding(padding: inset, child: c),
  ];

  @override
  Widget build(BuildContext context) => child;
}
