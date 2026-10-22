import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';

class NameForm extends ConsumerStatefulWidget {
  const NameForm({
    super.key,
    required this.title,
    required this.action,
    this.id,
    this.initial = '',
  });
  final String title, action, initial;
  final String? id;
  @override
  ConsumerState<NameForm> createState() => _NameFormState();
}

class _NameFormState extends ConsumerState<NameForm> {
  late final TextEditingController name = TextEditingController(
    text: widget.initial,
  );
  final form = GlobalKey<FormState>();
  bool busy = false;
  String profileType = 'regular';
  // Stable per form instance: a retried submit cannot create a second profile.
  late final String requestId = '${DateTime.now().microsecondsSinceEpoch}';
  bool get creatingProfile =>
      widget.action == 'saveProfile' && widget.id == null;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate(widget.action, {
        'name': name.text.trim(),
        if (widget.id != null) 'id': widget.id,
        if (creatingProfile) ...{'type': profileType, 'requestId': requestId},
      });
      if (mounted) {
        if (widget.action == 'createFamily') {
          context.go('/home');
        } else {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageTemplate(
      title: widget.title,
      showBack: true,
      child: Form(
        key: form,
        child: Column(
          children: [
            AppTextField(
              label: context.l.name,
              controller: name,
              validator: (v) =>
                  v == null || v.trim().isEmpty || v.trim().length > 80
                  ? context.l.requiredField
                  : null,
            ),
            if (creatingProfile) ...[
              const SizedBox(height: AppSpacing.lg),
              AppDropdownField<String>(
                key: const Key('profile-type'),
                label: context.l.profileType,
                initialValue: profileType,
                items: [
                  DropdownMenuItem(
                    value: 'regular',
                    child: Text(context.l.profileTypeRegular),
                  ),
                  DropdownMenuItem(
                    value: 'kids',
                    child: Text(context.l.profileTypeKids),
                  ),
                ],
                onChanged: (v) => setState(() => profileType = v ?? 'regular'),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton.primary(
              label: context.l.save,
              busy: busy,
              onPressed: save,
            ),
          ],
        ),
      ),
    ),
  );
}
