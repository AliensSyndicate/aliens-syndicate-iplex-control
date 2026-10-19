import 'package:flutter/material.dart';

import '../localized_context.dart';
import 'empty_state.dart';
import 'neumorphic_action_button.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    title: context.l.error,
    body: '',
    action: NeumorphicActionButton(label: context.l.retry, onPressed: onRetry),
  );
}
