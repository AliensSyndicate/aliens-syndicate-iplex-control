import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/data/providers.dart';
import '../../core/domain/public_identity.dart';
import '../../core/design_system/components.dart';
import '../devices/presentation/controllers/device_controller.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key, required this.device, this.parse});
  final bool device;

  /// Overrides the public user code parser (e.g. profile link codes).
  final String? Function(String raw)? parse;
  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final controller = MobileScannerController();
  bool busy = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String? _parseToken(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'iplex') {
      final kind = widget.device ? 'device' : 'member';
      if ((uri.host == 'link' && uri.path == '/$kind') ||
          (widget.device && uri.host == 'pair')) {
        final token = uri.queryParameters['token'];
        if (token != null && RegExp(r'^[a-f0-9]{32,64}$').hasMatch(token)) {
          return token;
        }
      }
    }
    if (RegExp(r'^[a-f0-9]{32,64}$').hasMatch(raw.trim())) {
      return raw.trim();
    }
    return null;
  }

  Future<void> detected(BarcodeCapture capture) async {
    if (busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    if (!widget.device) {
      final code = (widget.parse ?? parsePublicUserCode)(raw);
      if (code == null) return;
      setState(() => busy = true);
      await controller.stop();
      if (mounted) context.pop(code);
      return;
    }
    final token = _parseToken(raw);
    if (token == null) return;

    setState(() => busy = true);
    await controller.stop();

    if (widget.device) {
      try {
        final session = await ref
            .read(devicePairingProvider.notifier)
            .inspect(token: token);
        if (mounted && session != null) {
          context.push('/devices/confirm');
          return;
        }
      } catch (_) {
        // Fallback for legacy direct pairing
        try {
          await ref.read(repositoryProvider).mutate('linkDevice', {
            'token': token,
          });
          if (mounted) context.go('/devices');
          return;
        } catch (e) {
          if (mounted) {
            showDeviceConnectionFailure(context, e);
            setState(() => busy = false);
            await controller.start();
          }
          return;
        }
      }
    }

    if (mounted) {
      setState(() => busy = false);
      await controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppDimensions.touch,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircularButton(
                      label: l.back,
                      icon: AppIcons.left,
                      size: AppDimensions.touch,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(l.scan, style: AppTypography.headlineMedium),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                widget.device ? l.scanHelp : l.publicIdentityScanHelp,
              ),
            ),
            Expanded(
              child: MobileScanner(
                controller: controller,
                onDetect: detected,
                errorBuilder: (c, e) =>
                    ErrorState(onRetry: () => controller.start()),
              ),
            ),
            if (widget.device) ...[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppButton(
                  label: l.enterCodeManually,
                  onPressed: () => context.push('/devices/code'),
                ),
              ),
            ],
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
