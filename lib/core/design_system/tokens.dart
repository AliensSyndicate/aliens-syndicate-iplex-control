import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components/horizontal_page_transition.dart';

/// CODEX — iPlex | DARK INDUSTRIAL NEUMORPHISM DESIGN SYSTEM
/// Centralized Design Tokens based on physical matte graphite hardware.

abstract final class AppColors {
  // Calibrated Physical Graphite Palette from Reference Image
  static const backgroundPrimary = Color(0xFF39373A);
  static const backgroundDeep = Color(0xFF29292B);
  static const surfaceDefault = Color(0xFF353537);
  static const surfaceElevated = Color(0xFF414143);
  static const surfaceRecessed = Color(0xFF28282A);
  static const borderSubtle = Color(0xFF414143);
  static const borderLight = Color(0x17FFFFFF); // ~9% white highlight
  static const borderDark = Color(0x66000000); // ~40% black groove
  static const textPrimary = Color(0xFFE5E3E5);
  static const textSecondary = Color(0xFFB5B4B6);
  static const textDisabled = Color(0xFF6B696B);
  static const shadowDark = Color(0xFF000000);
  static const shadowLight = Color(0xFFFFFFFF);

  // Semantic & Brand Colors
  static const accent = Color(0xFFE5E3E5);
  static const brandBlue = Color(0xFF007AFF);
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFCCBA96);
  static const error = Color.fromARGB(255, 186, 71, 63);
  static const disabled = Color(0xFF636163);

  // Material values sampled and calibrated against the graphite reference.
  static const backgroundGradient = [
    Color(0xFF403E41),
    Color(0xFF39373C),
    Color(0xFF2C2C2C),
  ];
  static const grainLight = Color(0x08FFFFFF);
  static const grainDark = Color(0x09000000);
  static const groove = Color(0xFF101012);
  static const edgeShadow = Color(0xFF1A1A1C);
  static const edgeLight = Color(0xFF636365);
  static const faceLight = Color(0xFF4C4C4E);
  static const castShadow = Color(0x99000000);
  static const ambientHighlight = Color(0x16FFFFFF);
  static const insetShadow = Color(0xCC000000);
  static const insetHighlight = Color(0x29FFFFFF);
  static const panelGradient = [Color(0xFF403E41), Color(0xFF353336)];
  static const buttonGradient = [Color(0xFF28272A), Color(0xFF3F3D40)];
  static const elevatedGradient = [Color(0xFF3C3C3E), Color(0xFF2B2B2D)];
  static const pressedGradient = [Color(0xFF252527), Color(0xFF303032)];
  static const padOuterGradient = [
    Color(0xFF5F5D60),
    Color(0xFF3F3D40),
    Color(0xFF1E1E1E),
  ];
  static const padCenterGradient = [Color(0xFF484649), Color(0xFF3A383B)];
}

abstract final class AppSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class AppDimensions {
  static const avatar = 64.0;
  static const touch = 48.0;
  static const button = 56.0;
  static const input = 56.0;
  static const icon = 24.0;
  static const iconSmall = 18.0;
  static const iconLarge = 32.0;
  static const borderWidth = 1.0;
  static const borderBevel = 1.5;
  static const maxWidth = 620.0;
  static const bottomNav = 72.0;
}

abstract final class AppRadii {
  static const none = 0.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const card = 16.0;
  static const lg = 20.0;
  static const pill = 32.0;
  static const full = 999.0;
}

abstract final class AppShadows {
  // Simulated Light Source: Top-Left (135°)
  // Light rim: Top-Left | Dark ambient drop: Bottom-Right

  /// Raised surface (Buttons, D-Pad outer ring, Cards)
  static const elevated = [
    BoxShadow(
      color: Color(0x66000000), // ~40% black drop
      offset: Offset(4, 7),
      blurRadius: 16,
    ),
    BoxShadow(
      color: Color(0x14FFFFFF), // ~8% white top-left highlight
      offset: Offset(-2, -2),
      blurRadius: 5,
    ),
  ];

  /// Subtle elevated (Tiles, small controls)
  static const elevatedSmall = [
    BoxShadow(color: Color(0x59000000), offset: Offset(2, 4), blurRadius: 8),
    BoxShadow(color: Color(0x12FFFFFF), offset: Offset(-1, -1), blurRadius: 3),
  ];

  /// Pill button shadow (Login buttons, action triggers)
  static const pill = [
    BoxShadow(color: Color(0x73000000), offset: Offset(3, 6), blurRadius: 14),
    BoxShadow(
      color: Color(0x17FFFFFF),
      offset: Offset(-1.5, -1.5),
      blurRadius: 4,
    ),
  ];

  /// Physically pressed / inset shadow (Active buttons, cavities)
  static const pressed = [
    BoxShadow(color: Color(0x8C000000), offset: Offset(2, 3), blurRadius: 6),
    BoxShadow(color: Color(0x0FFFFFFF), offset: Offset(-1, -1), blurRadius: 2),
  ];

  /// Deep circular trench (D-pad cavity around OK button)
  static const deepTrench = [
    BoxShadow(
      color: Color(0xCC000000),
      offset: Offset(0, 4),
      blurRadius: 12,
      spreadRadius: 1,
    ),
  ];
}

