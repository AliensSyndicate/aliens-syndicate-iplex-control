import 'package:flutter/painting.dart';

/// Colors: surfaces, borders, text and semantic colors.
abstract final class AppColors {
  // Dark minimalist palette (Spotify-inspired redesign, 22/10/2026): near
  // black screens and menu, neutral grey surfaces, green as the main color.
  static const backgroundPrimary = Color(0xFF121212);
  static const backgroundDeep = Color(0xFF121212);

  /// Cards, list tiles, panels.
  static const surfaceDefault = Color(0xFF1F1F1F);

  /// Buttons, inputs, unselected tabs/chips, skeleton blocks.
  static const surfaceElevated = Color(0xFF2A2A2A);

  /// Pressed / highlighted surfaces.
  static const surfacePressed = Color(0xFF333333);

  /// Bottom sheets and recessed areas.
  static const surfaceRecessed = Color(0xFF181818);

  /// Main menu (and the system navigation bar under it): translucent page
  /// background, so the content shows through.
  static const navigationBar = Color(0xD9121212);

  /// Dark veil over images (play marks, camera overlays).
  static const scrim = Color(0x8C000000);

  /// Fade of a full-bleed cover into the black page (top to bottom).
  static const coverFade = [
    Color(0x59000000),
    Color(0x00000000),
    Color(0x00000000),
    Color(0x99000000),
    Color(0xE6000000),
    Color(0xFF000000),
  ];
  static const borderSubtle = Color(0xFF2A2A2A);

  /// Hairline divider / outline on dark surfaces.
  static const borderLight = Color(0x1AFFFFFF);
  static const borderDark = Color(0x14FFFFFF);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const textDisabled = Color(0xFF6A6A6A);

  // Semantic colors
  /// Main color of the app (solid white): selection, active state,
  /// primary action, online status.
  static const primary = Color(0xFFFFFFFF);
  static const onPrimary = Color(0xFF0F0F0F);

  /// Pressed fill of a primary button (web `.iplex-button-primary:hover`).
  static const primaryPressed = Color(0xFFF1F1F1);

  /// Active / highlighted state (same as [primary]).
  static const accent = primary;

  /// Legacy name of the focus/selection color: the main color (white).
  static const brandBlue = primary;
  static const success = primary;
  static const warning = Color(0xFFCCBA96);
  static const error = Color(0xFFE5534B);

  /// IPTV state dots: on (green), no connection / any failure ([error],
  /// red) and off ([disabled], grey).
  static const statusOn = Color(0xFF1ED760);
  static const disabled = Color(0xFF535353);
}
