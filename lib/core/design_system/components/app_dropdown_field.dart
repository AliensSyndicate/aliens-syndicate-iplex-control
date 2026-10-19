import 'package:flutter/material.dart';

import 'app_input_frame.dart';
import '../icons.dart';
import '../tokens.dart';
import 'app_icon.dart';

class AppDropdownField<T> extends StatefulWidget {
  const AppDropdownField({
    super.key,
    required this.initialValue,
    required this.items,
    required this.label,
    this.onChanged,
    this.focusNode,
  });
  final T initialValue;
  final List<DropdownMenuItem<T>> items;
  final String label;
  final ValueChanged<T?>? onChanged;
  final FocusNode? focusNode;
  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  FocusNode? _internalFocusNode;
  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppInputFrame(
    label: widget.label,
    focusNode: _effectiveFocusNode,
    child: DropdownButtonFormField<T>(
      focusNode: _effectiveFocusNode,
      initialValue: widget.initialValue,
      items: widget.items,
      onChanged: widget.onChanged,
      isExpanded: true,
      icon: const AppIcon(AppIcons.down, size: AppDimensions.iconSmall),
      dropdownColor: AppColors.backgroundPrimary,
      decoration: const InputDecoration(
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    ),
  );
}
