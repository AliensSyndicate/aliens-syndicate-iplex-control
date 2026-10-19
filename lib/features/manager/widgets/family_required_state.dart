import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/components.dart';

class FamilyRequiredState extends StatelessWidget {
  const FamilyRequiredState({super.key, this.onManage});
  final VoidCallback? onManage;
  @override
  Widget build(BuildContext context) => EmptyState(
    title: context.l.family,
    body: context.l.familyRequiredBody,
    action: AppButton(
      label: context.l.manageFamily,
      icon: AppIcons.users,
      onPressed: onManage ?? () => context.go('/users'),
    ),
  );
}
