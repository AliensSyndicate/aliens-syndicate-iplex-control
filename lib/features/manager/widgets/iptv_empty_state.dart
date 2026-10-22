import 'package:flutter/material.dart';

import '../../../core/design_system/components.dart';

class IptvEmptyState extends StatelessWidget {
  const IptvEmptyState({super.key, this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => EmptyState(
    title: context.l.emptySourcesTitle,
    body: context.l.emptySourcesDescription,
    action: onAdd == null
        ? null
        : AppButton.primary(
            label: context.l.addSource,
            icon: AppIcons.add,
            onPressed: onAdd,
          ),
  );
}
