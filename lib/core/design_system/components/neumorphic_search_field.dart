import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'app_icon.dart';
import 'neumorphic_text_field.dart';

/// Dedicated Neumorphic Search Field
class NeumorphicSearchField extends StatelessWidget {
  const NeumorphicSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => AppTextField(
    label: hintText,
    controller: controller,
    onChanged: onChanged,
    prefixIcon: const Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: AppIcon(AppIcons.search),
    ),
  );
}
