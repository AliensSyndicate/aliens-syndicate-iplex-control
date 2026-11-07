import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';

/// Sign in with e-mail and password (no sign-up: these accounts are created by
/// the operator, e.g. for store reviewers). Opened from the login page.
class EmailAuthPage extends ConsumerStatefulWidget {
  const EmailAuthPage({super.key});
  @override
  ConsumerState<EmailAuthPage> createState() => _EmailAuthPageState();
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class _EmailAuthPageState extends ConsumerState<EmailAuthPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  bool get _emailValid => _emailPattern.hasMatch(email.text.trim());
  bool get _canSubmit => !busy && _emailValid && password.text.isNotEmpty;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() => _run(
    () =>
        ref.read(repositoryProvider).signInWithEmail(email.text, password.text),
  );

  Future<void> forgotPassword() async {
    if (!_emailValid) {
      showFailure(context, const AppFailure('invalid-email'));
      return;
    }
    await _run(() async {
      await ref.read(repositoryProvider).sendPasswordReset(email.text);
      if (mounted) {
        showAppFeedbackSheet(
          context: context,
          message: context.l.authResetSent,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageTemplate(
        title: l.authEmailTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: const Key('auth-email'),
              label: l.authEmail,
              controller: email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
            ),
            AppTextField(
              key: const Key('auth-password'),
              label: l.authPassword,
              controller: password,
              secret: true,
              onChanged: (_) => setState(() {}),
            ),
            AppButton.primary(
              key: const Key('auth-submit'),
              label: l.authSignIn,
              busy: busy,
              onPressed: _canSubmit ? submit : null,
            ),
            TextButton(
              key: const Key('auth-forgot'),
              onPressed: busy ? null : forgotPassword,
              child: Text(l.authForgotPassword),
            ),
          ],
        ),
      ),
    );
  }
}
