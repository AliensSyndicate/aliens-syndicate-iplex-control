import 'package:aliens_syndicate_iplex_control/core/data/callable_failure.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/feedback/failure_feedback.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps domain codes and falls back from SDK messages to transport codes',
    () {
      expect(
        callableFailure(
          code: 'failed-precondition',
          message: 'family-required',
        ).code,
        'family-required',
      );
      expect(
        callableFailure(
          code: 'invalid-argument',
          message: 'invalid-input',
        ).code,
        'invalid-input',
      );
      expect(
        callableFailure(code: 'unavailable', message: 'UNAVAILABLE').code,
        'unavailable',
      );
      expect(
        callableFailure(
          code: 'internal',
          message: 'Provider failed at https://example.com/private-token',
        ).code,
        'internal',
      );
      expect(
        callableFailure(code: 'deadline-exceeded').code,
        'deadline-exceeded',
      );
    },
  );

  testWidgets(
    'validation and connection failures give actionable feedback without raw messages',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt', 'BR'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        failureText(
          context,
          callableFailure(code: 'invalid-argument', message: 'invalid-input'),
        ),
        'Revise os campos informados e tente salvar novamente.',
      );
      expect(
        failureText(
          context,
          callableFailure(code: 'unavailable', message: 'UNAVAILABLE'),
        ),
        contains('Verifique sua conexão'),
      );
      expect(
        failureText(context, callableFailure(code: 'deadline-exceeded')),
        contains('Verifique se a alteração foi salva'),
      );
      expect(
        failureText(
          context,
          callableFailure(
            code: 'internal',
            message: 'https://example.com/private-token',
          ),
        ),
        isNot(contains('private-token')),
      );
    },
  );
}
