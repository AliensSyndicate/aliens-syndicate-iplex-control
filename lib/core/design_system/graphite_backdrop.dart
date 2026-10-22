import 'package:flutter/material.dart';

import 'tokens.dart';

/// Solid page background shared by every screen (also the color of the main
/// menu, which must stay opaque).
class GraphiteBackdrop extends StatelessWidget {
  const GraphiteBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppColors.backgroundPrimary, child: child);
}
