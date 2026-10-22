import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../tokens.dart';

/// Tactile Graphite Switch / Toggle
class NeumorphicSwitchTile extends StatelessWidget {
  const NeumorphicSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.disabled = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String? subtitle;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final enabled = !disabled && onChanged != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GraphiteSurface(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: enabled ? () => onChanged!(!value) : null,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: enabled
                                ? AppColors.textPrimary
                                : AppColors.textDisabled,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: enabled
                                  ? AppColors.textSecondary
                                  : AppColors.textDisabled,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _NeumorphicSwitch(value: value, enabled: enabled),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeumorphicSwitch extends StatelessWidget {
  const _NeumorphicSwitch({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const trackWidth = 52.0;
    const trackHeight = 30.0;
    const thumbSize = 24.0;
    const padding = 3.0;

    // Flat switch: green track when on, white thumb.
    return Semantics(
      toggled: value,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: trackWidth,
        height: trackHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.full),
          color: value
              ? (enabled ? AppColors.primary : AppColors.disabled)
              : AppColors.surfacePressed,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(padding),
            child: Container(
              width: thumbSize,
              height: thumbSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? AppColors.textPrimary : AppColors.textDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
