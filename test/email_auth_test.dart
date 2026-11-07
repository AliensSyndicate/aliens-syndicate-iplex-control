import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/authentication/email_auth_page.dart';
import 'package:aliens_syndicate_iplex_control/features/authentication/login_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'widget_test.dart' as fixtures;

class _EmailRepository extends fixtures.TestRepository {
  final calls = <String>[];
  Object? signInError;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    calls.add('signIn:$email:$password');
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> sendPasswordReset(String email) async =>
      calls.add('reset:$email');
}

Future<void> _open(WidgetTester tester, _EmailRepository repo) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/login/email', builder: (_, _) => const EmailAuthPage()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.darkTheme,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.byKey(const Key('auth-email')), email);
  await tester.enterText(find.byKey(const Key('auth-password')), password);
  await tester.pump();
}

Future<void> _press(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(fixtures.loadTestFont);

  testWidgets('login offers Google, Apple and an e-mail button that opens '
      'its own screen', (tester) async {
    await _open(tester, _EmailRepository());
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.byKey(const Key('auth-email')), findsNothing);
    await _press(tester, 'login-email');
    expect(find.byType(EmailAuthPage), findsOneWidget);
    expect(find.byKey(const Key('auth-email')), findsOneWidget);
    expect(find.byKey(const Key('auth-password')), findsOneWidget);
  });

  testWidgets('sign in sends the typed e-mail and password', (tester) async {
    final repo = _EmailRepository();
    await _open(tester, repo);
    await _press(tester, 'login-email');
    await _fill(tester, 'ana@example.com', 'secret1');
    await _press(tester, 'auth-submit');
    expect(repo.calls, ['signIn:ana@example.com:secret1']);
  });

  testWidgets('there is no sign-up on the e-mail screen', (tester) async {
    await _open(tester, _EmailRepository());
    await _press(tester, 'login-email');
    expect(find.byKey(const Key('auth-toggle')), findsNothing);
    expect(find.textContaining('Create'), findsNothing);
    expect(find.textContaining('account'), findsNothing);
  });

  testWidgets('wrong credentials are reported and keep the screen', (
    tester,
  ) async {
    final repo = _EmailRepository()
      ..signInError = const AppFailure('invalid-credential');
    await _open(tester, repo);
    await _press(tester, 'login-email');
    await _fill(tester, 'ana@example.com', 'secret1');
    await _press(tester, 'auth-submit');
    expect(find.text('Incorrect e-mail or password.'), findsOneWidget);
    expect(find.byType(EmailAuthPage), findsOneWidget);
  });

  testWidgets('forgot password sends the reset to the typed e-mail', (
    tester,
  ) async {
    final repo = _EmailRepository();
    await _open(tester, repo);
    await _press(tester, 'login-email');
    await _fill(tester, 'ana@example.com', '');
    await _press(tester, 'auth-forgot');
    expect(repo.calls, ['reset:ana@example.com']);
  });
}
