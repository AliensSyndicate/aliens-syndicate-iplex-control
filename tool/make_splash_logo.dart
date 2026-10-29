// Generates the light splash logos (white letters for the dark splash
// background) from the black brand logos, keeping transparency.
// Run: dart run tool/make_splash_logo.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  for (final (from, to) in [
    ('assets/images/launcher.png', 'assets/images/splash_logo.png'),
    (
      'assets/images/splash_android12.png',
      'assets/images/splash_logo_android12.png',
    ),
  ]) {
    final source = img.decodePng(File(from).readAsBytesSync())!;
    final light = source.convert(numChannels: 4);
    for (final p in light) {
      p
        ..r = 255 - p.r
        ..g = 255 - p.g
        ..b = 255 - p.b;
    }
    File(to).writeAsBytesSync(img.encodePng(light));
    stdout.writeln('$from -> $to');
  }
}
