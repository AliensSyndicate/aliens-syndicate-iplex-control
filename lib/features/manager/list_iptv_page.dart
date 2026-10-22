import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import 'widgets/entries_view.dart';
import 'widgets/iptv_source_card.dart';
import 'widgets/iptv_empty_state.dart';

class ListIptvPage extends ConsumerWidget {
  const ListIptvPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final admin = ref.watch(canManageIptvProvider);
    return PageTemplate(
      title: l.iptv,
      hasBottomNav: true,
      action: admin
          ? CircularButton(
              label: l.addSource,
              icon: AppIcons.add,
              size: AppDimensions.touch,
              onPressed: () => context.push('/iptv/add'),
            )
          : null,
      child: EntriesView(
        collection: 'sources',
        empty: IptvEmptyState(
          onAdd: admin ? () => context.push('/iptv/add') : null,
        ),
        builder: (items) => Column(
          children: items
              .map((e) => IptvSourceCard(key: ValueKey(e.id), entry: e))
              .toList(),
        ),
      ),
    );
  }
}
