import 'package:flutter/material.dart';

import '../tokens.dart';

/// Official geometric typographic wordmark for iPlex
class IplexWordmark extends StatelessWidget {
  const IplexWordmark({
    super.key,
    this.fontSize = 44.0,
    this.color = AppColors.textPrimary,
  });
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(
      style: TextStyle(
        fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        letterSpacing: -1.4,
        color: color,
      ),
      children: const [
        TextSpan(
          text: 'i',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        TextSpan(
          text: 'Plex',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
