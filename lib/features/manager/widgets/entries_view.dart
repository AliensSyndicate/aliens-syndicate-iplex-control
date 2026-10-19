import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/providers.dart';
import '../../../core/design_system/components.dart';
import '../../../core/domain/models.dart';

class EntriesView extends ConsumerWidget {
  const EntriesView({
    super.key,
    required this.collection,
    required this.builder,
    required this.empty,
  });
  final String collection;
  final Widget Function(List<Entry>) builder;
  final Widget empty;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(entriesProvider(collection))
      .when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        data: (items) => items.isEmpty ? empty : builder(items),
        error: (e, s) => ErrorState(
          onRetry: () => ref.invalidate(entriesProvider(collection)),
        ),
        loading: () => const AppLoadingSkeleton(),
      );
}
