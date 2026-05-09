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

/// On-screen special key toolbar for mobile devices.
/// Provides frosted-glass buttons for Ctrl, Alt, Tab, Esc, and arrow keys
/// that are essential for terminal use but absent on virtual keyboards.
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../app/constants.dart';

class MobileToolbar extends StatefulWidget {
  final Terminal terminal;
  final TerminalController controller;

  const MobileToolbar({
    super.key,
    required this.terminal,
    required this.controller,
  });

  @override
  State<MobileToolbar> createState() => _MobileToolbarState();
}

class _MobileToolbarState extends State<MobileToolbar> {
  bool _ctrlActive = false;
  bool _altActive = false;

  void _sendKey(String seq) {
    String prefix = '';
    if (_ctrlActive) {
      // For ctrl+key, send the control character
      if (seq.length == 1) {
        final code = seq.codeUnitAt(0);
        if (code >= 97 && code <= 122) {
          // a-z -> ctrl code
          widget.terminal.textInput(String.fromCharCode(code - 96));
          setState(() => _ctrlActive = false);
          return;
        }
      }
      prefix = '\x1b'; // fallback ESC prefix for unknown combos
    }
    if (_altActive) {
      prefix = '\x1b';
      setState(() => _altActive = false);
    }
    widget.terminal.textInput('$prefix$seq');
  }

  void _sendEscape(String seq) {
    widget.terminal.textInput(seq);
  }

  Widget _buildKey(
    String label, {
    VoidCallback? onTap,
    bool isActive = false,
    double width = 42,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive
              ? SovColors.accent.withValues(alpha: 0.3)
              : SovColors.surfaceGlass,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? SovColors.accent : SovColors.borderGlass,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? SovColors.accent : SovColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SovSpacing.sm,
            vertical: SovSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: SovColors.surfaceGlass,
            border: Border(top: BorderSide(color: SovColors.borderGlass)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildKey('ESC', onTap: () => _sendEscape('\x1b')),
                  _buildKey('TAB', onTap: () => _sendEscape('\t')),
                  _buildKey(
                    'CTRL',
                    onTap: () => setState(() => _ctrlActive = !_ctrlActive),
                    isActive: _ctrlActive,
                  ),
                  _buildKey(
                    'ALT',
                    onTap: () => setState(() => _altActive = !_altActive),
                    isActive: _altActive,
                  ),
                  const SizedBox(width: 8),
                  // Arrow keys
                  _buildKey('←', onTap: () => _sendEscape('\x1b[D'), width: 34),
                  _buildKey('↑', onTap: () => _sendEscape('\x1b[A'), width: 34),
                  _buildKey('↓', onTap: () => _sendEscape('\x1b[B'), width: 34),
                  _buildKey('→', onTap: () => _sendEscape('\x1b[C'), width: 34),
                  const SizedBox(width: 8),
                  _buildKey('|', onTap: () => _sendKey('|'), width: 30),
                  _buildKey('/', onTap: () => _sendKey('/'), width: 30),
                  _buildKey('-', onTap: () => _sendKey('-'), width: 30),
                  _buildKey('~', onTap: () => _sendKey('~'), width: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
