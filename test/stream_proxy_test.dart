import 'dart:convert';
import 'dart:io';

import 'package:aliens_syndicate_iplex_control/features/player/stream_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Provider on loopback: a plain-text list pointing at a host the system does
/// not know (blocked.test), an HLS list with relative and URI="…" entries,
/// and media that honours Range.
final mediaHosts = <String>[];

Future<HttpServer> _provider() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  server.listen((request) async {
    final response = request.response;
    switch (request.uri.path) {
      case '/play/list':
        response.headers.contentType = ContentType.text;
        response.write('http://blocked.test:$port/media.ts\n');
      case '/redirect':
        response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '/hls/index.m3u8');
      case '/hls/index.m3u8':
        response.headers.set('content-type', 'application/x-mpegURL');
        response.write(
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
          '#EXTINF:4,\nseg1.ts\n#EXTINF:4,\nhttp://blocked.test:$port/seg2.ts\n',
        );
      case '/media.ts':
        // The Host header names the original host, not the address used.
        mediaHosts.add(request.headers.host ?? '');
        final range = request.headers.value('range');
        if (range == 'bytes=2-') {
          response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('content-range', 'bytes 2-5/6');
          response.add([2, 3, 4, 5]);
        } else {
          response.headers.contentType = ContentType.binary;
          response.add([0, 1, 2, 3, 4, 5]);
        }
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  });
  return server;
}

void main() {
  late HttpServer provider;
  late StreamProxy proxy;
  final resolved = <String>[];
  final client = HttpClient();

  setUp(() async {
    provider = await _provider();
    resolved.clear();
    proxy = await StreamProxy.start(
      resolve: (host) async {
        resolved.add(host);
        if (host == 'blocked.test' || host == 'provider.test') {
          return InternetAddress.loopbackIPv4;
        }
        throw const SocketException('unknown');
      },
    );
  });
  tearDown(() async {
    await proxy.close();
    await provider.close(force: true);
  });
  tearDownAll(() => client.close(force: true));

  Future<HttpClientResponse> get(Uri uri, {String? range}) async {
    final request = await client.getUrl(uri);
    if (range != null) request.headers.set('range', range);
    return request.close();
  }

  String origin(String host) => 'http://$host:${provider.port}';

  test('plain-text provider list: its entries go through the proxy and the '
      'blocked host plays', () async {
    final list = await get(
      proxy.wrap(Uri.parse('${origin('provider.test')}/play/list')),
    );
    final lines = (await utf8.decodeStream(list)).trim().split('\n');
    final entry = Uri.parse(lines.single);
    expect(entry.host, '127.0.0.1');
    expect(entry.queryParameters['u'], '${origin('blocked.test')}/media.ts');

    final media = await get(entry);
    expect(media.statusCode, 200);
    expect(mediaHosts.last, 'blocked.test');
    expect(await media.expand((b) => b).toList(), [0, 1, 2, 3, 4, 5]);
    expect(resolved, containsAll(['provider.test', 'blocked.test']));

    // Range passes through (VOD seeking).
    final part = await get(entry, range: 'bytes=2-');
    expect(part.statusCode, 206);
    expect(part.headers.value('content-range'), 'bytes 2-5/6');
    expect(await part.expand((b) => b).toList(), [2, 3, 4, 5]);
  });

  test('HLS after a redirect: relative entries and URI attributes are made '
      'absolute against the final address and proxied', () async {
    final hls = await get(
      proxy.wrap(Uri.parse('${origin('provider.test')}/redirect')),
    );
    final text = await utf8.decodeStream(hls);
    final targets = [
      for (final m in RegExp(r'u=([^"\s]+)').allMatches(text))
        Uri.decodeQueryComponent(m[1]!),
    ];
    expect(targets, [
      '${origin('provider.test')}/hls/key.bin',
      '${origin('provider.test')}/hls/seg1.ts',
      '${origin('blocked.test')}/seg2.ts',
    ]);
    expect(text, startsWith('#EXTM3U'));
  });

  test(
    'only the player: wrong token or non-http targets are refused',
    () async {
      final good = proxy.wrap(Uri.parse('${origin('provider.test')}/media.ts'));
      final wrongToken = good.replace(path: '/nope');
      expect((await get(wrongToken)).statusCode, 404);
      final file = good.replace(queryParameters: {'u': 'file:///etc/hosts'});
      expect((await get(file)).statusCode, 404);
      expect(proxy.wrap(Uri.parse('rtmp://x/y')), Uri.parse('rtmp://x/y'));
    },
  );
}
