import 'package:aliens_syndicate_iplex_control/core/data/providers.dart';
import 'package:aliens_syndicate_iplex_control/features/player/playback_engine.dart';
import 'package:aliens_syndicate_iplex_control/app/router.dart';
import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/player/mobile_player_page.dart';
import 'package:aliens_syndicate_iplex_control/features/player/player_rules.dart';
import 'package:aliens_syndicate_iplex_control/features/watch_on_tv/watch_on_tv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'home_page_test.dart' show profile;
import 'navigation_test.dart' as navigation;
import 'support/fake_playback_engine.dart';
import 'widget_test.dart' as fixtures;

/// Backend of the phone player (mobile session, stream, PIN, progress).
class _PlayerRepo extends navigation.SessionRepository {
  _PlayerRepo({this.pinRequired = false, this.subscription = true})
    : super(uid: 'u', linked: true) {
    sources = [
      Entry('s', {'name': 'Minha IPTV', 'version': 'v', 'status': 'ready'}),
    ];
    home = {'profile': profile};
  }
  final bool pinRequired, subscription;
  final calls = <(String, Map<String, dynamic>)>[];

  Iterable<Map<String, dynamic>> called(String action) =>
      calls.where((c) => c.$1 == action).map((c) => c.$2);

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add((action, Map.of(payload)));
    switch (action) {
      case 'startMobilePlayback':
        if (!subscription) throw const AppFailure('subscription-required');
        return {
          'sessionId': 'session1',
          'profileId': 'admin',
          'pinRequired': pinRequired,
          'generations': {'progress': 4, 'watched': 2},
        };
      case 'resolveSourceStream':
        return {
          'url':
              'https://example.com/${payload['episodeId'] ?? payload['itemId']}.mp4',
        };
      case 'verifyAdultPin':
        return {'verified': payload['pin'] == '2468', 'required': true};
      case 'readSourceSeries':
        return {
          'details': {
            'episodes': {
              '1': [
                {'id': 'e1', 'title': 'Piloto', 'season': 1, 'episodeNum': 1},
                {'id': 'e2', 'title': 'Segundo', 'season': 1, 'episodeNum': 2},
              ],
            },
          },
        };
      case 'mobilePlaybackHeartbeat' || 'stopMobilePlayback' || 'watchProgress':
        return {'ok': true};
    }
    return super.mutate(action, payload);
  }
}

Entry _movie({
  String id = 'm1',
  String title = 'Filme',
  Map<String, dynamic>? progress,
}) => Entry(id, {
  'title': title,
  'kind': 'movie',
  'sourceId': 's',
  'providerRef': '1',
  'category': 'Filmes',
  'progress': ?progress,
});

