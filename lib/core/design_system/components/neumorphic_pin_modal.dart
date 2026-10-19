import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/models.dart';
import '../feedback/failure_feedback.dart';
import '../graphite_surface.dart';
import '../icons.dart';
import '../localized_context.dart';
import '../tokens.dart';
import 'app_icon.dart';
import 'app_modal_sheet.dart';
import 'neumorphic_action_button.dart';
import 'neumorphic_text_field.dart';

/// Modal sheet prompting the user for the playlist protection PIN.
Future<bool> showPinUnlockDialog(
  BuildContext context,
  WidgetRef ref,
  String sourceId,
) async {
  final result = await showAppModalSheet<bool>(
    context: context,
    builder: (dialogContext) => NeumorphicPinModal(sourceId: sourceId),
  );
  return result == true;
}

class NeumorphicPinModal extends ConsumerStatefulWidget {
  const NeumorphicPinModal({super.key, required this.sourceId});
  final String sourceId;

  @override
  ConsumerState<NeumorphicPinModal> createState() => _NeumorphicPinModalState();
}

class _NeumorphicPinModalState extends ConsumerState<NeumorphicPinModal> {
  final pinController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  String? errorMessage;

  @override
  void dispose() {
    pinController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!formKey.currentState!.validate()) return;

    setState(() {
      busy = true;
      errorMessage = null;
    });

    try {
      await ref.read(repositoryProvider).mutate('verifySourcePin', {
        'id': widget.sourceId,
        'pin': pinController.text.trim(),
      });
      if (!mounted) return;
      ref.read(unlockedSourcesProvider.notifier).unlock(widget.sourceId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final l = context.l;
      if (e is AppFailure && e.code == 'pin-locked') {
        setState(() => errorMessage = l.pinLocked);
      } else if (e is AppFailure && e.code == 'invalid-pin') {
        setState(
          () => errorMessage = l.incorrectPin(
            (e.details['remainingAttempts'] as num?)?.toInt() ?? 0,
          ),
        );
      } else {
        setState(() => errorMessage = failureText(context, e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GraphiteSurface(
                      circle: true,
                      recessed: true,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: const AppIcon(
                        AppIcons.lock,
                        size: AppDimensions.iconLarge,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l.enterPinTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l.enterPinBody,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    label: l.pin,
                    controller: pinController,
                    secret: true,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final val = v?.trim() ?? '';
                      if (val.isEmpty) return l.requiredField;
                      if (!RegExp(r'^\d{4,6}$').hasMatch(val)) {
                        return l.pinLengthError;
                      }
                      return null;
                    },
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(label: l.unlock, busy: busy, onPressed: submit),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: l.cancel,
                    onPressed: busy ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
