import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../graphite_surface.dart';
import '../tokens.dart';
import 'app_icon.dart';

/// Pill action button: secondary (default), [primary] or destructive.
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
  }) : primary = false;

  /// Main action of a screen or sheet: green fill, black text.
  const NeumorphicActionButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
  }) : destructive = false,
       primary = true;

  const NeumorphicActionButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
  }) : destructive = true,
       primary = false;

  const NeumorphicActionButton.red({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
  }) : destructive = true,
       primary = false;

  final String label;
  final bool primary;
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

    // Destructive: red fill, white text. Primary: green fill, black text.
    // Default (secondary): grey fill, white text.
    final filled = widget.destructive || widget.primary;
    final defaultColor =
        widget.textColor ??
        (widget.primary ? AppColors.onPrimary : AppColors.textPrimary);
    final fill = widget.destructive ? AppColors.error : AppColors.primary;
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
        child: _Fill(
          filled: filled,
          color: enabled || widget.busy ? fill : AppColors.disabled,
          radius: widget.radius,
          pressed: pressed,
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
                          SizedBox.square(
                            dimension: AppDimensions.icon,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: defaultColor,
                            ),
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
                              fontWeight: filled
                                  ? FontWeight.w700
                                  : FontWeight.w500,
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

/// Background of an [AppButton]: the flat control surface, or a solid fill
/// (primary / destructive), slightly darker while pressed.
class _Fill extends StatelessWidget {
  const _Fill({
    required this.filled,
    required this.color,
    required this.radius,
    required this.pressed,
    required this.child,
  });
  final bool filled, pressed;
  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!filled) {
      return GraphiteSurface(
        radius: radius,
        recessed: pressed,
        finish: GraphiteFinish.button,
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pressed ? Color.lerp(color, Colors.black, 0.15) : color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
