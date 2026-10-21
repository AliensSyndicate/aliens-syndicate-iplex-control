import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import 'app_icon.dart';
import 'app_input_frame.dart';

/// Dedicated Neumorphic Search Field with vertically centered text and icon.
class NeumorphicSearchField extends StatefulWidget {
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
  State<NeumorphicSearchField> createState() => _NeumorphicSearchFieldState();
}

class _NeumorphicSearchFieldState extends State<NeumorphicSearchField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppInputFrame(
      label: '',
      height: AppDimensions.touch,
      focusNode: _focusNode,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const AppIcon(
            AppIcons.search,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextFormField(
              controller: widget.controller,
              focusNode: _focusNode,
              maxLines: 1,
              textAlignVertical: TextAlignVertical.center,
              cursorColor: Colors.white,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
