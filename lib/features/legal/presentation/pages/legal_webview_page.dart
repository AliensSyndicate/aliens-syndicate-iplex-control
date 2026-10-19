import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/design_system/components.dart';
import '../../data/services/legal_document_url_resolver.dart';
import '../../domain/enums/legal_document_type.dart';
import '../widgets/legal_document_error_state.dart';
import '../widgets/legal_document_loading_indicator.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri url, {LaunchMode? mode});

/// Reusable legal document viewer page embedding a secure, Dark-Industrial styled WebView.
class LegalWebViewPage extends StatefulWidget {
  const LegalWebViewPage({
    super.key,
    required this.type,
    this.resolver,
    this.controller,
    this.urlLauncher,
    this.timeoutDuration = const Duration(seconds: 20),
  });

  final LegalDocumentType type;
  final LegalDocumentUrlResolver? resolver;
  final WebViewController? controller;
  final ExternalUrlLauncher? urlLauncher;
  final Duration timeoutDuration;

  @override
  State<LegalWebViewPage> createState() => _LegalWebViewPageState();
}

class _LegalWebViewPageState extends State<LegalWebViewPage> {
  late final LegalDocumentUrlResolver _resolver;
  late final WebViewController _controller;
  Timer? _timeoutTimer;

  bool _isLoading = true;
  int _progress = 0;
  LegalErrorType? _errorType;
  String? _errorMessage;
  late Uri _resolvedUrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _resolver = widget.resolver ??
        LegalDocumentUrlResolver(environment: LegalEnvironment.current());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initAndLoad();
    }
  }

  void _initAndLoad() {
    final languageCode = Localizations.maybeLocaleOf(context)?.languageCode;
    _resolvedUrl = _resolver.resolve(widget.type, languageCode: languageCode);

    if (!_resolver.isAllowedLegalUrl(_resolvedUrl)) {
      setState(() {
        _isLoading = false;
        _errorType = LegalErrorType.security;
      });
      return;
    }

    if (widget.controller != null) {
      _controller = widget.controller!;
      _isLoading = false;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(AppColors.backgroundDeep)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
          onPageStarted: (url) {
            _startTimeoutWatchdog();
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorType = null;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (url) {
            _cancelTimeoutWatchdog();
            if (mounted && _errorType == null) {
              setState(() {
                _isLoading = false;
                _progress = 100;
              });
            }
          },
          onHttpError: (error) {
            _cancelTimeoutWatchdog();
            final statusCode = error.response?.statusCode ?? 0;
            if (statusCode >= 400 && mounted) {
              setState(() {
                _isLoading = false;
                _errorType = LegalErrorType.http;
                _errorMessage =
                    '${context.l.legalErrorGeneric} (HTTP $statusCode)';
              });
            }
          },
          onWebResourceError: (error) {
            _cancelTimeoutWatchdog();
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorType = _classifyError(error);
              });
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            if (_resolver.isAllowedLegalUrl(uri)) {
              return NavigationDecision.navigate;
            }

            if (_resolver.isLegitimateExternalLink(uri)) {
              final launcher = widget.urlLauncher ?? launchUrl;
              try {
                await launcher(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
            return NavigationDecision.prevent;
          },
        ),
      );

    _controller.loadRequest(_resolvedUrl);
  }

  void _startTimeoutWatchdog() {
    _cancelTimeoutWatchdog();
    _timeoutTimer = Timer(widget.timeoutDuration, () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _errorType = LegalErrorType.timeout;
        });
        _controller.loadRequest(Uri.parse('about:blank'));
      }
    });
  }

  void _cancelTimeoutWatchdog() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  LegalErrorType _classifyError(WebResourceError error) {
    final typeName = error.errorType?.toString().toLowerCase() ?? '';
    final desc = error.description.toLowerCase();

    if (typeName.contains('timeout') || desc.contains('timed out')) {
      return LegalErrorType.timeout;
    }
    if (typeName.contains('hostlookup') ||
        typeName.contains('connect') ||
        desc.contains('net::err_internet_disconnected') ||
        desc.contains('net::err_name_not_resolved') ||
        desc.contains('connection refused')) {
      return LegalErrorType.network;
    }
    if (typeName.contains('ssl') ||
        typeName.contains('cert') ||
        typeName.contains('secureconnectionfailed') ||
        desc.contains('ssl') ||
        desc.contains('certificate')) {
      return LegalErrorType.security;
    }
    return LegalErrorType.generic;
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _errorType = null;
      _errorMessage = null;
      _progress = 0;
    });
    _controller.loadRequest(_resolvedUrl);
  }

  Future<void> _handleBack() async {
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/login');
    }
  }

  String _documentTitle(BuildContext context) {
    switch (widget.type) {
      case LegalDocumentType.termsOfUse:
        return context.l.terms;
      case LegalDocumentType.privacyPolicy:
        return context.l.privacy;
    }
  }

  @override
  void dispose() {
    _cancelTimeoutWatchdog();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _documentTitle(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDeep,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar with tactile Back button and localized Title
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    CircularButton(
                      label: context.l.back,
                      icon: AppIcons.left,
                      size: AppDimensions.touch,
                      onPressed: _handleBack,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.headlineMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Progress bar during in-page loading
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress > 0 && _progress < 100
                      ? _progress / 100.0
                      : null,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accent,
                  ),
                  minHeight: 2,
                ),

              // Body content
              Expanded(
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_errorType != null) {
      return LegalDocumentErrorState(
        onRetry: _retry,
        errorType: _errorType!,
        customMessage: _errorMessage,
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading && _progress < 30)
          Container(
            color: AppColors.backgroundDeep,
            child: LegalDocumentLoadingIndicator(progress: _progress),
          ),
      ],
    );
  }
}
