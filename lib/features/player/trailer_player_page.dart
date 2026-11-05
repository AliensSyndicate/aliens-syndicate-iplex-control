import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/design_system/components.dart';

/// Opens the trailer on its own player screen; a video that cannot play
/// (embedding refused by its owner, no connection) comes back with a notice.
Future<void> openTrailer(BuildContext context, String videoKey) async {
  final played = await context.push<bool>('/trailer/$videoKey');
  if (played == false && context.mounted) {
    showAppFeedbackSheet(
      context: context,
      message: context.l.trailerUnavailable,
    );
  }
}

/// Trailer player: full screen and landscape, the same way as the movie player
/// (`MobilePlayerPage`). TMDB only offers YouTube videos, so it plays in the
/// official embedded player, with its own controls. The end of the video, the
/// back button and the background all leave the page.
class TrailerPlayerPage extends StatefulWidget {
  const TrailerPlayerPage({super.key, required this.videoKey});
  final String videoKey;

  /// Without playing by then, it gives up.
  static const giveUpAfter = Duration(seconds: 20);

  /// YouTube needs a real origin to embed; the page itself is local.
  static const baseUrl = 'https://iplex-2c8fc.web.app';

  @override
  State<TrailerPlayerPage> createState() => _TrailerPlayerPageState();
}

class _TrailerPlayerPageState extends State<TrailerPlayerPage>
    with WidgetsBindingObserver {
  late final WebViewController web = _createWebView();
  Timer? giveUp;
  bool playing = false;

  // The page turns itself, as the movie player: it enters in portrait, turns
  // to landscape once on screen and turns back before leaving, so the page
  // behind never turns.
  bool landscape = false, leaving = false;

  WebViewController _createWebView() {
    final creation = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const {},
          )
        : const PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(creation)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Trailer', onMessageReceived: _onMessage);
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
    }
    unawaited(
      controller.loadHtmlString(
        trailerPage(widget.videoKey),
        baseUrl: TrailerPlayerPage.baseUrl,
      ),
    );
    return controller;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    giveUp = Timer(TrailerPlayerPage.giveUpAfter, () {
      if (!playing) unawaited(_leave(played: false));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (landscape || leaving) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _turnLandscape();
    } else {
      void entered(AnimationStatus status) {
        if (status != AnimationStatus.completed) return;
        animation.removeStatusListener(entered);
        _turnLandscape();
      }

      animation.addStatusListener(entered);
    }
  }

  void _turnLandscape() {
    if (landscape || leaving || !mounted) return;
    landscape = true;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_leave());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    giveUp?.cancel();
    // The audio of a removed web view could go on until it is collected.
    unawaited(web.loadHtmlString('<html></html>'));
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Back to portrait first (on this page), then out.
  Future<void> _leave({bool played = true}) async {
    if (leaving) return;
    leaving = true;
    final view = View.of(context);
    unawaited(web.loadHtmlString('<html></html>'));
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Wait for the screen to be upright (or give up after a moment).
    for (var i = 0; i < 16 && mounted; i++) {
      if (view.physicalSize.height >= view.physicalSize.width) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (mounted) Navigator.of(context).pop(played);
  }

  void _onMessage(JavaScriptMessage message) {
    if (!mounted) return;
    switch (message.message) {
      case 'playing':
        giveUp?.cancel();
        setState(() => playing = true);
      case 'ended':
        unawaited(_leave());
      case 'error':
        unawaited(_leave(played: false));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      key: const Key('trailer-player'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: web),
          if (!playing)
            const IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          SafeArea(
            minimum: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: Alignment.topLeft,
              child: CircularButton(
                key: const Key('trailer-back'),
                label: context.l.back,
                icon: AppIcons.left,
                onPressed: _leave,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Page of the embedded player; reports its state to the `Trailer` channel.
String trailerPage(String videoKey) =>
    '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html, body { margin: 0; height: 100%; overflow: hidden; background: #000; }
#player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
</style>
</head>
<body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
function onYouTubeIframeAPIReady() {
  new YT.Player('player', {
    videoId: '$videoKey',
    host: 'https://www.youtube-nocookie.com',
    width: '100%',
    height: '100%',
    playerVars: { autoplay: 1, controls: 1, fs: 0, iv_load_policy: 3, modestbranding: 1, playsinline: 1, rel: 0 },
    events: {
      onReady: function (e) { e.target.playVideo(); },
      onStateChange: function (e) {
        if (e.data === 1) Trailer.postMessage('playing');
        if (e.data === 0) Trailer.postMessage('ended');
      },
      onError: function () { Trailer.postMessage('error'); }
    }
  });
}
</script>
</body>
</html>
''';
