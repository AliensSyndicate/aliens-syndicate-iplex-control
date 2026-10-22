import 'package:flutter/material.dart';

import '../components/app_modal_sheet.dart';
import '../components/neumorphic_action_button.dart';
import '../components/sheet_rows.dart';
import '../icons.dart';
import '../localized_context.dart';
import '../tokens.dart';
import 'failure_feedback.dart';

/// Destructive confirmation sheet: red mark, title, body, red confirm and
/// grey cancel.
Future<bool> confirmRemoval(
  BuildContext context, {
  String? title,
  String? body,
}) async {
  final l = context.l;
  final result = await showAppModalSheet<bool>(
    context: context,
    leading: const DangerMark(icon: AppIcons.delete),
    title: title ?? l.confirmRemoval,
    description: body ?? l.removalBody,
    actions: [
      AppButton.red(
        label: l.remove,
        onPressed: () => Navigator.of(context).pop(true),
      ),
      AppButton(
        label: l.cancel,
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ],
  );
  return result ?? false;
}

/// Destructive confirmation that runs [operation] inside the sheet: the
/// confirm button shows progress and ignores repeated taps, the sheet only
/// closes after [operation] completes, and failures stay visible in place.
/// Returns true only when the operation succeeded; cancelling changes nothing.
Future<bool> confirmAndRun(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required Future<void> Function() operation,
}) async {
  final l = context.l;
  var busy = false;
  String? error;
  final result = await showAppModalSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) => PopScope(
        canPop: !busy,
        child: AppModalSheet(
          leading: const DangerMark(icon: AppIcons.delete),
          title: title,
          description: body,
          content: error == null
              ? null
              : Text(
                  error!,
                  key: const Key('confirm-and-run-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
          actions: [
            AppButton.red(
              label: confirmLabel,
              busy: busy,
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await operation();
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop(true);
                        }
                      } catch (e) {
                        if (sheetContext.mounted) {
                          setState(() {
                            busy = false;
                            error = failureText(sheetContext, e);
                          });
                        }
                      }
                    },
            ),
            AppButton(
              label: l.cancel,
              onPressed: busy
                  ? null
                  : () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
