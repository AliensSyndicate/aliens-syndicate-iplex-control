import 'dart:async';

import 'package:aliens_syndicate_iplex_control/features/player/playback_engine.dart';
import 'package:flutter/material.dart';

/// Media engine for widget tests (no native library): records what the
/// player asks and lets the test drive position, duration and the end.
class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine() {
    last = this;
  }

  /// The engine of the latest play.
  static FakePlaybackEngine? last;

  final opened = <(String, Duration?)>[];
  final seeks = <Duration>[];
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<bool>.broadcast(sync: true);
  final _tracks =
      StreamController<(List<PlaybackTrack>, List<PlaybackTrack>)>.broadcast(
        sync: true,
      );
  bool isPlaying = false, disposed = false;

  void emitPosition(Duration value) => _position.add(value);
  void emitDuration(Duration value) => _duration.add(value);
  void emitTracks(List<PlaybackTrack> audio, List<PlaybackTrack> text) =>
      _tracks.add((audio, text));
  void finish() => _completed.add(true);

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<String> get error => const Stream.empty();
  @override
  Stream<(int?, int?)> get size => Stream.value((1920, 1080));
  @override
  Stream<(List<PlaybackTrack>, List<PlaybackTrack>)> get tracks =>
      _tracks.stream;

  @override
  Future<void> open(String url, {Duration? start}) async {
    opened.add((url, start));
    await play();
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _position.add(position);
  }

  @override
  Future<void> selectAudio(String id) async {}
  @override
  Future<void> selectSubtitle(String? id) async {}
  @override
  Widget view() =>
      const ColoredBox(key: Key('fake-video'), color: Colors.black);
  @override
  Future<void> dispose() async => disposed = true;
}
