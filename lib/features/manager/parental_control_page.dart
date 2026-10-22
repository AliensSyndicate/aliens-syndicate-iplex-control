import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';

/// Parental PIN of the family (contract v1, docs/CONTRACTS.md). With a kids
/// profile in the family, adult profiles open on the TV only with this PIN,
/// verified by the backend. The PIN is never stored or shown by the app.
class ParentalControlPage extends ConsumerWidget {
  const ParentalControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final admin = ref.watch(adminProvider);
    final configured = ref.watch(
      familyProvider.select(
        (f) => f.asData?.value?.parentalPinConfigured ?? false,
      ),
    );
    final hasKids =
        ref
            .watch(entriesProvider('profiles'))
            .asData
            ?.value
            .any(
              (p) => p.text('type') == 'kids' && p.data['deleting'] != true,
            ) ??
        false;
    return PageTemplate(
      title: l.parentalControl,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.parentalControlBody,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          EntryTile(
            key: const Key('parental-status'),
            title: configured ? l.parentalPinConfigured : l.parentalPinMissing,
            subtitle: !configured && hasKids ? l.parentalPinMissingKids : null,
            icon: configured ? AppIcons.lock : AppIcons.unlock,
          ),
          if (admin) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const Key('parental-set'),
              label: configured ? l.changeParentalPin : l.setParentalPin,
              icon: AppIcons.lock,
              onPressed: () => showAppModalSheet<void>(
                context: context,
                builder: (_) => const _ParentalPinForm(),
              ),
            ),
            if (configured) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const Key('parental-remove'),
                label: l.removeParentalPin,
                icon: AppIcons.delete,
                onPressed: () async {
                  final removed = await confirmAndRun(
                    context,
                    title: l.removeParentalPin,
                    body: l.removeParentalPinBody,
                    confirmLabel: l.removeParentalPin,
                    operation: () =>
                        ref.read(repositoryProvider).mutate('clearParentalPin'),
                  );
                  if (removed && context.mounted) {
                    showAppFeedbackSheet(
                      context: context,
                      message: l.parentalPinRemoved,
                    );
                  }
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ParentalPinForm extends ConsumerStatefulWidget {
  const _ParentalPinForm();
  @override
  ConsumerState<_ParentalPinForm> createState() => _ParentalPinFormState();
}

class _ParentalPinFormState extends ConsumerState<_ParentalPinForm> {
  final formKey = GlobalKey<FormState>();
  final pin = TextEditingController(), confirm = TextEditingController();
  bool busy = false;
  Object? error;

  @override
  void dispose() {
    pin.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(repositoryProvider).mutate('setParentalPin', {
        'pin': pin.text.trim(),
        'confirmPin': confirm.text.trim(),
      });
      if (!mounted) return;
      final message = context.l.parentalPinSaved;
      final navigator = Navigator.of(context);
      navigator.pop();
      showAppFeedbackSheet(context: navigator.context, message: message);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    String? validate(String? v) {
      final value = v?.trim() ?? '';
      if (value.isEmpty) return l.requiredField;
      if (!RegExp(r'^\d{4}$').hasMatch(value)) return l.parentalPinLength;
      return null;
    }

    return AppModalSheet(
      title: l.setParentalPin,
      description: l.parentalControlBody,
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              key: const Key('parental-pin'),
              label: l.pin,
              controller: pin,
              secret: true,
              keyboardType: TextInputType.number,
              validator: validate,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              key: const Key('parental-pin-confirm'),
              label: l.confirmPin,
              controller: confirm,
              secret: true,
              keyboardType: TextInputType.number,
              validator: (v) =>
                  validate(v) ??
                  (v?.trim() != pin.text.trim() ? l.pinMustMatch : null),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                failureText(context, error!),
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton.primary(
          key: const Key('parental-save'),
          label: l.save,
          busy: busy,
          onPressed: submit,
        ),
        AppButton(
          label: l.cancel,
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
