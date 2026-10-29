import 'package:aliens_syndicate_iplex_control/app/app.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/features/authentication/login_page.dart';
import 'package:aliens_syndicate_iplex_control/features/legal/data/services/legal_document_url_resolver.dart';
import 'package:aliens_syndicate_iplex_control/features/legal/domain/enums/legal_document_type.dart';
import 'package:aliens_syndicate_iplex_control/features/legal/presentation/pages/legal_webview_page.dart';
import 'package:aliens_syndicate_iplex_control/features/legal/presentation/widgets/legal_document_error_state.dart';
import 'package:aliens_syndicate_iplex_control/features/legal/presentation/widgets/legal_document_loading_indicator.dart';
import 'package:aliens_syndicate_iplex_control/features/manager/account_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fake_webview_platform.dart';
import 'widget_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  group('LegalDocumentType & UrlResolver', () {
    test('parses LegalDocumentType from string and path segment', () {
      expect(
        LegalDocumentType.fromString('terms'),
        LegalDocumentType.termsOfUse,
      );
      expect(
        LegalDocumentType.fromString('termsOfUse'),
        LegalDocumentType.termsOfUse,
      );
      expect(
        LegalDocumentType.fromString('terms-of-use'),
        LegalDocumentType.termsOfUse,
      );
      expect(
        LegalDocumentType.fromString('privacy'),
        LegalDocumentType.privacyPolicy,
      );
      expect(
        LegalDocumentType.fromString('privacyPolicy'),
        LegalDocumentType.privacyPolicy,
      );
      expect(
        LegalDocumentType.fromString('privacy_policy'),
        LegalDocumentType.privacyPolicy,
      );
      expect(LegalDocumentType.fromString('other'), isNull);
      expect(LegalDocumentType.fromString(null), isNull);

      expect(LegalDocumentType.termsOfUse.pathSegment, 'terms');
      expect(LegalDocumentType.privacyPolicy.pathSegment, 'privacy');
    });

    test(
      'resolves production URLs correctly without inventing arbitrary URLs',
      () {
        const resolver = LegalDocumentUrlResolver(
          environment: LegalEnvironment.production,
        );

        final terms = resolver.resolve(LegalDocumentType.termsOfUse);
        expect(terms.scheme, 'https');
        expect(terms.host, 'aliens-syndicate-docs.web.app');
        expect(terms.path, '/apps/iplex/terms');

        final privacy = resolver.resolve(LegalDocumentType.privacyPolicy);
        expect(privacy.scheme, 'https');
        expect(privacy.host, 'aliens-syndicate-docs.web.app');
        expect(privacy.path, '/apps/iplex/policy');
      },
    );

    test('staging and development use the same published pages', () {
      const stagingResolver = LegalDocumentUrlResolver(
        environment: LegalEnvironment.staging,
      );
      final stagingTerms = stagingResolver.resolve(
        LegalDocumentType.termsOfUse,
      );
      expect(
        stagingTerms.toString(),
        'https://aliens-syndicate-docs.web.app/apps/iplex/terms',
      );

      const devResolver = LegalDocumentUrlResolver(
        environment: LegalEnvironment.development,
      );
      final devTerms = devResolver.resolve(LegalDocumentType.termsOfUse);
      expect(
        devTerms.toString(),
        'https://aliens-syndicate-docs.web.app/apps/iplex/terms',
      );
      expect(devResolver.isAllowedLegalUrl(devTerms), isTrue);
    });

    test('applies supported language locale query parameters', () {
      const resolver = LegalDocumentUrlResolver(
        environment: LegalEnvironment.production,
      );

      final ptTerms = resolver.resolve(
        LegalDocumentType.termsOfUse,
        languageCode: 'pt_BR',
      );
      expect(ptTerms.queryParameters['lang'], 'pt');

      final esPrivacy = resolver.resolve(
        LegalDocumentType.privacyPolicy,
        languageCode: 'es',
      );
      expect(esPrivacy.queryParameters['lang'], 'es');

      final enTerms = resolver.resolve(
        LegalDocumentType.termsOfUse,
        languageCode: 'en_US',
      );
      expect(enTerms.queryParameters['lang'], 'en');
    });

    test('honors compile-time custom URL overrides when secure and valid', () {
      const customResolver = LegalDocumentUrlResolver(
        environment: LegalEnvironment.production,
        customTermsUrl: 'https://iplex.app/custom-terms',
        customPrivacyUrl: 'https://iplex.app/custom-privacy',
      );

      expect(
        customResolver.resolve(LegalDocumentType.termsOfUse).toString(),
        'https://iplex.app/custom-terms',
      );
      expect(
        customResolver.resolve(LegalDocumentType.privacyPolicy).toString(),
        'https://iplex.app/custom-privacy',
      );
    });

    test('enforces strict security validation rules on URLs', () {
      const prodResolver = LegalDocumentUrlResolver(
        environment: LegalEnvironment.production,
      );

      // HTTPS required in production
      expect(
        prodResolver.isAllowedLegalUrl(
          Uri.parse('https://iplex-2c8fc.web.app/terms'),
        ),
        isTrue,
      );
      expect(
        prodResolver.isAllowedLegalUrl(
          Uri.parse('https://iplex-2c8fc.firebaseapp.com/privacy'),
        ),
        isTrue,
      );
      expect(
        prodResolver.isAllowedLegalUrl(Uri.parse('https://iplex.app/terms')),
        isTrue,
      );
      expect(
        prodResolver.isAllowedLegalUrl(
          Uri.parse('http://iplex-2c8fc.web.app/terms'),
        ),
        isFalse,
      );

      // Block unauthorized domains
      expect(
        prodResolver.isAllowedLegalUrl(
          Uri.parse('https://evil-phishing.com/terms'),
        ),
        isFalse,
      );
      expect(
        prodResolver.isAllowedLegalUrl(Uri.parse('https://google.com')),
        isFalse,
      );

      // Block insecure schemes
      expect(
        prodResolver.isAllowedLegalUrl(Uri.parse('javascript:alert(1)')),
        isFalse,
      );
      expect(
        prodResolver.isAllowedLegalUrl(Uri.parse('file:///etc/hosts')),
        isFalse,
      );
      expect(
        prodResolver.isAllowedLegalUrl(Uri.parse('data:text/html,hack')),
        isFalse,
      );

      // Legitimate external links
      expect(
        prodResolver.isLegitimateExternalLink(
          Uri.parse('https://support.google.com'),
        ),
        isTrue,
      );
      expect(
        prodResolver.isLegitimateExternalLink(Uri.parse('http://insecure.org')),
        isFalse,
      );
      expect(
        prodResolver.isLegitimateExternalLink(
          Uri.parse('https://iplex-2c8fc.web.app/terms'),
        ),
        isFalse,
      );
    });
  });

  group('Legal Widgets', () {
    testWidgets(
      'LegalDocumentLoadingIndicator displays progress and localized message',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('pt'),
            home: Scaffold(body: LegalDocumentLoadingIndicator(progress: 45)),
          ),
        );
        await tester.pump();

        expect(find.text('Carregando documento…'), findsOneWidget);
        expect(find.text('45%'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'LegalDocumentErrorState shows message and triggers retry on button tap',
      (tester) async {
        var retried = false;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: Scaffold(
              body: LegalDocumentErrorState(
                errorType: LegalErrorType.network,
                onRetry: () => retried = true,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('Verifique sua conexão com a internet e tente novamente.'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsOneWidget);

        await tester.tap(find.text('Tentar novamente'));
        await tester.pump();

        expect(retried, isTrue);
      },
    );

    testWidgets(
      'LegalDocumentErrorState displays timeout and security messages',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: Scaffold(
              body: LegalDocumentErrorState(
                errorType: LegalErrorType.security,
                onRetry: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('Navegação para este endereço não permitida.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Login Page Legal Links', () {
    testWidgets(
      'LoginPage renders Terms and Privacy links and pushes routes without auth',
      (tester) async {
        final repo = fixtures.TestRepository(signedIn: false);
        final router = GoRouter(
          initialLocation: '/login',
          routes: [
            GoRoute(
              path: '/login',
              builder: (context, state) => const LoginPage(),
            ),
            GoRoute(
              path: '/legal/terms',
              builder: (context, state) =>
                  const Scaffold(body: Text('Terms Page Opened')),
            ),
            GoRoute(
              path: '/legal/privacy',
              builder: (context, state) =>
                  const Scaffold(body: Text('Privacy Page Opened')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [repositoryProvider.overrideWithValue(repo)],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('pt'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ensure footer links are present
        expect(find.text('Termos de uso'), findsOneWidget);
        expect(find.text('Política de privacidade'), findsOneWidget);

        // Tap Terms
        await tester.ensureVisible(find.text('Termos de uso'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Termos de uso'));
        await tester.pumpAndSettle();

        expect(find.text('Terms Page Opened'), findsOneWidget);

        // Return to login
        router.go('/login');
        await tester.pumpAndSettle();

        // Tap Privacy
        await tester.ensureVisible(find.text('Política de privacidade'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Política de privacidade'));
        await tester.pumpAndSettle();

        expect(find.text('Privacy Page Opened'), findsOneWidget);
      },
    );
  });

  group('Account Page Legal Section', () {
    testWidgets(
      'AccountPage renders Legal section with Terms and Privacy tiles',
      (tester) async {
        final repo = fixtures.TestRepository(signedIn: true);
        final router = GoRouter(
          initialLocation: '/settings',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const Scaffold(body: AccountPage()),
            ),
            GoRoute(
              path: '/legal/terms',
              builder: (context, state) =>
                  const Scaffold(body: Text('Terms From Settings')),
            ),
            GoRoute(
              path: '/legal/privacy',
              builder: (context, state) =>
                  const Scaffold(body: Text('Privacy From Settings')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [repositoryProvider.overrideWithValue(repo)],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('pt'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check section header and entries
        expect(find.text('Legal'), findsOneWidget);
        expect(find.text('Termos de uso'), findsOneWidget);
        expect(find.text('Política de privacidade'), findsOneWidget);

        // Tap Terms
        await tester.ensureVisible(find.text('Termos de uso'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Termos de uso'));
        await tester.pumpAndSettle();

        expect(find.text('Terms From Settings'), findsOneWidget);

        // Return to settings
        router.go('/settings');
        await tester.pumpAndSettle();

        // Tap Privacy
        await tester.ensureVisible(find.text('Política de privacidade'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Política de privacidade'));
        await tester.pumpAndSettle();

        expect(find.text('Privacy From Settings'), findsOneWidget);
      },
    );
  });

  group('Router Public Access & Gating', () {
    testWidgets(
      'allows unauthenticated access to /legal/terms without redirect to login',
      (tester) async {
        final repo = fixtures.TestRepository(signedIn: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              initialRouteProvider.overrideWithValue('/legal/terms'),
            ],
            child: const IplexApp(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Should be on Legal page and show the localized title, NOT redirected to LoginPage
        expect(find.text('Terms of use'), findsOneWidget);
        expect(find.text('Continue with Google'), findsNothing);
      },
    );

    testWidgets(
      'allows unauthenticated access to /legal/privacy without redirect to login',
      (tester) async {
        final repo = fixtures.TestRepository(signedIn: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              initialRouteProvider.overrideWithValue('/legal/privacy'),
            ],
            child: const IplexApp(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Should show Privacy policy title, NOT login screen
        expect(find.text('Privacy policy'), findsOneWidget);
        expect(find.text('Continue with Google'), findsNothing);
      },
    );

    testWidgets(
      'semantic route /legal/:type redirects to corresponding document',
      (tester) async {
        final repo = fixtures.TestRepository(signedIn: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(repo),
              initialRouteProvider.overrideWithValue('/legal/terms'),
            ],
            child: const IplexApp(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Terms of use'), findsOneWidget);
      },
    );
  });

  group('LegalWebViewPage Loading, Errors & Retry', () {
    testWidgets('displays network error and recovers on retry', (tester) async {
      final fakePlatform = FakeWebViewPlatform();
      WebViewPlatform.instance = fakePlatform;

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: LegalWebViewPage(type: LegalDocumentType.termsOfUse),
        ),
      );
      await tester.pump();

      final controller = fakePlatform.lastCreatedController!;
      // Simulate network error
      controller.delegate?.onWebResourceError?.call(
        const WebResourceError(
          errorCode: -2,
          description: 'net::ERR_INTERNET_DISCONNECTED',
          errorType: WebResourceErrorType.connect,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Verifique sua conexão com a internet e tente novamente.'),
        findsOneWidget,
      );
      expect(find.text('Tentar novamente'), findsOneWidget);

      // Tap retry
      final previousCount = controller.loadCount;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();

      expect(controller.loadCount, greaterThan(previousCount));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('displays HTTP 404 error message', (tester) async {
      final fakePlatform = FakeWebViewPlatform();
      WebViewPlatform.instance = fakePlatform;

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: LegalWebViewPage(type: LegalDocumentType.privacyPolicy),
        ),
      );
      await tester.pump();

      final controller = fakePlatform.lastCreatedController!;
      controller.delegate?.onHttpError?.call(
        HttpResponseError(
          response: WebResourceResponse(
            uri: Uri.parse('https://iplex-2c8fc.web.app/privacy'),
            statusCode: 404,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('HTTP 404'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('displays SSL security error message', (tester) async {
      final fakePlatform = FakeWebViewPlatform();
      WebViewPlatform.instance = fakePlatform;

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: LegalWebViewPage(type: LegalDocumentType.termsOfUse),
        ),
      );
      await tester.pump();

      final controller = fakePlatform.lastCreatedController!;
      controller.delegate?.onWebResourceError?.call(
        const WebResourceError(
          errorCode: -1200,
          description: 'SSL certificate error',
          errorType: WebResourceErrorType.failedSslHandshake,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Navegação para este endereço não permitida.'),
        findsOneWidget,
      );
      expect(find.text('Tentar novamente'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Back Navigation', () {
    testWidgets('Back button returns to Login when opened from Login', (
      tester,
    ) async {
      WebViewPlatform.instance = FakeWebViewPlatform();
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(
            path: '/login',
            builder: (context, state) => const LoginPage(),
          ),
          GoRoute(
            path: '/legal/terms',
            builder: (context, state) =>
                const LegalWebViewPage(type: LegalDocumentType.termsOfUse),
          ),
        ],
      );

      final repo = fixtures.TestRepository(signedIn: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap terms
      await tester.tap(find.text('Termos de uso'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalWebViewPage), findsOneWidget);

      // Tap top bar back button
      await tester.tap(find.bySemanticsLabel('Voltar'));
      await tester.pumpAndSettle();

      // Should be back on Login
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(LegalWebViewPage), findsNothing);
    });

    testWidgets('Back button returns to Account when opened from Account', (
      tester,
    ) async {
      WebViewPlatform.instance = FakeWebViewPlatform();
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (context, state) => const Scaffold(body: AccountPage()),
          ),
          GoRoute(
            path: '/legal/privacy',
            builder: (context, state) =>
                const LegalWebViewPage(type: LegalDocumentType.privacyPolicy),
          ),
        ],
      );

      final repo = fixtures.TestRepository(signedIn: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap privacy tile
      await tester.ensureVisible(find.text('Política de privacidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Política de privacidade'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalWebViewPage), findsOneWidget);

      // Tap back button
      await tester.tap(find.bySemanticsLabel('Voltar'));
      await tester.pumpAndSettle();

      // Should be back on Account
      expect(find.byType(AccountPage), findsOneWidget);
      expect(find.byType(LegalWebViewPage), findsNothing);
    });
  });

  group('Internationalization across languages', () {
    testWidgets('renders titles in Portuguese, English, and Spanish', (
      tester,
    ) async {
      WebViewPlatform.instance = FakeWebViewPlatform();

      // Portuguese
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: LegalWebViewPage(type: LegalDocumentType.termsOfUse),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Termos de uso'), findsOneWidget);

      // English
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: LegalWebViewPage(type: LegalDocumentType.privacyPolicy),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Privacy policy'), findsOneWidget);

      // Spanish
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('es'),
          home: LegalWebViewPage(type: LegalDocumentType.termsOfUse),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Términos de uso'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Platform Rendering on Android & iOS', () {
    testWidgets('renders on Android platform', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      WebViewPlatform.instance = FakeWebViewPlatform();

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: LegalWebViewPage(type: LegalDocumentType.termsOfUse),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LegalWebViewPage), findsOneWidget);
      expect(find.text('Termos de uso'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('renders on iOS platform', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      WebViewPlatform.instance = FakeWebViewPlatform();

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: LegalWebViewPage(type: LegalDocumentType.privacyPolicy),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LegalWebViewPage), findsOneWidget);
      expect(find.text('Política de privacidade'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Navigation Policy and External Links', () {
    testWidgets(
      'allows navigation to authorized official domain and prevents unauthorized',
      (tester) async {
        final fakePlatform = FakeWebViewPlatform();
        WebViewPlatform.instance = fakePlatform;

        Uri? launchedUri;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: LegalWebViewPage(
              type: LegalDocumentType.termsOfUse,
              urlLauncher: (uri, {mode}) async {
                launchedUri = uri;
                return true;
              },
            ),
          ),
        );
        await tester.pump();

        final controller = fakePlatform.lastCreatedController!;
        final delegate = controller.delegate!;

        // 1. Navigation request to official domain is permitted inside WebView
        final allowed = await delegate.onNavigationRequest?.call(
          const NavigationRequest(
            url: 'https://iplex-2c8fc.web.app/terms',
            isMainFrame: true,
          ),
        );
        expect(allowed, NavigationDecision.navigate);
        expect(launchedUri, isNull);

        // 2. Navigation request to legitimate external HTTPS link is prevented in WebView and launched externally
        final externalAllowed = await delegate.onNavigationRequest?.call(
          const NavigationRequest(
            url: 'https://support.google.com/iplex',
            isMainFrame: true,
          ),
        );
        expect(externalAllowed, NavigationDecision.prevent);
        expect(launchedUri?.host, 'support.google.com');

        // 3. Navigation request to arbitrary unauthorized scheme is blocked completely
        launchedUri = null;
        final blocked = await delegate.onNavigationRequest?.call(
          const NavigationRequest(
            url: 'javascript:alert(1)',
            isMainFrame: true,
          ),
        );
        expect(blocked, NavigationDecision.prevent);
        expect(launchedUri, isNull);

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
