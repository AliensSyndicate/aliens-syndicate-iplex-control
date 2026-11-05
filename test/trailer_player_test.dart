import 'package:aliens_syndicate_iplex_control/features/home/metadata_service.dart';
import 'package:aliens_syndicate_iplex_control/features/player/trailer_player_page.dart';
import 'package:aliens_syndicate_iplex_control/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fake_webview_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only a valid YouTube id reaches the page', () {
    expect(
      ContentMetadata.fromJson({'trailerKey': 'abc_123-XY'}).trailerKey,
      'abc_123-XY',
    );
    expect(
      ContentMetadata.fromJson({'trailerKey': "a'; alert(1)"}).trailerKey,
      isNull,
    );
    expect(ContentMetadata.fromJson({}).trailerKey, isNull);
  });

  test('the page embeds the video and reports to the channel', () {
    final page = trailerPage('abc123');
    expect(page, contains("videoId: 'abc123'"));
    expect(page, contains("Trailer.postMessage('playing')"));
  });

  testWidgets('turns to landscape, and back to portrait on leaving', (
    tester,
  ) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    final orientations = <List<String>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add((call.arguments as List).cast<String>());
        }
        return null;
      },
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('details')),
      ),
    );
    final played = navigator.currentState!.push<bool>(
      MaterialPageRoute(
        builder: (_) => const TrailerPlayerPage(videoKey: 'abc123'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('trailer-player')), findsOneWidget);
    expect(orientations.last, contains('DeviceOrientation.landscapeLeft'));
    await tester.tap(find.byKey(const Key('trailer-back')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('details'), findsOneWidget);
    expect(orientations.last, ['DeviceOrientation.portraitUp']);
    expect(await played, isTrue);
  });
}
