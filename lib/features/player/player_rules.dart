/// Pure rules of the phone player, the same as the TV player
/// (aliens-syndicate-iplex-web `features/playback/playerRules.ts`).
library;

import '../watch_on_tv/watch_on_tv_sheet.dart';

/// Side buttons jump this far.
const skipStep = Duration(seconds: 10);

/// "Próximo episódio" shows in the last 30 s of an episode.
const nextEpisodeWindow = Duration(seconds: 30);

/// The overlay hides after this long without a touch.
const overlayTimeout = Duration(seconds: 5);

/// Last accepted seek point: the exact end would finish the media by mistake.
const _seekEndGuard = Duration(seconds: 1);

/// Valid seek position, or null when the media has no known duration.
Duration? clampSeek(Duration target, Duration duration) {
  if (duration <= Duration.zero) return null;
  final last = duration - _seekEndGuard;
  if (target < Duration.zero) return Duration.zero;
  return target > last ? last : target;
}

/// Known video size → seal; without reliable dimensions, none.
String? qualityLabel(int? width, int? height) {
  final w = width ?? 0, h = height ?? 0;
  if (w <= 0 || h <= 0) return null;
  if (w >= 3200 || h >= 1800) return '4K';
  if (w >= 1800 || h >= 1000) return 'Full HD';
  if (w >= 1200 || h >= 700) return 'HD';
  return 'SD';
}

/// "T1:E3" (compact); without an episode number, only the season.
String episodeCode(TvEpisode episode) => episode.number.isEmpty
    ? 'T${episode.season}'
    : 'T${episode.season}:E${episode.number}';

String _two(int n) => n.toString().padLeft(2, '0');

/// 00:38:12 (with hours when the media has 1 h or more) or 38:12.
String formatTimecode(Duration value, {bool withHours = false}) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  return withHours || h > 0
      ? '${_two(h)}:${_two(m)}:${_two(s)}'
      : '${_two(m)}:${_two(s)}';
}

/// Seconds left for the next episode, from the media's real time; null
/// outside the final window.
int? nextEpisodeCountdown(Duration position, Duration duration) {
  if (duration <= nextEpisodeWindow || position < Duration.zero) return null;
  final remaining = duration - position;
  if (remaining > nextEpisodeWindow) return null;
  return (remaining.inMilliseconds / 1000).ceil().clamp(0, 1 << 30);
}

/// Next playable episode: only what the IPTV source lists (already in play
/// order, see [parseEpisodes]).
TvEpisode? findNextEpisode(List<TvEpisode> episodes, String? current) {
  if (current == null) return null;
  final index = episodes.indexWhere((e) => e.id == current);
  return index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
}

/// Progress id of an episode (backend `episodeContentId`).
String episodeContentId(String seriesItemId, String episodeId) {
  final id =
      '${seriesItemId}_e${episodeId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}';
  return id.length > 128 ? id.substring(0, 128) : id;
}

/// Engine error → failure code: the provider's address could not be reached
/// (DNS, connection, HTTP error) or the media itself failed.
String playbackErrorCode(String message) =>
    RegExp(
      r'resolve hostname|failed to open|connection refused|timed out|'
      r'network is unreachable|http error|server returned',
      caseSensitive: false,
    ).hasMatch(message)
    ? 'stream-unreachable'
    : 'playback-failed';
