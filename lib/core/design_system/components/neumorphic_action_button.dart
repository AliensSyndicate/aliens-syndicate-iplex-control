import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../graphite_surface.dart';
import '../tokens.dart';
import 'app_icon.dart';

/// Tactile Graphite Action Button
class NeumorphicActionButton extends StatefulWidget {
  const NeumorphicActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.destructive = false,
    this.radius = AppRadii.full,
    this.textColor,
  });

  const NeumorphicActionButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
  }) : destructive = true;

  const NeumorphicActionButton.red({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
  }) : destructive = true;

  final String label;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;
  final Widget? leading;
  final bool busy;
  final bool destructive;
  final double radius;
  final Color? textColor;

  @override
  State<NeumorphicActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<NeumorphicActionButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final motionDuration = AppMotion.duration(
      context,
      pressed ? AppMotion.pressIn : AppMotion.pressOut,
    );
    final motionCurve = pressed ? AppMotion.pressCurve : AppMotion.releaseCurve;

    final defaultColor = widget.destructive
        ? (widget.textColor ?? AppColors.error)
        : (widget.textColor ?? AppColors.textPrimary);
    final effectiveTextColor = enabled || widget.busy
        ? defaultColor
        : AppColors.textDisabled;

    final leading =
        widget.leading ??
        (widget.icon == null
            ? null
            : AppIcon(
                widget.icon!,
                size: AppDimensions.icon,
                color: enabled ? defaultColor : AppColors.textDisabled,
              ));

    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedScale(
        scale: pressed ? 0.985 : 1,
        duration: motionDuration,
        curve: motionCurve,
        child: GraphiteSurface(
          radius: widget.radius,
          recessed: pressed,
          finish: GraphiteFinish.button,
          child: Material(
            type: MaterialType.transparency,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: enabled
                  ? (_) {
                      if (!pressed) setState(() => pressed = true);
                    }
                  : null,
              onPointerUp: enabled
                  ? (_) {
                      if (pressed) setState(() => pressed = false);
                    }
                  : null,
              onPointerCancel: enabled
                  ? (_) {
                      if (pressed) setState(() => pressed = false);
                    }
                  : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(widget.radius),
                onTapDown: enabled
                    ? (_) {
                        if (!pressed) setState(() => pressed = true);
                      }
                    : null,
                onTapUp: enabled
                    ? (_) {
                        if (pressed) setState(() => pressed = false);
                      }
                    : null,
                onTapCancel: enabled
                    ? () {
                        if (pressed) setState(() => pressed = false);
                      }
                    : null,
                onHighlightChanged: (value) {
                  if (enabled && pressed != value) {
                    setState(() => pressed = value);
                  }
                },
                onTap: enabled
                    ? () {
                        HapticFeedback.selectionClick();
                        widget.onPressed!();
                      }
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppDimensions.button,
                    minWidth: double.infinity,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.busy)
                          const SizedBox.square(
                            dimension: AppDimensions.icon,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          ?leading,
                        if (widget.busy || leading != null)
                          const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: effectiveTextColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Backward compatibility alias for NeumorphicActionButton
typedef AppButton = NeumorphicActionButton;
