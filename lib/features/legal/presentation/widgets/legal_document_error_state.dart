import 'package:flutter/material.dart';

import '../../../../core/design_system/components.dart';

enum LegalErrorType {
  network,
  timeout,
  http,
  security,
  generic,
}

/// Error state for Legal WebView failures with retry capability.
class LegalDocumentErrorState extends StatelessWidget {
  const LegalDocumentErrorState({
    super.key,
    required this.onRetry,
    this.errorType = LegalErrorType.generic,
    this.customMessage,
  });

  final VoidCallback onRetry;
  final LegalErrorType errorType;
  final String? customMessage;

  String _resolveMessage(BuildContext context) {
    if (customMessage != null && customMessage!.isNotEmpty) {
      return customMessage!;
    }
    switch (errorType) {
      case LegalErrorType.network:
        return context.l.legalErrorNetwork;
      case LegalErrorType.timeout:
        return context.l.requestTimeout;
      case LegalErrorType.security:
        return context.l.legalErrorBlocked;
      case LegalErrorType.http:
      case LegalErrorType.generic:
        return context.l.legalErrorGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: EmptyState(
          icon: AppIcons.alert,
          title: context.l.error,
          body: _resolveMessage(context),
          action: NeumorphicActionButton(
            label: context.l.retry,
            onPressed: onRetry,
            icon: AppIcons.refresh,
          ),
        ),
      ),
    );
  }
}
