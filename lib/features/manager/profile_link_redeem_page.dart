import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/public_identity.dart';
import 'scan_page.dart';

/// Account side of "Vincular com conta": the administrator authorized a profile
/// by issuing the code; this authenticated account confirms by redeeming it.
class ProfileLinkRedeemPage extends ConsumerStatefulWidget {
  const ProfileLinkRedeemPage({super.key});
  @override
  ConsumerState<ProfileLinkRedeemPage> createState() =>
      _ProfileLinkRedeemPageState();
}

class _ProfileLinkRedeemPageState extends ConsumerState<ProfileLinkRedeemPage> {
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> redeem([String? scanned]) async {
    final value = scanned ?? parseProfileLinkCode(code.text);
    if (busy ||
        value == null ||
        !(scanned != null || form.currentState!.validate())) {
      return;
    }
    setState(() => busy = true);
    try {
      final result = await ref.read(repositoryProvider).mutate(
        'redeemProfileLink',
        {'code': value},
      );
      await ref.read(repositoryProvider).mutate('selectContext', {
        'familyId': result['familyId'],
      });
      if (!mounted) return;
      showAppFeedbackSheet(context: context, message: context.l.profileLinked);
      context.go('/users');
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      body: PageTemplate(
        title: l.linkToProfile,
        showBack: true,
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.linkToProfileBody,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppTokens.lg),
              AppTextField(
                key: const Key('profile-link-input'),
                label: l.linkCode,
                controller: code,
                validator: (v) => parseProfileLinkCode(v ?? '') == null
                    ? l.invalidCode
                    : null,
              ),
              const SizedBox(height: AppTokens.lg),
              AppButton.primary(label: l.save, busy: busy, onPressed: redeem),
              const SizedBox(height: AppTokens.md),
              AppButton(
                label: l.scanQrCode,
                icon: AppIcons.qr,
                onPressed: busy
                    ? null
                    : () async {
                        final scanned = await Navigator.of(context)
                            .push<String>(
                              MaterialPageRoute(
                                builder: (_) => const ScanPage(
                                  device: false,
                                  parse: parseProfileLinkCode,
                                ),
                              ),
                            );
                        if (scanned != null) await redeem(scanned);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
