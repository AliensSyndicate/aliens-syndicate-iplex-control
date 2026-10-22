import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Network image with a disk cache and a downscaled decode.
///
/// - Memory: Flutter's [ImageCache] (enlarged by [configureImageCache]).
/// - Disk: the bytes of every image are kept for [maxAge], so a poster seen
///   once opens instantly next time (even offline) instead of downloading again.
/// - Decode: [decodeWidth] (physical pixels) decodes a poster at the size it is
///   drawn, which is much faster and lighter than the full-size artwork.
///
/// It is a [NetworkImage], so widgets and tests that read `url` keep working.
@immutable
class CachedNetworkImage extends ImageProvider<NetworkImage>
    implements NetworkImage {
  const CachedNetworkImage(this.url, {this.decodeWidth});

  @override
  final String url;
  @override
  double get scale => 1;
  @override
  Map<String, String>? get headers => null;
  @override
  WebHtmlElementStrategy get webHtmlElementStrategy =>
      WebHtmlElementStrategy.never;

  /// Physical pixel width to decode at (null = original size).
  final int? decodeWidth;

  static const maxAge = Duration(days: 14);

  /// Test hook: use this directory instead of the platform cache directory.
  @visibleForTesting
  static Directory? debugDirectory;
  static Future<Directory?>? _directory;

  static Future<Directory?> _cacheDirectory() {
    // Widget tests have no platform channels: memory cache only. (Checked
    // before the shared future so no test zone ever owns it.)
    if (debugDirectory == null &&
        (Platform.environment.containsKey('FLUTTER_TEST') ||
            WidgetsBinding.instance.runtimeType.toString().contains('Test'))) {
      return SynchronousFuture<Directory?>(null);
    }
    return _directory ??= () async {
      try {
        final base =
            debugDirectory ??
            await getTemporaryDirectory().timeout(const Duration(seconds: 3));
        return await Directory('${base.path}/iplex_images')
            .create(recursive: true);
      } catch (_) {
        return null;
      }
    }();
  }

  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    NetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url,
    informationCollector: () => [DiagnosticsProperty('Image url', url)],
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await readBytes();
    if (bytes.isEmpty) throw StateError('Empty image: $url');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(
      buffer,
      getTargetSize: decodeWidth == null
          ? null
          : (intrinsicWidth, intrinsicHeight) {
              // Never upscale; keep the aspect ratio.
              if (intrinsicWidth <= decodeWidth!) {
                return ui.TargetImageSize(
                  width: intrinsicWidth,
                  height: intrinsicHeight,
                );
              }
              return ui.TargetImageSize(width: decodeWidth);
            },
    );
  }

  @visibleForTesting
  Future<Uint8List> readBytes() async {
    final directory = await _cacheDirectory();
    File? file;
    if (directory != null) {
      file = File('${directory.path}/${sha1.convert(url.codeUnits)}');
      try {
        if (file.existsSync() &&
            DateTime.now().difference(file.lastModifiedSync()) < maxAge) {
          final cached = await file.readAsBytes();
          if (cached.isNotEmpty) return cached;
        }
      } catch (_) {
        // Unreadable entry: download again.
      }
    }
    final client = HttpClient()..autoUncompress = false;
    try {
      final request = await client.getUrl(Uri.base.resolve(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: Uri.parse(url),
        );
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (file != null && bytes.isNotEmpty) {
        // Write to a temp name first: a half-written file is never read.
        final temp = File('${file.path}.part');
        unawaited(
          temp
              .writeAsBytes(bytes, flush: true)
              .then((_) => temp.rename(file!.path))
              .then((_) {}, onError: (_) {}),
        );
      }
      return bytes;
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImage &&
      other.url == url &&
      other.decodeWidth == decodeWidth;

  @override
  int get hashCode => Object.hash(url, decodeWidth);

  @override
  String toString() => 'CachedNetworkImage("$url", decodeWidth: $decodeWidth)';
}

/// Larger in-memory image cache: the default (100 MB / 1000) evicts posters
/// while the user scrolls the Home rows.
void configureImageCache() {
  PaintingBinding.instance.imageCache
    ..maximumSize = 1500
    ..maximumSizeBytes = 300 << 20;
}
