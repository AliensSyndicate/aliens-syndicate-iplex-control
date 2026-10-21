import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart' show Fake, WidgetTester;

/// Answers every `Image.network` request with a small solid PNG, so tests can see a
/// provider photo being drawn without any network access.
final Uint8List fakePhotoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGOIq+/HihiGlgQAgpVbAb3tsbcAAAAASUVORK5CYII=',
);

/// A URL containing `broken` answers 404 (Flutter keeps one shared client for all
/// network images, so the answer is chosen per request, not per override).
class FakeImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client();
}

class _Client extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(url.path.contains('broken') ? 404 : 200);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.status);
  final int status;
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response(status);
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Response extends Fake implements HttpClientResponse {
  _Response(this.status);
  final int status;
  @override
  int get statusCode => status;
  @override
  int get contentLength => fakePhotoBytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(fakePhotoBytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

/// Lets pending photo loads (resolved outside the fake clock) reach the tree.
Future<void> loadImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
