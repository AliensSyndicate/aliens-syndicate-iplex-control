import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';

/// A linked TV that reports what it plays right now (as `reportPlayback`
/// writes it on the device document).
Entry tvPlaying({
  required String itemId,
  required String title,
  String kind = 'movie',
  String? episodeId,
  num? position,
  num? duration,
  String state = 'playing',
  int? updatedAt,
}) => Entry('tv1', {
  'name': 'Sala',
  'status': 'linked',
  'nowPlaying': {
    'itemId': itemId,
    'sourceId': 's',
    'title': title,
    'kind': kind,
    'episodeId': ?episodeId,
    'state': state,
    'updatedAt': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    'positionSec': ?position,
    'durationSec': ?duration,
  },
});
