import 'package:flutter/material.dart';

import '../tokens.dart';

/// Brazilian age rating seal (ClassInd — Guia Prático da Classificação
/// Indicativa / ABNT NBR 15290 for accessibility): square seal with the
/// regulated color of each age and the age (or "L") in the center. These
/// colors are regulatory, not part of the iPlex palette, and are used only here.
class AgeRatingBadge extends StatelessWidget {
  const AgeRatingBadge(this.rating, {super.key, this.size = 32});

  /// Normalized rating: `L`, `10`, `12`, `14`, `16` or `18`.
  final String rating;
  final double size;

  static const _seal = <String, (Color, Color)>{
    'L': (Color(0xFF0C9447), Colors.white),
    '10': (Color(0xFF0F7DC2), Colors.white),
    '12': (Color(0xFFF8C411), Colors.black),
    '14': (Color(0xFFE67824), Colors.white),
    '16': (Color(0xFFDB2827), Colors.white),
    '18': (Color(0xFF1D1815), Colors.white),
  };

  /// Brazilian rating from a TMDB certification or a source value
  /// ("L", "Livre", "AL", "14", "A14", "16 anos"…); null when it is not one.
  static String? normalize(String? value) {
    final raw = (value ?? '').trim().toUpperCase();
    if (raw.isEmpty) return null;
    if (raw == 'L' || raw == 'AL' || raw.startsWith('LIVRE')) return 'L';
    final age = RegExp(r'^A?(10|12|14|16|18)(\s*ANOS)?$').firstMatch(raw);
    return age?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _seal[rating] ?? _seal['18']!;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        // Contrast on the dark background for the black "18" seal.
        border: rating == '18'
            ? Border.all(color: AppColors.textSecondary, width: 1)
            : null,
      ),
      child: Text(
        rating,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.45,
          height: 1,
        ),
      ),
    );
  }
}
