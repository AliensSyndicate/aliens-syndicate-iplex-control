import 'dart:io';

import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_network_image.dart';

void main() {
  test(
    'an image is downloaded once and then read from the disk cache',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var hits = 0;
      server.listen((request) {
        hits++;
        request.response
          ..add(fakePhotoBytes)
          ..close();
      });
      final dir = await Directory.systemTemp.createTemp('iplex_img_test');
      CachedNetworkImage.debugDirectory = dir;
      addTearDown(() async {
        CachedNetworkImage.debugDirectory = null;
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final url = 'http://127.0.0.1:${server.port}/poster.png';
      final first = await CachedNetworkImage(url).readBytes();
      expect(first, fakePhotoBytes);
      // The cache file is written in the background.
      for (var i = 0; i < 20; i++) {
        if (dir
            .listSync(recursive: true)
            .any((f) => !f.path.endsWith('.part') && f is File)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final second = await CachedNetworkImage(url).readBytes();
      expect(second, fakePhotoBytes);
      expect(hits, 1);
    },
  );

  test('providers with the same url and size are equal (one memory entry)', () {
    expect(
      CachedNetworkImage('https://a/b.png', decodeWidth: 300),
      CachedNetworkImage('https://a/b.png', decodeWidth: 300),
    );
    expect(
      CachedNetworkImage('https://a/b.png', decodeWidth: 300) ==
          CachedNetworkImage('https://a/b.png', decodeWidth: 600),
      isFalse,
    );
  });
}
