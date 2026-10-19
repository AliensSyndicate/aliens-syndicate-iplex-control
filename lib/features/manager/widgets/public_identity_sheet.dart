import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import '../../../core/domain/public_identity.dart';

Future<void> showPublicIdentity(BuildContext context, [String? initialCode]) =>
    showAppModalSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (c) => _PublicIdentitySheetContent(initialCode: initialCode),
    );

class _PublicIdentitySheetContent extends ConsumerStatefulWidget {
  const _PublicIdentitySheetContent({this.initialCode});
  final String? initialCode;

  @override
  ConsumerState<_PublicIdentitySheetContent> createState() =>
      _PublicIdentitySheetContentState();
}

class _PublicIdentitySheetContentState
    extends ConsumerState<_PublicIdentitySheetContent> {
  bool _copied = false;
  bool _bootstrapping = false;

  @override
  void initState() {
    super.initState();
    _ensureCode();
  }

  void _ensureCode() {
    final account = ref.read(accountProvider).asData?.value;
    if (widget.initialCode == null &&
        (account == null || account.publicCode == null || account.publicCode!.isEmpty)) {
      _runBootstrap();
    }
  }

  Future<void> _runBootstrap() async {
    if (_bootstrapping) return;
    final uid = ref.read(authProvider).asData?.value;
    if (uid == null) return;
    setState(() => _bootstrapping = true);
    try {
      await ref.read(repositoryProvider).initializeAccount(uid);
      if (mounted) {
        ref.invalidate(accountProvider);
      }
    } catch (_) {
      // Handled via accountProvider error state
    } finally {
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context;
    final accountState = ref.watch(accountProvider);
    final account = accountState.asData?.value;
    final code = account?.publicCode ?? widget.initialCode;

    Widget content;
    if (_bootstrapping || (code == null && accountState.isLoading)) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTokens.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (code == null || code.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
        child: Column(
          children: [
            Text(
              c.l.identityUnavailable,
              style: const TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.md),
            AppButton(
              label: c.l.retry,
              busy: _bootstrapping,
              onPressed: () {
                ref.invalidate(accountProvider);
                _runBootstrap();
              },
            ),
          ],
        ),
      );
    } else {
      content = Column(
        children: [
          AppSurface(
            child: Semantics(
              label: c.l.publicUserCode,
              child: QrImageView(
                data: publicUserQr(code),
                backgroundColor: Colors.white,
                size: 220,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.lg),
          SelectableText(
            code,
            style: Theme.of(c).textTheme.titleLarge?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      );
    }

    return AppModalSheet(
      title: c.l.publicUserCode,
      description: c.l.publicIdentityHelp,
      content: content,
      actions: [
        if (code != null && code.isNotEmpty)
          AppButton(
            label: _copied ? c.l.codeCopied : c.l.copyPublicCode,
            icon: _copied ? AppIcons.check : null,
            onPressed: () {
              final currentCode =
                  ref.read(accountProvider).asData?.value?.publicCode ?? code;
              Clipboard.setData(ClipboardData(text: currentCode)).ignore();
              if (mounted) {
                setState(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              }
            },
          ),
        AppButton(
          label: c.l.close,
          onPressed: () => Navigator.of(c, rootNavigator: true).pop(),
        ),
      ],
    );
  }
}
