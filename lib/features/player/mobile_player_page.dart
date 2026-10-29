import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import '../../core/domain/repository.dart';
import '../home/home_data.dart';
import '../home/home_providers.dart';
import '../manager/widgets/profile_library.dart';
import '../watch_on_tv/watch_on_tv_sheet.dart';
import 'playback_engine.dart';
import 'player_rules.dart';

/// What the phone player opens: a catalog item, the episode of a series (or
/// the one in progress / the first) and whether it resumes saved progress.
@immutable
class MobilePlayerArgs {
  const MobilePlayerArgs(this.item, {this.episodeId, this.resume = false});
  final Entry item;
  final String? episodeId;
  final bool resume;
}

/// What the open player plays. The router rebuilds its pages when the
/// session or the family change (the player itself writes its session), and
/// a rebuilt location may come without its `extra`: the player keeps going
/// with these.
MobilePlayerArgs? currentPlayerArgs;

/// Plays [item] on this phone (full screen, landscape).
Future<void> openMobilePlayer(
  BuildContext context,
  Entry item, {
  String? episodeId,
  bool resume = false,
}) {
  final args = MobilePlayerArgs(item, episodeId: episodeId, resume: resume);
  currentPlayerArgs = args;
  return context.push('/player', extra: args);
}

/// Phone player, the same as the TV player (aliens-syndicate-iplex-web
/// `PlayerScreen`), driven by touch:
///
/// 1. A phone session in the backend (`startMobilePlayback`), with the TV
///    rules: subscription or trial, 3 simultaneous plays, 1 per profile.
/// 2. Adult content with a personal PIN: the video only loads after the PIN
///    (`verifyAdultPin`, single use).
/// 3. The authorized URL (`resolveSourceStream` with the session); IPTV
///    credentials never reach the app.
/// 4. Overlay: shows on start and hides after 5 s without a touch; a tap
///    shows it again. −10 s, play/pause, +10 s, timeline, quality seal,
///    audio and subtitles. Live channels: no timeline or jumps.
/// 5. Progress: VOD only, never adult or live (same rules as the TV).
/// 6. Series: "Próximo episódio" in the last 30 s; the end plays it.
/// 7. "Continuar na TV": saves the position, a TV is chosen and resumes
///    there at the same point; the phone stops.
/// The app is portrait; only this page turns to landscape.
class MobilePlayerPage extends ConsumerStatefulWidget {
  const MobilePlayerPage({super.key, required this.args});
  final MobilePlayerArgs args;

  @override
  ConsumerState<MobilePlayerPage> createState() => _MobilePlayerPageState();
}

/// Heartbeat of the phone session (the lease lasts 90 s).
const _heartbeatEvery = Duration(seconds: 30);

/// Progress is saved this often while playing (and on pause, exit and
/// "Continuar na TV").
const _progressEvery = Duration(seconds: 15);

class _MobilePlayerPageState extends ConsumerState<MobilePlayerPage> {
  late final PlaybackEngine engine = _createEngine();

  /// The native engine could not start: nothing is asked of the backend.
  bool engineUnavailable = false;

  PlaybackEngine _createEngine() {
    try {
      return ref.read(playbackEngineProvider)();
    } catch (_) {
      engineUnavailable = true;
      return const UnavailablePlaybackEngine();
    }
  }

  // Kept from the start: closing the page still saves and stops the session,
  // when `ref` is no longer usable.
  late final ManagerRepository repository = ref.read(repositoryProvider);
  late final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final subscriptions = <StreamSubscription<Object?>>[];
  Timer? heartbeat, progressTimer, overlayTimer;

  // Session.
  String? sessionId, profileId;
  bool pinRequired = false;
  Map<String, int> generations = const {};

  // What plays.
  List<TvEpisode> episodes = const [];
  TvEpisode? episode;
  bool preparing = true;
  Object? failure;

  // Media state.
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false, buffering = false;
  (int?, int?) size = (null, null);
  List<PlaybackTrack> audio = const [], subtitles = const [];
  String? subtitle;

  // Progress session (backend `progressSession`).
  String playId = '';
  int startedAt = 0, seq = 0;
  String origin = 'start';
  bool userSeek = false;

  // Overlay and seeking.
  bool overlay = true;
  Duration? scrubbing;

  /// The phone handed the title to a TV (closing does not save again).
  bool handedOff = false;

  Entry get item => widget.args.item;
  bool get live => item.isChannel;
  bool get adult => isAdultEntry(item);
  bool get series => item.kind == 'series';

