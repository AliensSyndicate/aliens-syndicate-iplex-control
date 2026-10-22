import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/components.dart';
import '../controllers/device_controller.dart';

class DeviceManualCodePage extends ConsumerStatefulWidget {
  const DeviceManualCodePage({super.key});

  @override
  ConsumerState<DeviceManualCodePage> createState() =>
      _DeviceManualCodePageState();
}

class _DeviceManualCodePageState extends ConsumerState<DeviceManualCodePage> {
  final TextEditingController textController = TextEditingController();
  bool busy = false;
  String? errorMessage;

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final raw = textController.text.trim();
    if (raw.isEmpty) {
      setState(() => errorMessage = context.l.requiredField);
      return;
    }

    setState(() {
      busy = true;
      errorMessage = null;
    });

    try {
      final session = await ref
          .read(devicePairingProvider.notifier)
          .inspect(code: raw);
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
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return PageTemplate(
      title: l.enterCodeTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.enterCodeHelp,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  NeumorphicTextField(
                    label: l.enterCodeTitle,
                    controller: textController,
                    hintText: l.enterCodeHint,
                    validator: (_) => errorMessage,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(label: l.save, busy: busy, onPressed: submit),
        ],
      ),
    );
  }
}
