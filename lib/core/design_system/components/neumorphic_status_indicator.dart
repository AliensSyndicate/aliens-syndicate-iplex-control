import 'package:flutter/material.dart';

import '../tokens.dart';

enum IndicatorStatus { online, offline, error }

/// Neumorphic Status Indicator Dot (Online / Offline / Error)
class NeumorphicStatusIndicator extends StatelessWidget {
  const NeumorphicStatusIndicator({
    super.key,
    this.online = false,
    this.status,
    this.color,
  });

  final bool online;
  final IndicatorStatus? status;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final IndicatorStatus resolvedStatus;
    if (status != null) {
      resolvedStatus = status!;
    } else {
      resolvedStatus = online ? IndicatorStatus.online : IndicatorStatus.offline;
    }

    final Color dotColor = color ??
        switch (resolvedStatus) {
          IndicatorStatus.online => AppColors.success,
          IndicatorStatus.offline => AppColors.disabled,
          IndicatorStatus.error => AppColors.error,
        };

    final bool hasGlow = resolvedStatus != IndicatorStatus.offline;

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor,
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}