  /// Progress is saved for movies and episodes, never adult or live.
  bool get persistent => !live && !adult && profileId != null;

  String get contentId =>
      episode == null ? item.id : episodeContentId(item.id, episode!.id);

  @override
  void initState() {
    super.initState();
    repository;
    container;
    subscriptions.addAll([
      engine.position.listen((p) {
        if (mounted) setState(() => position = p);
      }),
      engine.duration.listen((d) {
        if (mounted) setState(() => duration = d);
      }),
      engine.playing.listen((p) {
        if (!mounted) return;
        setState(() => playing = p);
        if (!p) unawaited(_saveProgress());
        _scheduleHide();
      }),
      engine.buffering.listen((b) {
        if (mounted) setState(() => buffering = b);
      }),
      engine.size.listen((s) {
        if (mounted) setState(() => size = s);
      }),
      engine.tracks.listen((t) {
        if (mounted) {
          setState(() {
            audio = t.$1;
            subtitles = t.$2;
          });
        }
      }),
      engine.completed.listen((done) {
        if (done && mounted) unawaited(_finished());
      }),
      engine.error.listen((message) {
        if (mounted && !preparing) {
          setState(() => failure = AppFailure(playbackErrorCode(message)));
        }
      }),
    ]);
    // After the first frame: the session uses the localized phone name.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (identical(currentPlayerArgs, widget.args)) currentPlayerArgs = null;
    for (final s in subscriptions) {
      s.cancel();
    }
    heartbeat?.cancel();
    progressTimer?.cancel();
    overlayTimer?.cancel();
    if (!handedOff) unawaited(_saveProgress());
    unawaited(_stopSession());
    unawaited(engine.dispose());
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) => repository.mutate(action, payload);

  Future<void> _start() async {
    if (engineUnavailable) {
      setState(() => failure = const AppFailure('playback-failed'));
      return;
    }
    try {
      final session = await _call('startMobilePlayback', {
        'deviceName': context.l.playerDeviceName,
      });
      sessionId = session['sessionId'] as String;
      profileId = session['profileId'] as String?;
      pinRequired = session['pinRequired'] == true;
      generations = {
        for (final MapEntry(:key, :value)
            in ((session['generations'] as Map?) ?? const {}).entries)
          if (value is num) '$key': value.toInt(),
      };
      heartbeat = Timer.periodic(_heartbeatEvery, (_) => _beat());
      if (series) {
        final result = await _call('readSourceSeries', {
          'id': item.sourceId,
          'seriesId': item.text('providerRef'),
        });
        episodes = parseEpisodes(result['details']);
        final wanted = widget.args.episodeId ?? item.episodeId;
        episode =
            episodes.where((e) => e.id == wanted).firstOrNull ??
            episodes.firstOrNull;
        if (episode == null) throw const AppFailure('content-unavailable');
      }
      final progress = item.progress;
      final resumeAt =
          widget.args.resume &&
              progress != null &&
              (!series || item.episodeId == episode?.id)
          ? Duration(seconds: progress.position.round())
          : null;
      await _play(resumeAt: resumeAt);
    } catch (e) {
      _log(e);
      if (mounted) setState(() => failure = e);
    }
  }

