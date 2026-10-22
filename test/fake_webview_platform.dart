import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  FakePlatformWebViewController? lastCreatedController;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakePlatformWebViewController(params);
    lastCreatedController = controller;
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakePlatformWebViewWidget(params);
  }
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params) : super.implementation();

  Uri? loadedUri;
  JavaScriptMode? javaScriptMode;
  Color? backgroundColor;
  FakePlatformNavigationDelegate? delegate;
  int loadCount = 0;
  bool simulateFailure = false;
  WebResourceError? errorToSimulate;
  HttpResponseError? httpErrorToSimulate;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    javaScriptMode = mode;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    backgroundColor = color;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as FakePlatformNavigationDelegate?;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loadCount++;
    loadedUri = params.uri;
    delegate?.onPageStarted?.call(params.uri.toString());
    if (simulateFailure) {
      if (errorToSimulate != null) {
        delegate?.onWebResourceError?.call(errorToSimulate!);
      }
      if (httpErrorToSimulate != null) {
        delegate?.onHttpError?.call(httpErrorToSimulate!);
      }
    } else {
      delegate?.onProgress?.call(100);
      delegate?.onPageFinished?.call(params.uri.toString());
    }
  }

  @override
  Future<bool> canGoBack() async => false;
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;
  HttpResponseErrorCallback? onHttpError;
  WebResourceErrorCallback? onWebResourceError;
  NavigationRequestCallback? onNavigationRequest;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    this.onProgress = onProgress;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    this.onHttpError = onHttpError;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
