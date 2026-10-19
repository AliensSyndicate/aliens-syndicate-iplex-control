import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import 'widgets/entries_view.dart';

class ProfileDataPage extends ConsumerWidget {
  const ProfileDataPage({
    super.key,
    required this.profileId,
    this.progress = false,
  });
  final String profileId;
  final bool progress;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l,
        collection =
            'profiles/$profileId/${progress ? 'watch_progress' : 'favorites'}';
    return Scaffold(
      body: PageTemplate(
        title: progress ? l.continueWatching : l.favorites,
        showBack: true,
        child: EntriesView(
          collection: collection,
          empty: Text(l.empty),
          builder: (items) => Column(
            children: items
                .map(
                  (e) => EntryTile(
                    title: e.name.isEmpty ? e.text('contentId') : e.name,
                    subtitle: progress
                        ? '${e.number('position')} / ${e.number('duration')}'
                        : l.unavailable,
                    icon: progress ? AppIcons.play : AppIcons.favorite,
                    onTap: progress
                        ? null
                        : () async {
                            if (!await confirmRemoval(context)) return;
                            try {
                              await ref.read(repositoryProvider).mutate(
                                'favorite',
                                {
                                  'profileId': profileId,
                                  'contentId': e.id,
                                  'remove': true,
                                },
                              );
                            } catch (error) {
                              if (context.mounted) showFailure(context, error);
                            }
                          },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