/// The loading spinner turns while a PIN is asked: frames instead of settling.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(fixtures.loadTestFont);
  late List<List<String>> orientations;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    orientations = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add((call.arguments as List).cast<String>());
          }
          return null;
        });
  });

  Future<void> open(
    WidgetTester tester,
    _PlayerRepo repo,
    MobilePlayerArgs args,
  ) async {
    await navigation.launch(tester, repo);
    GoRouter.of(tester.element(find.byKey(const Key('home-title'))))
        .push('/player', extra: args);
    await _settle(tester);
  }

  testWidgets('plays a movie in its own session, in landscape; progress on '
      'pause; back stops the session and returns to portrait', (tester) async {
    final repo = _PlayerRepo();
    await open(tester, repo, MobilePlayerArgs(_movie()));
    expect(orientations.last, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    final engine = FakePlaybackEngine.last!;
    expect(repo.called('startMobilePlayback').single['deviceName'], 'Phone');
    expect(repo.called('resolveSourceStream').single, {
      'id': 's',
      'itemId': 'm1',
      'sessionId': 'session1',
    });
    expect(engine.opened.single, ('https://example.com/m1.mp4', null));

    // Overlay: title, "Continue on TV", and it hides after 5 s.
    expect(find.text('Filme'), findsOneWidget);
    expect(find.byKey(const Key('player-continue-on-tv')), findsOneWidget);
    // Icon only: no label and no background surface.
    expect(
      find.descendant(
        of: find.byKey(const Key('player-continue-on-tv')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Continue on TV'), findsOneWidget);
    expect(find.text('Full HD'), findsOneWidget);
    engine.emitDuration(const Duration(minutes: 100));
    engine.emitPosition(const Duration(minutes: 30));
    await tester.pump(const Duration(seconds: 6));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byKey(const Key('player-continue-on-tv')),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );
    // A tap shows it again; pause saves the progress with the generations.
    await tester.tapAt(const Offset(300, 200));
    await tester.pump();
    await tester.tap(find.byKey(const Key('player-toggle')));
    await tester.pump();
    final progress = repo.called('watchProgress').last;
    expect(progress, containsPair('contentId', 'm1'));
    expect(progress, containsPair('position', 1800.0));
    expect(progress, containsPair('duration', 6000.0));
    expect(progress, containsPair('generation', 4));
    expect(progress, containsPair('watchedGeneration', 2));
    expect(progress, containsPair('origin', 'start'));

    // −10 s.
    await tester.tap(find.byKey(const Key('player-skip-back')));
    await tester.pump();
    expect(engine.seeks.last, const Duration(minutes: 29, seconds: 50));

    await tester.tap(find.byKey(const Key('player-back')));
    await tester.pumpAndSettle();
    expect(find.byType(MobilePlayerPage), findsNothing);
    expect(repo.called('stopMobilePlayback').single, {'sessionId': 'session1'});
    expect(orientations.last, ['DeviceOrientation.portraitUp']);
    expect(engine.disposed, isTrue);
  });

  testWidgets('"Continue" resumes the saved position', (tester) async {
    final repo = _PlayerRepo();
    await open(
      tester,
      repo,
      MobilePlayerArgs(
        _movie(progress: {'position': 120, 'duration': 6000}),
        resume: true,
      ),
    );
    expect(
      FakePlaybackEngine.last!.opened.single.$2,
      const Duration(seconds: 120),
    );
  });

  testWidgets('adult content asks for the profile PIN before loading', (
    tester,
  ) async {
    final repo = _PlayerRepo(pinRequired: true);
    await open(
      tester,
      repo,
      MobilePlayerArgs(_movie(id: 'x1', title: 'XXX Night')),
    );
    expect(repo.called('resolveSourceStream'), isEmpty);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('player-pin')),
        matching: find.byType(EditableText),
      ),
      '1111',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('player-pin-submit')));
    await _settle(tester);
    expect(find.byKey(const Key('player-pin-error')), findsOneWidget);
    expect(repo.called('resolveSourceStream'), isEmpty);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('player-pin')),
        matching: find.byType(EditableText),
      ),
      '2468',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('player-pin-submit')));
    await _settle(tester);
    expect(repo.called('verifyAdultPin').last, {
      'sessionId': 'session1',
      'pin': '2468',
    });
    expect(repo.called('resolveSourceStream').single['itemId'], 'x1');
    // Adult content never saves progress.
    await tester.tap(find.byKey(const Key('player-toggle')));
    await tester.pump();
    expect(repo.called('watchProgress'), isEmpty);
  });

  testWidgets('series: the chosen episode, "Next episode" in the last 30 s and '
      'the end plays it', (tester) async {
    final repo = _PlayerRepo();
    final series = Entry('se1', {
      'title': 'Série',
      'kind': 'series',
      'sourceId': 's',
      'providerRef': '77',
      'category': 'Séries',
    });
    await open(tester, repo, MobilePlayerArgs(series, episodeId: 'e1'));
    final engine = FakePlaybackEngine.last!;
    expect(engine.opened.single.$1, 'https://example.com/e1.mp4');
    expect(find.text('T1:E1 · Piloto'), findsOneWidget);
    engine.emitDuration(const Duration(minutes: 40));
    engine.emitPosition(const Duration(minutes: 39, seconds: 40));
    await tester.pump();
    expect(find.byKey(const Key('player-next-episode')), findsOneWidget);
    engine.finish();
    await tester.pumpAndSettle();
    expect(engine.opened.last.$1, 'https://example.com/e2.mp4');
    // Episode progress uses its own content id.
    await tester.tap(find.byKey(const Key('player-toggle')));
    await tester.pump();
    engine.emitDuration(const Duration(minutes: 40));
    engine.emitPosition(const Duration(minutes: 5));
    await tester.tap(find.byKey(const Key('player-toggle')));
    await tester.tap(find.byKey(const Key('player-toggle')));
    await tester.pump();
    expect(
      repo.called('watchProgress').last['contentId'],
      episodeContentId('se1', 'e2'),
    );
  });

  testWidgets('"Continue on TV" saves the position, a TV takes over and the '
      'phone stops', (tester) async {
    final repo = _PlayerRepo();
    await open(tester, repo, MobilePlayerArgs(_movie()));
    final engine = FakePlaybackEngine.last!;
    engine.emitDuration(const Duration(minutes: 100));
    engine.emitPosition(const Duration(minutes: 42));
    await tester.tap(find.byKey(const Key('player-continue-on-tv')));
    await tester.pumpAndSettle();
    expect(engine.isPlaying, isFalse);
    expect(repo.called('watchProgress').last['position'], 2520.0);
    final sheet = tester.widget<WatchOnTvSheet>(find.byType(WatchOnTvSheet));
    expect(sheet.resume, isTrue);
    // The TV accepted the request.
    sheet.onSent!();
    Navigator.of(tester.element(find.byType(WatchOnTvSheet))).pop();
    await tester.pumpAndSettle();
    expect(repo.called('stopMobilePlayback'), isNotEmpty);
    expect(find.byType(MobilePlayerPage), findsNothing);
  });

  testWidgets('without subscription or trial: the specific message', (
    tester,
  ) async {
    final repo = _PlayerRepo(subscription: false);
    await open(tester, repo, MobilePlayerArgs(_movie()));
    expect(find.byKey(const Key('player-failure')), findsOneWidget);
    expect(repo.called('resolveSourceStream'), isEmpty);
    // "Back" as wide as its label, not the whole screen.
    expect(
      tester.getSize(find.byKey(const Key('player-failure-back'))).width,
      lessThan(
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
      ),
    );
  });

  testWidgets('engine that cannot start (native library missing): the '
      'message, no session', (tester) async {
    final repo = _PlayerRepo();
    final container = await navigation.launch(tester, repo);
    container.updateOverrides([
      repositoryProvider.overrideWithValue(repo),
      initialRouteProvider.overrideWithValue('/home'),
      playbackEngineProvider.overrideWithValue(
        () => throw Exception('Cannot find libmpv.so'),
      ),
    ]);
    GoRouter.of(tester.element(find.byKey(const Key('home-title'))))
        .push('/player', extra: MobilePlayerArgs(_movie()));
    await _settle(tester);
    expect(find.byKey(const Key('player-failure')), findsOneWidget);
    expect(find.text('This content could not be played.'), findsOneWidget);
    expect(repo.called('startMobilePlayback'), isEmpty);
  });

  testWidgets('a rebuilt player location without its extra keeps playing; '
      'with nothing playing it goes Home instead of failing', (tester) async {
    final repo = _PlayerRepo();
    await navigation.launch(tester, repo);
    final context = tester.element(find.byKey(const Key('home-title')));
    final router = GoRouter.of(context);
    openMobilePlayer(context, _movie());
    await _settle(tester);
    expect(find.byType(MobilePlayerPage), findsOneWidget);
    // The router rebuilds the location (session/family refresh): no extra.
    router.go('/player');
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<MobilePlayerPage>(find.byType(MobilePlayerPage))
          .args
          .item
          .id,
      'm1',
    );
    router.go('/home');
    await _settle(tester);
    expect(currentPlayerArgs, isNull);
    router.go('/player');
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(MobilePlayerPage), findsNothing);
    expect(find.byKey(const Key('home-title')), findsOneWidget);
  });

  test('rules: seals, codes, times, next episode, seek limits', () {
    expect(qualityLabel(3840, 2160), '4K');
    expect(qualityLabel(1280, 720), 'HD');
    expect(qualityLabel(null, 720), isNull);
    expect(formatTimecode(const Duration(minutes: 38, seconds: 12)), '38:12');
    expect(formatTimecode(const Duration(hours: 1, seconds: 5)), '01:00:05');
    expect(
      nextEpisodeCountdown(
        const Duration(seconds: 80),
        const Duration(seconds: 100),
      ),
      20,
    );
    expect(
      nextEpisodeCountdown(
        const Duration(seconds: 10),
        const Duration(seconds: 100),
      ),
      isNull,
    );
    expect(
      clampSeek(const Duration(seconds: 200), const Duration(seconds: 100)),
      const Duration(seconds: 99),
    );
    expect(
      clampSeek(const Duration(seconds: -5), const Duration(seconds: 100)),
      Duration.zero,
    );
    expect(episodeContentId('abc', 'e 1'), 'abc_ee1');
    expect(
      playbackErrorCode(
        'tcp: Failed to resolve hostname x.example: No address associated',
      ),
      'stream-unreachable',
    );
    expect(playbackErrorCode('Failed to open <url>'), 'stream-unreachable');
    expect(playbackErrorCode('Could not decode video'), 'playback-failed');
  });
}
