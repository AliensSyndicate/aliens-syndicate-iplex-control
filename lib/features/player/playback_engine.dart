import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'stream_proxy.dart';

/// One audio or subtitle track of the playing media.
@immutable
class PlaybackTrack {
  const PlaybackTrack(this.id, this.label);
  final String id;

  /// Title or language from the stream (null: unnamed).
  final String? label;
}

/// What the phone player needs from a media engine (media_kit in the app; a
/// fake in tests, where no native library exists).
abstract class PlaybackEngine {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<bool> get completed;
  Stream<String> get error;

  /// Video size in pixels (quality seal).
  Stream<(int?, int?)> get size;

  /// Audio and subtitle tracks of the stream (no "auto"/"off" entries).
  Stream<(List<PlaybackTrack>, List<PlaybackTrack>)> get tracks;

  Future<void> open(String url, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> selectAudio(String id);

  /// null: subtitles off.
  Future<void> selectSubtitle(String? id);
  Widget view();
  Future<void> dispose();
}

/// media_kit (libmpv): HLS, MPEG-TS live, MP4/MKV, audio and subtitle tracks.
class MediaKitEngine implements PlaybackEngine {
  MediaKitEngine() {
    MediaKit.ensureInitialized();
    _player = Player(
      configuration: PlayerConfiguration(
        logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
      ),
    );
    _controller = VideoController(_player);
    if (kDebugMode) {
      // Diagnostic only: what libmpv reports, with addresses removed (stream
      // URLs may carry IPTV credentials).
      String safe(String text) => text.replaceAll(
        RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false),
        '<url>',
      );
      _player.stream.log.listen(
        (l) => debugPrint('mpv ${l.level} ${l.prefix}: ${safe(l.text)}'),
      );
      _player.stream.error.listen((e) => debugPrint('mpv error: ${safe(e)}'));
    }
  }
  late final Player _player;
  late final VideoController _controller;

  static bool _real(String id) => id != 'auto' && id != 'no';
  static String? _label(String? title, String? language) => [
    title,
    language,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' · ').ifEmpty;

  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<String> get error => _player.stream.error;
  @override
  Stream<(int?, int?)> get size =>
      _player.stream.videoParams.map((p) => (p.dw ?? p.w, p.dh ?? p.h));
  @override
  Stream<(List<PlaybackTrack>, List<PlaybackTrack>)> get tracks =>
      _player.stream.tracks.map(
        (t) => (
          [
            for (final a in t.audio)
              if (_real(a.id)) PlaybackTrack(a.id, _label(a.title, a.language)),
          ],
          [
            for (final s in t.subtitle)
              if (_real(s.id)) PlaybackTrack(s.id, _label(s.title, s.language)),
          ],
        ),
      );

  /// Provider hosts that this network's DNS does not resolve still play:
  /// the engine opens the stream through the loopback [StreamProxy].
  StreamProxy? _proxy;

  @override
  Future<void> open(String url, {Duration? start}) async {
    final proxy = _proxy ??= await StreamProxy.start();
    final target = Uri.tryParse(url);
    await _player.open(
      Media(target == null ? url : proxy.wrap(target).toString(), start: start),
    );
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> selectAudio(String id) async {
    final track = _player.state.tracks.audio
        .where((a) => a.id == id)
        .firstOrNull;
    if (track != null) await _player.setAudioTrack(track);
  }

  @override
  Future<void> selectSubtitle(String? id) async {
    final track = id == null
        ? SubtitleTrack.no()
        : _player.state.tracks.subtitle.where((s) => s.id == id).firstOrNull;
    if (track != null) await _player.setSubtitleTrack(track);
  }

  @override
  Widget view() => Video(
    controller: _controller,
    controls: NoVideoControls,
    fill: Colors.black,
  );

  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _proxy?.close();
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}

/// Stand-in when the native engine cannot start (e.g. its library is
/// missing from the build): nothing plays and the player shows a message.
class UnavailablePlaybackEngine implements PlaybackEngine {
  const UnavailablePlaybackEngine();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  @override
  Stream<(int?, int?)> get size => const Stream.empty();
  @override
  Stream<(List<PlaybackTrack>, List<PlaybackTrack>)> get tracks =>
      const Stream.empty();
  @override
  Future<void> open(String url, {Duration? start}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> selectAudio(String id) async {}
  @override
  Future<void> selectSubtitle(String? id) async {}
  @override
  Widget view() => const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose() async {}
}

/// Creates the engine of each play (overridden in tests).
final playbackEngineProvider = Provider<PlaybackEngine Function()>(
  (ref) => MediaKitEngine.new,
);
