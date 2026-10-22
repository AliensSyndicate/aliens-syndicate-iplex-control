import 'package:flutter/material.dart';

import '../../core/design_system/components.dart';

/// Buttons of the title details page only: the iPlex Web/TV button pattern
/// (`.iplex-button-primary` / `.iplex-button-secondary`, text only, pill),
/// at phone scale. Primary: white fill, near-black text. Secondary:
/// transparent with a 2 px light border and light text.
class DetailsButton extends StatelessWidget {
  const DetailsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.busy = false,
    this.icon,
  });

  const DetailsButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  }) : primary = true;

  /// Icon-only button (fit width, circular); [label] stays for accessibility.
  final List<List<dynamic>>? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary, busy;

  // Same values as the Web tokens (--iplex-button-*).
  static const _primaryBackground = Color(0xFFFFFFFF);
  static const _primaryText = Color(0xFF0F0F0F);
  static const _secondaryText = Color(0xFFF1F1F1);
  static const _border = 2.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final foreground = primary ? _primaryText : _secondaryText;
    final side = primary
        ? BorderSide.none
        : const BorderSide(color: _secondaryText, width: _border);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: primary ? _primaryBackground : Colors.transparent,
          shape: icon == null
              ? StadiumBorder(side: side)
              : CircleBorder(side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: AppDimensions.touch,
              width: icon == null ? null : AppDimensions.touch,
              // Fit width unless the parent stretches it (rows, columns).
              child: Center(
                widthFactor: 1,
                child: icon != null && !busy
                    ? AppIcon(icon!, color: foreground)
                    : busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
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

/// Two buttons side by side, 50% each.
class DetailsButtonRow extends StatelessWidget {
  const DetailsButtonRow({
    super.key,
    required this.first,
    required this.second,
  });
  final Widget first, second;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: first),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: second),
    ],
  );
}

/// Icon-only action of the details page top bar: white, no box, 48 dp.
class DetailsBarIcon extends StatelessWidget {
  const DetailsBarIcon({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.material,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;

  /// Filled/outlined state glyph (favorite, saved).
  final IconData? material;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkResponse(
      radius: AppDimensions.touch / 2,
      onTap: busy ? null : onPressed,
      child: SizedBox.square(
        dimension: AppDimensions.touch,
        child: Center(
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : material != null
              ? Icon(material, color: Colors.white, size: 28)
              : AppIcon(icon!, color: Colors.white, size: 28),
        ),
      ),
    ),
  );
}
