import 'package:aliens_syndicate_iplex_control/core/domain/models.dart';
import 'package:aliens_syndicate_iplex_control/features/home/home_data.dart';

/// Answers `readCatalogManifest` / `readCatalogChunk` (one chunk per set) from
/// [items], as the backend splits them: adult items in `adult`, the others in
/// `live` / `vod` / `series` by kind. An item's `set` forces its set (e.g. an
/// adult item an older backend still sends with the regular ones). Null for
/// any other action.
Map<String, dynamic>? catalogSetsAnswer(
  String action,
  Map<String, dynamic> payload,
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>> categories = const [],
}) {
  if (action == 'readCatalogManifest') {
    return {
      'version': 'v',
      'sets': {
        for (final set in [
          'live',
          'live_categories',
          'vod',
          'vod_categories',
          'series',
          'series_categories',
          'adult',
          'adult_categories',
        ])
          set: {'chunks': 1},
      },
    };
  }
  if (action != 'readCatalogChunk') return null;
  final set = payload['set'] as String;
  String setOf(Map<String, dynamic> item) =>
      item['set'] as String? ??
      (isAdultEntry(Entry('${item['id']}', item))
          ? 'adult'
          : const {
              'channel': 'live',
              'movie': 'vod',
              'series': 'series',
            }[item['kind']]!);
  final kindOfCategories = const {
    'live_categories': 'channel',
    'vod_categories': 'movie',
    'series_categories': 'series',
  }[set];
  return {
    'records': set.endsWith('_categories')
        ? [
            for (final c in categories)
              if (c['kind'] == kindOfCategories) c,
          ]
        : [
            for (final item in items)
              if (setOf(item) == set) item,
          ],
  };
}
