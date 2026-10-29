import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Resolves a host name to an address.
typedef HostResolver = Future<InternetAddress> Function(String host);

/// Loopback proxy for the phone player. Many networks (ISP DNS filters) do not
/// resolve IPTV provider hosts that public resolvers do, so the media engine
/// asks this proxy instead of the provider:
///
/// - each host is resolved by the system first and, when that fails, by
///   DNS over HTTPS (Google, then Cloudflare);
/// - redirects are followed here;
/// - playlists (HLS and the providers' plain-text lists) are rewritten so every
///   address inside them also goes through the proxy;
/// - media is streamed through unchanged (Range requests pass through, so VOD
///   seeking keeps working).
///
/// It listens on 127.0.0.1 only, behind a random token per player, and keeps
/// nothing: stream addresses (which may carry IPTV credentials) never leave
/// the device.
class StreamProxy {
  StreamProxy._(this._server, this._token, HostResolver? resolve)
    : _resolveOverride = resolve {
    _client
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = _connect;
    _server.listen(_handle);
  }

  /// Starts a proxy on a free loopback port. [resolve] replaces the system /
  /// DNS-over-HTTPS resolution (tests).
  static Future<StreamProxy> start({HostResolver? resolve}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return StreamProxy._(server, token, resolve);
  }

  final HttpServer _server;
  final String _token;
  final HostResolver? _resolveOverride;
  final _client = HttpClient();
  final _doh = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  final _addresses = <String, InternetAddress>{};

  /// Largest playlist read into memory.
  static const _maxPlaylistBytes = 4 * 1024 * 1024;

  /// Address the media engine opens for [target] (http/https only; anything
  /// else is returned unchanged).
  Uri wrap(Uri target) => target.isScheme('http') || target.isScheme('https')
      ? Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: _server.port,
          path: '/$_token',
          queryParameters: {'u': target.toString()},
        )
      : target;

  Future<void> close() async {
    _client.close(force: true);
    _doh.close(force: true);
    await _server.close(force: true);
  }

  Future<InternetAddress> _resolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    final cached = _addresses[host];
    if (cached != null) return cached;
    final override = _resolveOverride;
    final address = override != null
        ? await override(host)
        : await _systemOrDoh(host);
    return _addresses[host] = address;
  }

  Future<InternetAddress> _systemOrDoh(String host) async {
    try {
      final found = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      if (found.isNotEmpty) return found.first;
    } catch (_) {
      // Not resolved here (filtered or unknown): public resolvers below.
    }
    for (final endpoint in [
      Uri.https('dns.google', '/resolve', {'name': host, 'type': 'A'}),
      Uri.https('cloudflare-dns.com', '/dns-query', {
        'name': host,
        'type': 'A',
      }),
    ]) {
      try {
        final request = await _doh.getUrl(endpoint);
        request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        final body = jsonDecode(await utf8.decodeStream(response));
        for (final answer in (body['Answer'] as List? ?? const [])) {
          if (answer is Map && answer['type'] == 1) {
            final ip = InternetAddress.tryParse('${answer['data']}');
            if (ip != null) return ip;
          }
        }
      } catch (_) {
        // Next resolver.
      }
    }
    throw SocketException('host not resolved', osError: null);
  }

  Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final address = await _resolve(uri.host);
    final port = uri.hasPort ? uri.port : (uri.isScheme('https') ? 443 : 80);
    if (!uri.isScheme('https')) return Socket.startConnect(address, port);
    // TLS still verifies the certificate against the real host name (SNI).
    return ConnectionTask.fromSocket(
      Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 15),
      ).then((socket) => SecureSocket.secure(socket, host: uri.host)),
      () {},
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final target = Uri.tryParse(request.uri.queryParameters['u'] ?? '');
    if (segments.length != 1 ||
        segments.first != _token ||
        target == null ||
        !(target.isScheme('http') || target.isScheme('https'))) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    StreamIterator<List<int>>? body;
    try {
      final upstream = await _client.openUrl(
        request.method == 'HEAD' ? 'HEAD' : 'GET',
        target,
      );
      upstream
        ..followRedirects = true
        ..maxRedirects = 5;
      for (final name in const ['range', 'user-agent', 'accept']) {
        final value = request.headers.value(name);
        if (value != null) upstream.headers.set(name, value);
      }
      final answer = await upstream.close();
      var base = target;
      for (final hop in answer.redirects) {
        base = base.resolveUri(hop.location);
      }
      body = StreamIterator(answer);
      final first = await body.moveNext() ? body.current : const <int>[];
      final type = answer.headers.contentType?.mimeType ?? '';
      if (_isPlaylist(type, base, first)) {
        final bytes = BytesBuilder(copy: false)..add(first);
        while (await body.moveNext()) {
          bytes.add(body.current);
          if (bytes.length > _maxPlaylistBytes) break;
        }
        final text = _rewrite(
          utf8.decode(bytes.takeBytes(), allowMalformed: true),
          base,
        );
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          )
          ..write(text);
        await response.close();
        return;
      }
      response.statusCode = answer.statusCode;
      for (final name in const [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
      ]) {
        final value = answer.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      response.add(first);
      final rest = body;
      await response.addStream(() async* {
        while (await rest.moveNext()) {
          yield rest.current;
        }
      }());
      await response.close();
    } catch (_) {
      // Upstream failure or the engine closed the connection.
      await body?.cancel();
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        // Headers already sent.
      }
      await response.close().catchError((Object _) {});
    }
  }

  /// HLS by type or name, or a body that reads as a list of addresses.
  static bool _isPlaylist(String type, Uri base, List<int> first) {
    if (type.contains('mpegurl') ||
        RegExp(r'\.m3u8?$', caseSensitive: false).hasMatch(base.path)) {
      return true;
    }
    final head = latin1
        .decode(first.take(512).toList(), allowInvalid: true)
        .trimLeft();
    return head.startsWith('#EXTM3U') ||
        RegExp(r'^https?://', caseSensitive: false).hasMatch(head);
  }

  /// Every address in a playlist (entries and URI="…" attributes) through the
  /// proxy, made absolute against the list's final address.
  String _rewrite(String playlist, Uri base) {
    String through(String raw) {
      final target = Uri.tryParse(raw.trim());
      return target == null ? raw : wrap(base.resolveUri(target)).toString();
    }

    return playlist
        .split('\n')
        .map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return line;
          if (trimmed.startsWith('#')) {
            return line.replaceAllMapped(
              RegExp(r'URI="([^"]+)"'),
              (m) => 'URI="${through(m[1]!)}"',
            );
          }
          return through(trimmed);
        })
        .join('\n');
  }
}
