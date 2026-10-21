import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_input_frame.dart';
import '../tokens.dart';

/// Tactile Recessed Input Field with Physical Inset Depth, fixed top label and 56px height
class NeumorphicTextField extends StatefulWidget {
  const NeumorphicTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.secret = false,
    this.onChanged,
    this.validator,
    this.keyboardType,
    this.prefixIcon,
    this.focusNode,
    this.height = AppDimensions.input,
    this.bottomSpacing = AppSpacing.md,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool secret;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final FocusNode? focusNode;
  final double height;
  final double bottomSpacing;

  @override
  State<NeumorphicTextField> createState() => _NeumorphicTextFieldState();
}

class _NeumorphicTextFieldState extends State<NeumorphicTextField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  FocusNode? _internalFocusNode;
  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  void _refreshValidation() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSpacing),
      child: AppInputFrame(
        label: widget.label,
        height: widget.height,
        focusNode: _effectiveFocusNode,
        errorText: _fieldKey.currentState?.errorText,
        padding: EdgeInsets.only(
          left: widget.prefixIcon == null ? AppSpacing.md : AppSpacing.xs,
          right: AppSpacing.md,
        ),
        child: TextFormField(
          key: _fieldKey,
          controller: widget.controller,
          focusNode: _effectiveFocusNode,
          obscureText: widget.secret,
          enableSuggestions: !widget.secret,
          autocorrect: !widget.secret,
          keyboardType: widget.keyboardType,
          onChanged: (value) {
            final field = _fieldKey.currentState;
            // TextFormField also calls onChanged on reset. Keep its form value
            // aligned with the controller when a rebuilt field is reset.
            if (field?.value != value) field?.didChange(value);
            if (field?.hasError ?? false) {
              field!.validate();
            } else {
              _refreshValidation();
            }
            widget.onChanged?.call(value);
          },
          validator: (value) {
            final error = widget.validator?.call(value);
            _refreshValidation();
            return error;
          },
          maxLines: 1,
          textAlignVertical: TextAlignVertical.center,
          errorBuilder: (_, _) => const SizedBox.shrink(),
          maxLength: widget.secret ? 512 : 2048,
          cursorColor: Colors.white,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            height: 1.25,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              height: 1.25,
            ),
            counterText: '',
            prefixIcon: widget.prefixIcon,
            prefixIconConstraints: BoxConstraints(
              minWidth: 40,
              minHeight: widget.height,
              maxWidth: 44,
              maxHeight: widget.height,
            ),
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

/// Backward compatibility alias for NeumorphicTextField
typedef AppTextField = NeumorphicTextField;
