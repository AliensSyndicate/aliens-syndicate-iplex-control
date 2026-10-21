import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/design_system/components.dart';
import '../controllers/device_controller.dart';

class DeviceQrScannerPage extends ConsumerStatefulWidget {
  const DeviceQrScannerPage({super.key});

  @override
  ConsumerState<DeviceQrScannerPage> createState() =>
      _DeviceQrScannerPageState();
}

class _DeviceQrScannerPageState extends ConsumerState<DeviceQrScannerPage> {
  final MobileScannerController controller = MobileScannerController();
  bool busy = false;
  String? errorMessage;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String? _extractToken(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'iplex') {
      if ((uri.host == 'pair' ||
              (uri.host == 'link' && uri.path == '/device')) &&
          uri.queryParameters.containsKey('token')) {
        final token = uri.queryParameters['token']!;
        if (RegExp(r'^[a-f0-9]{32,64}$').hasMatch(token)) {
          return token;
        }
      }
    }
    // Also accept raw hex token for direct tests
    if (RegExp(r'^[a-f0-9]{32,64}$').hasMatch(raw.trim())) {
      return raw.trim();
    }
    return null;
  }

  Future<void> onDetect(BarcodeCapture capture) async {
    if (busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final token = _extractToken(raw);
    if (token == null) {
      setState(() => errorMessage = context.l.invalidQrCode);
      return;
    }

    setState(() {
      busy = true;
      errorMessage = null;
    });

    try {
      await controller.stop();
      final session = await ref
          .read(devicePairingProvider.notifier)
          .inspect(token: token);
      if (!mounted) return;
      if (session != null) {
        context.push('/devices/confirm');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          errorMessage = failureText(context, e);
        });
        showDeviceConnectionFailure(context, e);
        await controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  CircularButton(
                    label: l.back,
                    icon: AppIcons.left,
                    size: AppDimensions.touch,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l.scanQrCode,
                      style: AppTypography.headlineMedium,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                l.scanHelp,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (errorMessage != null) ...[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: controller,
                        onDetect: onDetect,
                        errorBuilder: (ctx, err) => Container(
                          color: AppColors.surfaceRecessed,
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const AppIcon(
                                AppIcons.alert,
                                size: AppTokens.xxl,
                                color: AppColors.warning,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                l.cameraPermissionHelp,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              AppButton(
                                label: l.enterCodeManually,
                                onPressed: () {
                                  context.pushReplacement('/devices/code');
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Industrial viewfinder frame; hidden when the camera
                      // is unavailable so it never covers the fallback message.
                      ValueListenableBuilder<MobileScannerState>(
                        valueListenable: controller,
                        builder: (context, state, _) => state.error != null
                            ? const SizedBox.shrink()
                            : IgnorePointer(
                                child: Center(
                                  child: Container(
                                    width: 240,
                                    height: 240,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.accent.withValues(
                                          alpha: 0.6,
                                        ),
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.md,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (busy)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AppButton(
                label: l.enterCodeManually,
                onPressed: () => context.pushReplacement('/devices/code'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