abstract final class AppMotion {
  // Semantic Durations (calibrated for instantaneous tactile feedback)
  static const pressIn = Duration(milliseconds: 80);
  static const pressOut = Duration(milliseconds: 110);
  static const selection = Duration(milliseconds: 130);
  static const tabTransition = Duration(milliseconds: 100);
  static const pageEnter = Duration(milliseconds: 190);
  static const pageExit = Duration(milliseconds: 150);
  static const dialogEnter = Duration(milliseconds: 180);
  static const dialogExit = Duration(milliseconds: 140);

  // Backward-compatibility aliases
  static const fast = Duration(milliseconds: 130);
  static const standard = Duration(milliseconds: 190);

  // Calibrated Natural & Responsive Curves
  static const pressCurve = Curves.easeOutQuad;
  static const releaseCurve = Curves.easeOutCubic;
  static const selectionCurve = Curves.easeOutCubic;
  static const tabCurve = Curves.easeOutCubic;
  static const pageCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeOutCubic;
  static const dialogCurve = Curves.easeOutCubic;
  static const naturalCurve = Curves.easeOutCubic;

  /// Returns Duration.zero when reduced motion accessibility is active
  static Duration duration(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

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

  static const tagline = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 2.2,
    color: AppColors.textSecondary,
  );
}

abstract final class AppTheme {
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.backgroundPrimary,
      surface: AppColors.surfaceDefault,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
    ),
    textTheme: const TextTheme(
      headlineLarge: AppTypography.headlineLarge,
      headlineMedium: AppTypography.headlineMedium,
      titleLarge: AppTypography.titleLarge,
      bodyLarge: AppTypography.bodyLarge,
      bodyMedium: AppTypography.bodyMedium,
      labelSmall: AppTypography.labelSmall,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.focused)
              ? Colors.white
              : AppColors.textSecondary,
        ),
      ),
      filled: true,
      fillColor: AppColors.surfaceRecessed,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        borderSide: const BorderSide(color: AppColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        borderSide: const BorderSide(color: AppColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.backgroundPrimary,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.backgroundPrimary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceRecessed,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AppDimensions.touch, AppDimensions.touch),
      ),
    ),
    dividerColor: AppColors.borderSubtle,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _IplexPageTransitionsBuilder(),
        TargetPlatform.iOS: _IplexPageTransitionsBuilder(),
        TargetPlatform.macOS: _IplexPageTransitionsBuilder(),
        TargetPlatform.linux: _IplexPageTransitionsBuilder(),
        TargetPlatform.windows: _IplexPageTransitionsBuilder(),
      },
    ),
  );
}

class _IplexPageTransitionsBuilder extends PageTransitionsBuilder {
  const _IplexPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return HorizontalPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      curve: AppMotion.pageCurve,
      reverseCurve: AppMotion.exitCurve,
      child: child,
    );
  }
}

/// Backward compatibility facade mapping to the new modular token classes
abstract final class AppTokens {
  static const background = AppColors.backgroundPrimary;
  static const surface = AppColors.surfaceDefault;
  static const elevated = AppColors.surfaceElevated;
  static const recessed = AppColors.surfaceRecessed;
  static const buttonSurface = AppColors.surfaceDefault;

  static const text = AppColors.textPrimary;
  static const secondary = AppColors.textSecondary;
  static const border = AppColors.borderSubtle;
  static const light = AppColors.borderLight;
  static const dark = AppColors.borderDark;

  static const accent = AppColors.accent;
  static const brandBlue = AppColors.brandBlue;
  static const success = AppColors.success;
  static const warning = AppColors.warning;
  static const error = AppColors.error;
  static const disabled = AppColors.disabled;

  static const xs = AppSpacing.xs;
  static const sm = AppSpacing.sm;
  static const md = AppSpacing.md;
  static const lg = AppSpacing.lg;
  static const xl = AppSpacing.xl;
  static const xxl = AppSpacing.xxl;

  static const radius = AppRadii.lg;
  static const cardRadius = AppRadii.card;
  static const pillRadius = AppRadii.pill;
  static const buttonRadius = AppRadii.pill;

  static const touch = AppDimensions.touch;
  static const button = AppDimensions.button;
  static const icon = AppDimensions.icon;
  static const borderWidth = AppDimensions.borderWidth;
  static const maxWidth = AppDimensions.maxWidth;
  static const bottomNav = AppDimensions.bottomNav;

  static const fast = AppMotion.fast;
  static const standard = AppMotion.standard;
  static const pressIn = AppMotion.pressIn;
  static const pressOut = AppMotion.pressOut;
  static const selection = AppMotion.selection;
  static const tabTransition = AppMotion.tabTransition;
  static const pageEnter = AppMotion.pageEnter;
  static const pageExit = AppMotion.pageExit;
  static const dialogEnter = AppMotion.dialogEnter;
  static const dialogExit = AppMotion.dialogExit;

  static const raised = AppShadows.elevated;
  static const pillShadow = AppShadows.pill;
  static const pressed = AppShadows.pressed;

  static ThemeData get theme => AppTheme.darkTheme;
}
