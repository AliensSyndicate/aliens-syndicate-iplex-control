import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';

const _subjects = ['suggestion', 'bug', 'question', 'praise', 'other'];

/// Feedback form: saves a record in Firebase (`sendFeedback`).
Future<void> showFeedbackSheet(BuildContext context) => showAppModalSheet<void>(
  context: context,
  isDismissible: false,
  builder: (_) => const _FeedbackSheet(),
);

class _FeedbackSheet extends ConsumerStatefulWidget {
  const _FeedbackSheet();
  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  final message = TextEditingController();
  String subject = _subjects.first;
  bool busy = false;
  // Stable per sheet: a retried submit overwrites the same record.
  late final String requestId = '${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  String _subjectLabel(String code) {
    final l = context.l;
    return switch (code) {
      'bug' => l.feedbackBug,
      'question' => l.feedbackQuestion,
      'praise' => l.feedbackPraise,
      'other' => l.feedbackOther,
      _ => l.feedbackSuggestion,
    };
  }

  Future<void> send() async {
    final text = message.text.trim();
    if (text.isEmpty || text.length > 2000) return;
    final l = context.l;
    final nav = Navigator.of(context, rootNavigator: true);
    final host = nav.context;
    final locale = Localizations.localeOf(context).toString();
    setState(() => busy = true);
    try {
      String? version;
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } catch (_) {}
      await ref.read(repositoryProvider).mutate('sendFeedback', {
        'subject': subject,
        'message': text,
        'requestId': requestId,
        'locale': locale,
        'appVersion': ?version,
      });
      if (!mounted) return;
      nav.pop();
      if (host.mounted) {
        showAppFeedbackSheet(context: host, message: l.feedbackSent);
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showFailure(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AppModalSheet(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(icon: AppIcons.feedback, title: l.sendFeedback),
          AppDropdownField<String>(
            key: const Key('feedback-subject'),
            label: l.feedbackSubject,
            initialValue: subject,
            items: [
              for (final code in _subjects)
                DropdownMenuItem(value: code, child: Text(_subjectLabel(code))),
            ],
            onChanged: (v) => setState(() => subject = v ?? _subjects.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            key: const Key('feedback-message'),
            label: l.feedbackMessage,
            hintText: l.feedbackHint,
            controller: message,
            maxLines: 6,
            height: 160,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        AppButton.primary(
          key: const Key('feedback-send'),
          label: l.feedbackSend,
          busy: busy,
          onPressed: message.text.trim().isEmpty ? null : send,
        ),
        AppButton(
          label: l.close,
          onPressed: busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
