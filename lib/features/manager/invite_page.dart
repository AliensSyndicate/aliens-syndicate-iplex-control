import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/public_identity.dart';

class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key});
  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  Map<String, dynamic>? person;
  String? targetFamilyId;
  bool busy = false;
  bool kidsAccount = false;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> lookup() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      person = null;
    });
    targetFamilyId = ref.read(accountProvider).asData?.value?.familyId;
    try {
      final result = await ref.read(repositoryProvider).mutate(
        'lookupPublicUser',
        {'code': parsePublicUserCode(code.text), 'familyId': targetFamilyId},
      );
      if (mounted) setState(() => person = result);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> invite() async {
    if (person == null || busy) return;
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate('requestMembership', {
        'code': person!['code'],
        'familyId': targetFamilyId,
        'profileType': kidsAccount ? 'kids' : 'regular',
      });
      if (mounted) {
        context.pop();
        showAppFeedbackSheet(
          context: context,
          message: context.l.membershipSent,
        );
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
      title: context.l.addMember,
      showBack: true,
      child: Form(
        key: form,
        child: Column(
          children: [
            NeumorphicSwitchTile(
              key: const Key('kids-account-toggle'),
              title: context.l.kidsAccount,
              subtitle: kidsAccount ? context.l.kidsRestrictionNote : null,
              value: kidsAccount,
              disabled: busy || !ref.watch(adminProvider),
              onChanged: (value) => setState(() => kidsAccount = value),
            ),
            AppTextField(
              label: context.l.publicUserCode,
              controller: code,
              validator: (v) => parsePublicUserCode(v ?? '') == null
                  ? context.l.invalidPublicCode
                  : null,
              onChanged: (_) => setState(() => person = null),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: context.l.search, busy: busy, onPressed: lookup),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: context.l.scan,
              icon: AppIcons.qr,
              onPressed: busy
                  ? null
                  : () async {
                      final result = await context.push<String>('/users/scan');
                      if (!mounted || result == null) return;
                      code.text = result;
                      await lookup();
                    },
            ),
            if (person != null) ...[
              EntryTile(
                title: person!['name'] as String,
                subtitle: person!['code'] as String,
                icon: AppIcons.account,
              ),
              AppButton.primary(
                label: context.l.sendMembershipRequest,
                busy: busy,
                onPressed: invite,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
