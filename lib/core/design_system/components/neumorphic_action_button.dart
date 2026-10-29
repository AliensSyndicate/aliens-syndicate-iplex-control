import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../graphite_surface.dart';
import '../tokens.dart';
import 'app_icon.dart';

/// Pill action button: secondary (default), [primary] or destructive.
class NeumorphicActionButton extends StatefulWidget {
  const NeumorphicActionButton({
    super.key,
    this.label = '',
    this.semanticsLabel,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.destructive = false,
    this.radius = AppRadii.full,
    this.textColor,
    this.height,
    this.width,
    this.fit = false,
  }) : primary = false;

  /// Main action of a screen or sheet: same as the web `.iplex-button-primary`
  /// (white fill, #0F0F0F text, medium weight).
  const NeumorphicActionButton.primary({
    super.key,
    this.label = '',
    this.semanticsLabel,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
    this.height,
    this.width,
    this.fit = false,
  }) : destructive = false,
       primary = true;

  const NeumorphicActionButton.destructive({
    super.key,
    this.label = '',
    this.semanticsLabel,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
    this.height,
    this.width,
    this.fit = false,
  }) : destructive = true,
       primary = false;

  const NeumorphicActionButton.red({
    super.key,
    this.label = '',
    this.semanticsLabel,
    this.onPressed,
    this.icon,
    this.leading,
    this.busy = false,
    this.radius = AppRadii.full,
    this.textColor,
    this.height,
    this.width,
    this.fit = false,
  }) : destructive = true,
       primary = false;

  final String label;
  final String? semanticsLabel;
  final bool primary;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;
  final Widget? leading;
  final bool busy;
  final bool destructive;
  final double radius;
  final Color? textColor;
  final double? height;
  final double? width;

  /// As wide as its content (with a label it otherwise fills the width).
  final bool fit;

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

    // Destructive: red fill, white text. Primary: white fill, dark text.
    // Default (secondary): grey fill, white text.
    final filled = widget.destructive || widget.primary;
    final defaultColor =
        widget.textColor ??
        (widget.primary ? AppColors.onPrimary : AppColors.textPrimary);
    final fill = widget.destructive ? AppColors.error : AppColors.primary;
    // Primary mirrors the web `.iplex-button-primary`: disabled fades the
    // whole button (opacity 0.45) instead of greying it.
    final fadesWhenDisabled = widget.primary && !enabled && !widget.busy;
    final effectiveTextColor = enabled || widget.busy || widget.primary
        ? defaultColor
        : AppColors.textDisabled;

    final leading =
        widget.leading ??
        (widget.icon == null
            ? null
            : AppIcon(
                widget.icon!,
                size: AppDimensions.icon,
                color: enabled || widget.primary
                    ? defaultColor
                    : AppColors.textDisabled,
              ));

    final hasLabel = widget.label.isNotEmpty;
    final minH = widget.height ?? AppDimensions.button;
    final minW =
        widget.width ?? (hasLabel && !widget.fit ? double.infinity : minH);
    final maxW = widget.width ?? double.infinity;
    final maxH = widget.height ?? double.infinity;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? (hasLabel ? widget.label : null),
      child: AnimatedScale(
        scale: pressed ? 0.985 : 1,
        duration: motionDuration,
        curve: motionCurve,
        child: Opacity(
          opacity: fadesWhenDisabled ? 0.45 : 1,
          child: _Fill(
            filled: filled,
            color: enabled || widget.busy || widget.primary
                ? fill
                : AppColors.disabled,
            pressedColor: widget.primary ? AppColors.primaryPressed : null,
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
                    constraints: BoxConstraints(
                      minHeight: minH,
                      maxHeight: maxH,
                      minWidth: minW,
                      maxWidth: maxW,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: hasLabel ? AppSpacing.lg : AppSpacing.sm,
                        vertical: widget.height != null ? 0 : AppSpacing.md,
                      ),
                      child: Center(
                        widthFactor: widget.fit ? 1 : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize:
                              hasLabel && widget.width == null && !widget.fit
                              ? MainAxisSize.max
                              : MainAxisSize.min,
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
                            if (hasLabel && (widget.busy || leading != null))
                              const SizedBox(width: AppSpacing.md),
                            if (hasLabel)
                              Flexible(
                                child: Text(
                                  widget.label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: effectiveTextColor,
                                    fontSize: 16,
                                    fontWeight: widget.destructive
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
    this.pressedColor,
  });
  final bool filled, pressed;
  final Color color;
  final Color? pressedColor;
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
        color: pressed
            ? pressedColor ?? Color.lerp(color, Colors.black, 0.15)
            : color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
