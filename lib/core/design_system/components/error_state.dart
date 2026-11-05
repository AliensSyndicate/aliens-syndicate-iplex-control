import 'dart:async';

import 'package:flutter/material.dart';

import '../localized_context.dart';
import 'empty_state.dart';
import 'neumorphic_action_button.dart';

class ErrorState extends StatefulWidget {
  const ErrorState({super.key, required this.onRetry});
  final VoidCallback onRetry;

  /// How long the button spins before asking again: failures of an IPTV
  /// provider often come back at once, and the person must see the new try.
  static const retryFeedback = Duration(milliseconds: 2500);

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState> {
  Timer? retrying;

  @override
  void dispose() {
    retrying?.cancel();
    super.dispose();
  }

  void retry() {
    setState(() {
      retrying = Timer(ErrorState.retryFeedback, () {
        if (!mounted) return;
        setState(() => retrying = null);
        widget.onRetry();
      });
    });
  }

  @override
  Widget build(BuildContext context) => EmptyState(
    title: context.l.error,
    body: '',
    action: NeumorphicActionButton(
      label: context.l.retry,
      busy: retrying != null,
      onPressed: retrying == null ? retry : null,
    ),
  );
}