  /// Diagnostic in debug builds: the failure code, or the type and text of
  /// an app-side error with any address removed (stream URLs may carry IPTV
  /// credentials).
  void _log(Object error) {
    if (kDebugMode) {
      debugPrint(
        'mobile player failed: '
        '${error is AppFailure ? error.code : '${error.runtimeType}: ${'$error'.replaceAll(RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false), '<url>')}'}',
      );
    }
  }

  // The player turns itself: it enters in portrait, turns to landscape once
  // it is on screen and turns back before leaving, so the page behind never
  // turns.
  bool landscape = false, leaving = false;

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

  /// Leaves the player: back to portrait first (on this page), then out.
  Future<void> _leave() async {
    if (leaving) return;
    leaving = true;
    final view = View.of(context);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Wait for the screen to be upright (or give up after a moment).
    for (var i = 0; i < 16 && mounted; i++) {
      if (view.physicalSize.height >= view.physicalSize.width) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (mounted) context.pop();
  }

  /// Loads the current title or episode (PIN first for adult content).
  Future<void> _play({Duration? resumeAt}) async {
    setState(() {
      preparing = true;
      failure = null;
      position = Duration.zero;
      duration = Duration.zero;
    });
    if (adult && pinRequired && !await _askPin()) {
      if (mounted) unawaited(_leave());
      return;
    }
    final stream = await _call('resolveSourceStream', {
      'id': item.sourceId,
      'itemId': item.id,
      if (episode != null) 'episodeId': episode!.id,
      'sessionId': sessionId,
    });
    playId = _newPlayId();
    startedAt = DateTime.now().millisecondsSinceEpoch;
    seq = 0;
    origin = resumeAt == null ? 'start' : 'resume';
    userSeek = false;
    await engine.open(stream['url'] as String, start: resumeAt);
    progressTimer?.cancel();
    progressTimer = Timer.periodic(_progressEvery, (_) {
      if (playing) unawaited(_saveProgress());
    });
    if (mounted) setState(() => preparing = false);
    _showOverlay();
  }

  String _newPlayId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _beat() async {
    final id = sessionId;
    if (id == null) return;
    try {
      await _call('mobilePlaybackHeartbeat', {'sessionId': id});
    } catch (e) {
      // Session gone (subscription, limit taken elsewhere): playback stops.
      if (e is AppFailure &&
          ['session-expired', 'subscription-required'].contains(e.code) &&
          mounted) {
        await engine.pause();
        setState(() => failure = e);
      }
    }
  }

  Future<void> _stopSession() async {
    final id = sessionId;
    sessionId = null;
    if (id == null) return;
    try {
      await _call('stopMobilePlayback', {'sessionId': id});
    } catch (_) {
      // The lease expires by itself.
    }
  }

  Future<void> _saveProgress() async {
    final id = profileId;
    if (!persistent ||
        id == null ||
        sessionId == null ||
        duration <= Duration.zero ||
        playId.isEmpty) {
      return;
    }
    try {
      await _call('watchProgress', {
        'profileId': id,
        'contentId': contentId,
        'position': position.inMilliseconds / 1000,
        'duration': duration.inMilliseconds / 1000,
        'generation': generations['progress'] ?? 0,
        'watchedGeneration': ?generations['watched'],
        'playId': playId,
        'startedAt': startedAt,
        'seq': ++seq,
        'origin': origin,
        if (userSeek) 'userSeek': true,
      });
      container
        ..invalidate(homeProvider)
        ..invalidate(profileLibraryProvider);
    } catch (_) {
      // Progress only: playback goes on.
    }
  }

  Future<void> _finished() async {
    await _saveProgress();
    final next = series ? findNextEpisode(episodes, episode?.id) : null;
    if (next == null) {
      if (mounted) unawaited(_leave());
      return;
    }
    await _playEpisode(next);
  }

  Future<void> _playEpisode(TvEpisode next) async {
    await _saveProgress();
    episode = next;
    try {
      await _play();
    } catch (e) {
      if (mounted) setState(() => failure = e);
    }
  }

  Future<bool> _askPin() async =>
      await showAppModalSheet<bool>(
        context: context,
        isDismissible: false,
        builder: (_) => _AdultPinSheet(
          verify: (pin) =>
              _call('verifyAdultPin', {'sessionId': sessionId, 'pin': pin}),
        ),
      ) ??
      false;

  /// "Continuar na TV": the position is saved first, so the chosen TV resumes
  /// at the same point; once a TV accepts, the phone stops.
  Future<void> _continueOnTv() async {
    await engine.pause();
    await _saveProgress();
    if (!mounted) return;
    await showWatchOnTv(
      context,
      item,
      resume: persistent,
      episodeId: episode?.id,
      onSent: () {
        handedOff = true;
        progressTimer?.cancel();
        unawaited(engine.pause());
        unawaited(_stopSession());
      },
    );
    if (!mounted) return;
    if (handedOff) {
      unawaited(_leave());
    } else {
      await engine.play();
    }
  }

  void _showOverlay() {
    setState(() => overlay = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    overlayTimer?.cancel();
    if (!playing || scrubbing != null) return;
    overlayTimer = Timer(overlayTimeout, () {
      if (mounted && playing) setState(() => overlay = false);
    });
  }

  Future<void> _seek(Duration target) async {
    final clamped = clampSeek(target, duration);
    if (clamped == null) return;
    userSeek = true;
    await engine.seek(clamped);
    _scheduleHide();
  }

  Future<void> _pickTrack(bool isAudio) async {
    final l = context.l;
    final options = isAudio ? audio : subtitles;
    final picked = await showAppModalSheet<String>(
      context: context,
      builder: (sheet) => AppModalSheet(
        title: isAudio ? l.playerAudio : l.playerSubtitles,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isAudio)
              SelectionRow(
                key: const ValueKey('track-off'),
                title: l.playerSubtitlesOff,
                selected: subtitle == null,
                onTap: () => Navigator.of(sheet).pop(''),
              ),
            for (final (i, t) in options.indexed)
              SelectionRow(
                key: ValueKey('track-${t.id}'),
                title: t.label ?? '${i + 1}',
                selected: !isAudio && subtitle == t.id,
                onTap: () => Navigator.of(sheet).pop(t.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (isAudio) {
      await engine.selectAudio(picked);
    } else {
      setState(() => subtitle = picked.isEmpty ? null : picked);
      await engine.selectSubtitle(subtitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final failure = this.failure;
    final next = series ? findNextEpisode(episodes, episode?.id) : null;
    final countdown = live ? null : nextEpisodeCountdown(position, duration);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        key: const Key('mobile-player'),
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => overlay && playing
              ? setState(() => overlay = false)
              : _showOverlay(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              engine.view(),
              if (failure != null)
                _PlayerMessage(
                  text: failureText(context, failure),
                  onBack: _leave,
                )
              else if (preparing || buffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (failure == null)
                AnimatedOpacity(
                  opacity: overlay ? 1 : 0,
                  duration: AppMotion.duration(context, AppMotion.selection),
                  child: IgnorePointer(
                    ignoring: !overlay,
                    child: _Overlay(
                      title: item.name,
                      episode: episode,
                      live: live,
                      playing: playing,
                      position: scrubbing ?? position,
                      duration: duration,
                      quality: qualityLabel(size.$1, size.$2),
                      hasAudio: audio.length > 1,
                      hasSubtitles: subtitles.isNotEmpty,
                      onBack: _leave,
                      onContinueOnTv: preparing ? null : _continueOnTv,
                      onToggle: () {
                        playing ? engine.pause() : engine.play();
                        _showOverlay();
                      },
                      onSkip: (forward) =>
                          _seek(position + (forward ? skipStep : -skipStep)),
                      onScrub: (value) {
                        overlayTimer?.cancel();
                        setState(() => scrubbing = value);
                      },
                      onScrubEnd: (value) {
                        setState(() => scrubbing = null);
                        _seek(value);
                      },
                      onAudio: () => _pickTrack(true),
                      onSubtitles: () => _pickTrack(false),
                    ),
                  ),
                ),
              if (failure == null && next != null && countdown != null)
                Positioned(
                  right: AppSpacing.lg,
                  bottom: AppSpacing.xxl * 2,
                  child: AppButton.primary(
                    key: const Key('player-next-episode'),
                    width: 260,
                    icon: AppIcons.play,
                    label: '${l.nextEpisode} · ${countdown}s',
                    onPressed: () => _playEpisode(next),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay of the player (same parts as the TV `PlayerOverlay`): title and
/// episode, "Continuar na TV", −10 s / play-pause / +10 s, timeline with
/// times, quality seal and the audio / subtitle choices.
class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.title,
    required this.episode,
    required this.live,
    required this.playing,
    required this.position,
    required this.duration,
    required this.quality,
    required this.hasAudio,
    required this.hasSubtitles,
    required this.onBack,
    required this.onContinueOnTv,
    required this.onToggle,
    required this.onSkip,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onAudio,
    required this.onSubtitles,
  });
  final String title;
  final TvEpisode? episode;
  final bool live, playing, hasAudio, hasSubtitles;
  final Duration position, duration;
  final String? quality;
  final VoidCallback onBack, onToggle, onAudio, onSubtitles;
  final VoidCallback? onContinueOnTv;
  final ValueChanged<bool> onSkip;
  final ValueChanged<Duration> onScrub, onScrubEnd;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final seekable = !live && duration > Duration.zero;
    final hours = duration.inHours > 0;
    final episode = this.episode;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Colors.transparent, Color(0xCC000000)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircularButton(
                  key: const Key('player-back'),
                  label: l.back,
                  icon: AppIcons.left,
                  onPressed: onBack,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleLarge,
                      ),
                      if (episode != null)
                        Text(
                          [
                            episodeCode(episode),
                            if (episode.title.isNotEmpty) episode.title,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // "Continuar na TV": the icon only, no label or background.
                Semantics(
                  button: true,
                  enabled: onContinueOnTv != null,
                  label: l.continueOnTv,
                  child: InkResponse(
                    key: const Key('player-continue-on-tv'),
                    onTap: onContinueOnTv,
                    radius: AppDimensions.touch / 2,
                    child: SizedBox.square(
                      dimension: AppDimensions.touch,
                      child: Center(
                        child: AppIcon(
                          AppIcons.devices,
                          color: onContinueOnTv == null
                              ? AppColors.textDisabled
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (!live)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularButton(
                    key: const Key('player-skip-back'),
                    label: l.playerSkipBack,
                    icon: AppIcons.skipBack,
                    onPressed: seekable ? () => onSkip(false) : null,
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  CircularButton(
                    key: const Key('player-toggle'),
                    label: playing ? l.playerPause : l.playerPlay,
                    icon: playing ? AppIcons.pause : AppIcons.play,
                    size: AppDimensions.touch * 1.4,
                    onPressed: onToggle,
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  CircularButton(
                    key: const Key('player-skip-forward'),
                    label: l.playerSkipForward,
                    icon: AppIcons.skipForward,
                    onPressed: seekable ? () => onSkip(true) : null,
                  ),
                ],
              )
            else
              Center(
                child: CircularButton(
                  key: const Key('player-toggle'),
                  label: playing ? l.playerPause : l.playerPlay,
                  icon: playing ? AppIcons.pause : AppIcons.play,
                  size: AppDimensions.touch * 1.4,
                  onPressed: onToggle,
                ),
              ),
            const Spacer(),
            if (seekable)
              Row(
                children: [
                  Text(
                    formatTimecode(position, withHours: hours),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: const Color(0x4DFFFFFF),
                        thumbColor: AppColors.primary,
                        overlayColor: const Color(0x22FFFFFF),
                      ),
                      child: Slider(
                        key: const Key('player-timeline'),
                        value: position.inMilliseconds
                            .clamp(0, duration.inMilliseconds)
                            .toDouble(),
                        max: duration.inMilliseconds.toDouble(),
                        onChanged: (v) =>
                            onScrub(Duration(milliseconds: v.round())),
                        onChangeEnd: (v) =>
                            onScrubEnd(Duration(milliseconds: v.round())),
                      ),
                    ),
                  ),
                  Text(
                    formatTimecode(duration, withHours: hours),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                if (live) _Badge(l.playerLive),
                if (quality case final q?) _Badge(q),
                const Spacer(),
                if (hasAudio)
                  CircularButton(
                    key: const Key('player-audio'),
                    label: l.playerAudio,
                    icon: AppIcons.audio,
                    onPressed: onAudio,
                  ),
                if (hasSubtitles) ...[
                  const SizedBox(width: AppSpacing.sm),
                  CircularButton(
                    key: const Key('player-subtitles'),
                    label: l.playerSubtitles,
                    icon: AppIcons.subtitles,
                    onPressed: onSubtitles,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Technical seal (quality, "Ao vivo").
class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: AppSpacing.sm),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.textSecondary),
      borderRadius: BorderRadius.circular(AppRadii.xs),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

/// A failure inside the player: the specific message and a way back.
class _PlayerMessage extends StatelessWidget {
  const _PlayerMessage({required this.text, required this.onBack});
  final String text;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            key: const Key('player-failure'),
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const Key('player-failure-back'),
            fit: true,
            label: context.l.back,
            onPressed: onBack,
          ),
        ],
      ),
    ),
  );
}

/// Personal PIN before adult content (same rule as the TV).
class _AdultPinSheet extends StatefulWidget {
  const _AdultPinSheet({required this.verify});
  final Future<Map<String, dynamic>> Function(String pin) verify;
  @override
  State<_AdultPinSheet> createState() => _AdultPinSheetState();
}

class _AdultPinSheetState extends State<_AdultPinSheet> {
  final pin = TextEditingController();
  bool busy = false;
  String? message;

  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || pin.text.length != 4) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await widget.verify(pin.text);
      if (!mounted) return;
      if (result['verified'] == true) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => message = context.l.errorPinInvalid);
    } catch (e) {
      if (mounted) setState(() => message = failureText(context, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AppModalSheet(
      title: l.profilePinTitle,
      description: l.adultPinBody,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: const Key('player-pin'),
            label: l.profilePinTitle,
            controller: pin,
            secret: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          if (message != null)
            Text(
              message!,
              key: const Key('player-pin-error'),
              style: const TextStyle(color: AppColors.error),
            ),
        ],
      ),
      actions: [
        AppButton.primary(
          key: const Key('player-pin-submit'),
          label: l.unlock,
          busy: busy,
          onPressed: pin.text.length == 4 ? submit : null,
        ),
        AppButton(
          label: l.cancel,
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
