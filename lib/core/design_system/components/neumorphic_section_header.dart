import 'package:flutter/material.dart';

import '../tokens.dart';

class NeumorphicSectionHeader extends StatelessWidget {
  const NeumorphicSectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      ),
    ),
  );
}

/// Backward compatibility alias for NeumorphicSectionHeader
typedef SectionHeader = NeumorphicSectionHeader;
