import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/components.dart';
import '../controllers/iptv_sync_controller.dart';

/// Reusable Global IPTV Sync Progress Bar.
///
/// Requirement: Appears across all authenticated screens whenever an active sync job
/// exists for the current user/family.
/// Positioned immediately below the Status Bar area and above the AppBar.
/// Thin 2.5 dp height, Design System styling, non-blocking touches,
/// smooth animations without layout jumps.
class GlobalIptvSyncProgress extends ConsumerStatefulWidget {
  const GlobalIptvSyncProgress({super.key});

  @override
  ConsumerState<GlobalIptvSyncProgress> createState() =>
      _GlobalIptvSyncProgressState();
}

class _GlobalIptvSyncProgressState extends ConsumerState<GlobalIptvSyncProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(globalIptvSyncProgressProvider);

    if (syncState.isActive && syncState.isIndeterminate) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    }

    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        opacity: syncState.isActive ? 1.0 : 0.0,
        child: Container(
          margin: const EdgeInsets.only(top: 8.0),
          width: double.infinity,
          height: 2.5,
          color: AppColors.surfaceRecessed.withValues(alpha: 0.7),
          child: syncState.isActive
              ? (syncState.isIndeterminate
                    ? AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final curvedVal = Curves.easeInOut.transform(
                                _pulseController.value,
                              );
                              final w = constraints.maxWidth;
                              const barWidthFraction = 0.35;
                              final barWidth = (w * barWidthFraction).clamp(
                                0.0,
                                w,
                              );
                              final left = (curvedVal * (w - barWidth)).clamp(
                                0.0,
                                w,
                              );
                              return Stack(
                                children: [
                                  Positioned(
                                    left: left,
                                    width: barWidth,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.brandBlue.withValues(
                                              alpha: 0.2,
                                            ),
                                            AppColors.brandBlue,
                                            AppColors.brandBlue.withValues(
                                              alpha: 0.2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      )
                    : TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(
                          begin: 0.0,
                          end: (syncState.progress ?? 0.0).clamp(0.0, 1.0),
                        ),
                        builder: (context, progressVal, child) {
                          return FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progressVal,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue,
                              ),
                            ),
                          );
                        },
                      ))
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
