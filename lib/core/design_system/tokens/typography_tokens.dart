import 'package:flutter/painting.dart';

import 'color_tokens.dart';

/// Text styles.
abstract final class AppTypography {
  static const headlineLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -1.2,
    color: AppColors.textPrimary,
  );

  static const headlineMedium = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.8,
    color: AppColors.textPrimary,
  );

  static const titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.5,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  static const labelSmall = TextStyle(
    fontSize: 11,
    letterSpacing: 0.3,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}
