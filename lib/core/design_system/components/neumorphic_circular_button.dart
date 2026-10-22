import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../graphite_surface.dart';
import '../tokens.dart';
import 'app_icon.dart';

/// Physical circular control button from the Dark Neumorphic reference image
class NeumorphicCircularButton extends StatefulWidget {
  const NeumorphicCircularButton({
    super.key,
    required this.label,
    this.icon,
    this.child,
    this.onPressed,
    this.selected = false,
    this.size = AppDimensions.touch,
    this.hasSocket = false,
    this.onPad = false,
    this.finish = GraphiteFinish.button,
  });

  final String label;
  final List<List<dynamic>>? icon;
  final Widget? child;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final bool hasSocket;
  final bool onPad;
  final GraphiteFinish finish;

  @override
  State<NeumorphicCircularButton> createState() =>
      _NeumorphicCircularButtonState();
}

class _NeumorphicCircularButtonState extends State<NeumorphicCircularButton> {
  @override
  Widget build(BuildContext context) {
    // Only the chosen state changes the surface: a tap has no press effect.
    final isInset = widget.selected;
    final enabled = widget.onPressed != null;
    final size = widget.size < AppDimensions.touch
        ? AppDimensions.touch
        : widget.size;
    final content =
        widget.child ??
        (widget.icon == null
            ? const SizedBox.shrink()
            : AppIcon(
                widget.icon!,
                size: widget.onPad ? AppDimensions.icon : size * 0.40,
                color: enabled
                    ? (widget.selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary)
                    : AppColors.textDisabled,
              ));
    final motionDuration = AppMotion.duration(context, AppMotion.selection);
    const motionCurve = AppMotion.releaseCurve;

    Widget surface = widget.onPad
        ? AnimatedContainer(
            duration: motionDuration,
            curve: motionCurve,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isInset ? AppColors.borderDark : Colors.transparent,
            ),
            child: Center(child: content),
          )
        : GraphiteSurface(
            circle: true,
            recessed: isInset,
            finish: widget.finish,
            child: SizedBox.square(
              dimension: size,
              child: Center(child: content),
            ),
          );

    if (widget.hasSocket) {
      surface = GraphiteSurface(
        circle: true,
        recessed: true,
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: surface,
      );
    }

    final interactive = Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const CircleBorder(),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: AppColors.borderLight,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        onLongPress: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: surface),
        ),
      ),
    );

    Widget result = Semantics(
      button: true,
      selected: widget.selected,
      enabled: enabled,
      label: widget.label,
      onTap: enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: interactive,
    );

    if (widget.label.isNotEmpty) {
      result = Tooltip(message: widget.label, child: result);
    }

    return result;
  }
}

/// Backward compatibility alias for NeumorphicCircularButton
typedef CircularButton = NeumorphicCircularButton;
