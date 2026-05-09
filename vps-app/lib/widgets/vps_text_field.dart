// PublicNode VPS
// Copyright (C) 2026 mohammadhasanulislam
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import '../app/constants.dart';
import './vps_bounce.dart';

enum VpsValidationStatus { none, loading, valid, invalid }

class VpsTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final String? helperText;
  final Widget? prefixIcon;
  final bool obscureText;
  final bool isPassword;
  final VoidCallback? onSubmitted;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  // Validation fields
  final VpsValidationStatus validationStatus;
  final String? validationMessage;
  final String? guidanceText;
  final bool readOnly;

  const VpsTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.helperText,
    this.prefixIcon,
    this.obscureText = false,
    this.isPassword = false,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.suffixIcon,
    this.validationStatus = VpsValidationStatus.none,
    this.validationMessage,
    this.guidanceText,
    this.readOnly = false,
  });

  @override
  State<VpsTextField> createState() => _VpsTextFieldState();
}

class _VpsTextFieldState extends State<VpsTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText || widget.isPassword;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Color _getBorderColor() {
    switch (widget.validationStatus) {
      case VpsValidationStatus.valid:
        return SovColors.success.withValues(alpha: 0.6);
      case VpsValidationStatus.invalid:
        return SovColors.error.withValues(alpha: 0.6);
      case VpsValidationStatus.loading:
        return SovColors.accent.withValues(alpha: 0.6);
      case VpsValidationStatus.none:
        return SovColors.borderGlass;
    }
  }

  Widget? _getValidationSuffix() {
    switch (widget.validationStatus) {
      case VpsValidationStatus.loading:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: SovColors.accent,
          ),
        );
      case VpsValidationStatus.valid:
        return const Icon(
          Icons.check_circle_rounded,
          color: SovColors.success,
          size: 20,
        );
      case VpsValidationStatus.invalid:
        return const Icon(
          Icons.error_rounded,
          color: SovColors.error,
          size: 20,
        );
      case VpsValidationStatus.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInvalid = widget.validationStatus == VpsValidationStatus.invalid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          obscureText: _obscured,
          textInputAction: widget.textInputAction,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          onChanged: widget.onChanged,
          readOnly: widget.readOnly,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          keyboardType: widget.isPassword
              ? TextInputType.visiblePassword
              : TextInputType.text,
          style: const TextStyle(
            color: SovColors.textPrimary,
            fontSize: 14,
            fontFamily: SovFonts.ui,
          ),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: TextStyle(
              color: isInvalid ? SovColors.error : SovColors.textSecondary,
              fontSize: 13,
            ),
            hintText: widget.hintText,
            helperText:
                isInvalid ? widget.validationMessage : widget.helperText,
            helperStyle: TextStyle(
              color: isInvalid ? SovColors.error : SovColors.accent,
              fontSize: 10,
              fontWeight: isInvalid ? FontWeight.bold : FontWeight.normal,
              letterSpacing: 0.2,
            ),
            prefixIcon: widget.prefixIcon,
            prefixIconColor: isInvalid ? SovColors.error : SovColors.accent,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_getValidationSuffix() != null) ...[
                    _getValidationSuffix()!,
                    const SizedBox(width: 8),
                  ],
                  if (widget.isPassword)
                    VpsBounce(
                      onTap: () => setState(() => _obscured = !_obscured),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          _obscured
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: SovColors.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  if (widget.suffixIcon != null) widget.suffixIcon!,
                ],
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
              borderSide: BorderSide(color: _getBorderColor(), width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
              borderSide: BorderSide(
                color: isInvalid ? SovColors.error : SovColors.accent,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
              borderSide: const BorderSide(color: SovColors.error, width: 1.0),
            ),
          ),
        ),
        if (isInvalid && widget.guidanceText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              child: Row(
                children: [
                  const Icon(
                    Icons.tips_and_updates_rounded,
                    color: SovColors.warning,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.guidanceText!,
                      style: const TextStyle(
                        color: SovColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
