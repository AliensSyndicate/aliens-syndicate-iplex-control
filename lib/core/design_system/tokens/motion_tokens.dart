import 'package:flutter/material.dart';

/// Durations and curves.
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

  // Curves
  static const pressCurve = Curves.easeOutQuad;
  static const releaseCurve = Curves.easeOutCubic;
  static const pageCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeOutCubic;

  /// Returns Duration.zero when reduced motion accessibility is active
  static Duration duration(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
