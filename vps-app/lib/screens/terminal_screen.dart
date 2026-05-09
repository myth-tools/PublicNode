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

/// Terminal Screen — full-screen xterm terminal view with status bar
/// and mobile toolbar. This is the core "viewer" of the PublicNode VPS.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../app/constants.dart';
import '../services/ssh_service.dart';
import '../services/navigation_service.dart';
import 'package:provider/provider.dart';
import '../widgets/mobile_toolbar.dart';
import '../widgets/status_indicator.dart';
import '../widgets/vps_notification.dart';
import '../models/connection.dart' as model;

class TerminalScreen extends StatefulWidget {
  final SshService ssh;
  final String vpsName;
  final String vpsVersion;
  final bool embedded;

  const TerminalScreen({
    super.key,
    required this.ssh,
    required this.vpsName,
    required this.vpsVersion,
    this.embedded = false,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final TerminalController _terminalController;
  late final FocusNode _focusNode;
  bool _showToolbar = true;

  // Key used to get the real pixel size of the TerminalView on the first frame
  // so we can push the correct PTY dimensions to the server immediately.
  final GlobalKey _terminalKey = GlobalKey();

  Timer? _cursorBlinkTimer;
  bool _cursorVisible = true;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _terminalController = TerminalController();
    _focusNode = FocusNode();
    _checkPendingCommands();
    widget.ssh.addListener(_onSshStateChanged);

    _startCursorBlink();
  }

  void _startCursorBlink() {
    _cursorBlinkTimer?.cancel();
    // Custom native blinking implementation since xterm's internal blink can be buggy
    _cursorBlinkTimer =
        Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted) return;
      final terminal = widget.ssh.terminal;
      if (terminal != null) {
        setState(() {
          _cursorVisible = !_cursorVisible;
          terminal.setCursorVisibleMode(_cursorVisible);
        });
      }
    });
  }

  void _checkPendingCommands() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = context.read<NavigationService>();
      final cmd = nav.pendingTerminalCommand;
      if (cmd != null) {
        widget.ssh.send(cmd);
        nav.clearTerminalCommand();
      }
    });
  }

  void _onSshStateChanged() {
    if (mounted) setState(() {});

    if (widget.ssh.state == model.ConnectionState.disconnected) {
      if (mounted && !widget.embedded) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _cursorBlinkTimer?.cancel();
    _focusNode.dispose();
    widget.ssh.removeListener(_onSshStateChanged);
    _terminalController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _disconnect() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SovColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SovSpacing.borderRadius),
        ),
        title: const Text(
          'Disconnect?',
          style: TextStyle(color: SovColors.textPrimary),
        ),
        content: const Text(
          'This will close your terminal session.',
          style: TextStyle(color: SovColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SovColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              widget.ssh.disconnect();
            },
            child: const Text(
              'Disconnect',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    Terminal terminal,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: SovColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.copy, size: 18, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Copy', style: TextStyle(color: SovColors.textPrimary)),
            ],
          ),
          onTap: () {
            // V6: Smart Grid Copy (Trims trailing whitespace from fixed-width terminal lines)
            final cursorLine = widget
                .ssh.terminal!.buffer.lines[widget.ssh.terminal!.buffer.cursorY]
                .toString();
            if (cursorLine.isNotEmpty) {
              final smartText = cursorLine.trimRight();
              Clipboard.setData(ClipboardData(text: smartText));
              HapticFeedback.lightImpact();
              if (mounted) {
                VpsNotification.success(context, 'Copied');
              }
            }
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.content_paste, size: 18, color: SovColors.accent),
              SizedBox(width: 12),
              Text('Paste', style: TextStyle(color: SovColors.textPrimary)),
            ],
          ),
          onTap: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) {
              widget.ssh.send(data!.text!);
              HapticFeedback.lightImpact();
            }
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.terminal_outlined, size: 18, color: SovColors.accent),
              SizedBox(width: 12),
              Text(
                'Paste and Run',
                style: TextStyle(color: SovColors.textPrimary),
              ),
            ],
          ),
          onTap: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) {
              widget.ssh.send('${data!.text!}\n');
              HapticFeedback.mediumImpact();
            }
          },
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.select_all, size: 18, color: SovColors.textSecondary),
              SizedBox(width: 12),
              Text(
                'Copy All Text',
                style: TextStyle(color: SovColors.textPrimary),
              ),
            ],
          ),
          onTap: () {
            // V6: Deep Buffer Extraction
            final terminal = widget.ssh.terminal;
            if (terminal == null) return;
            final List<String> bufferLines = [];
            for (var i = 0; i < terminal.buffer.lines.length; i++) {
              bufferLines.add(terminal.buffer.lines[i].toString());
            }
            final fullText = bufferLines.join('\n');
            Clipboard.setData(ClipboardData(text: fullText));
            if (mounted) {
              VpsNotification.success(context, 'All text copied');
            }
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(
                Icons.delete_sweep_outlined,
                size: 18,
                color: SovColors.error,
              ),
              SizedBox(width: 12),
              Text(
                'Clear Screen',
                style: TextStyle(color: SovColors.textPrimary),
              ),
            ],
          ),
          onTap: () {
            widget.ssh.clearTerminal();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final terminal = widget.ssh.terminal;

    if (terminal == null) {
      return const Scaffold(
        backgroundColor: SovColors.terminalBg,
        body: Center(child: CircularProgressIndicator(color: SovColors.accent)),
      );
    }

    return Scaffold(
      backgroundColor: SovColors.terminalBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // --- Status Bar ---
            if (!widget.embedded) _buildStatusBar(),

            // --- Terminal View ---
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Industrial-Grade Precision Resizing
                  final fontSize = _isMobile
                      ? SovFonts.terminalFontMobile
                      : SovFonts.terminalFontDesktop;

                  // Use TextPainter to get PRECISE character dimensions
                  final textPainter = TextPainter(
                    text: TextSpan(
                      text: 'W', // Monospaced 'W' for measurement
                      style: TextStyle(
                        fontSize: fontSize,
                        fontFamily: SovFonts.mono,
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                  )..layout();

                  final charWidth = textPainter.width;
                  final charHeight = textPainter.height;

                  final cols = (constraints.maxWidth / charWidth).floor();
                  final rows = (constraints.maxHeight / charHeight).floor();

                  // Debounced Resize Logic
                  if (terminal.viewWidth != cols ||
                      terminal.viewHeight != rows) {
                    terminal.resize(cols, rows);
                  }

                  return GestureDetector(
                    onSecondaryTapDown: (details) {
                      HapticFeedback.mediumImpact();
                      _showContextMenu(
                        context,
                        details.globalPosition,
                        terminal,
                      );
                    },
                    onLongPressStart: (details) {
                      HapticFeedback.mediumImpact();
                      _showContextMenu(
                        context,
                        details.globalPosition,
                        terminal,
                      );
                    },
                    child: TerminalView(
                      key: _terminalKey,
                      terminal,
                      controller: _terminalController,
                      focusNode: _focusNode,
                      cursorType: TerminalCursorType.block,
                      autofocus: true,
                      backgroundOpacity: 0, // Solid background for clarity
                      theme: const TerminalTheme(
                        cursor: SovColors.terminalCursor,
                        selection: Color(0x6000D4FF),
                        foreground: SovColors.terminalFg,
                        background: SovColors.terminalBg,
                        black: Color(0xFF000000),
                        red: Color(0xFFFF5555),
                        green: Color(0xFF50FA7B),
                        yellow: Color(0xFFF1FA8C),
                        blue: Color(0xFFBD93F9),
                        magenta: Color(0xFFFF79C6),
                        cyan: Color(0xFF8BE9FD),
                        white: Color(0xFFF8F8F2),
                        brightBlack: Color(0xFF6272A4),
                        brightRed: Color(0xFFFF6E6E),
                        brightGreen: Color(0xFF69FF94),
                        brightYellow: Color(0xFFFFFFA5),
                        brightBlue: Color(0xFFD6ACFF),
                        brightMagenta: Color(0xFFFF92DF),
                        brightCyan: Color(0xFFA4FFFF),
                        brightWhite: Color(0xFFFFFFFF),
                        searchHitBackground: Color(0x80FFD740),
                        searchHitBackgroundCurrent: Color(0xB3FFD740),
                        searchHitForeground: Color(0xFF000000),
                      ),
                      textStyle: TerminalStyle(
                        fontSize: _isMobile
                            ? SovFonts.terminalFontMobile
                            : SovFonts.terminalFontDesktop,
                        fontFamily: SovFonts.mono,
                      ),
                    ),
                  );
                },
              ),
            ),

            // --- Mobile Toolbar ---
            if (_isMobile && _showToolbar)
              MobileToolbar(
                terminal: terminal,
                controller: _terminalController,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SovSpacing.md,
        vertical: SovSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: SovColors.surface,
        border: Border(bottom: BorderSide(color: SovColors.borderGlass)),
      ),
      child: Row(
        children: [
          // VPS identity
          Text(
            ' ${widget.vpsName}',
            style: const TextStyle(
              color: SovColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: SovSpacing.sm),
          Text(
            'v${widget.vpsVersion}',
            style: const TextStyle(
              color: SovColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const Spacer(),

          // Connection status
          StatusIndicator(
            state: widget.ssh.state,
            message: widget.ssh.statusMessage,
          ),

          // Mobile toolbar toggle
          if (_isMobile) ...[
            const SizedBox(width: SovSpacing.sm),
            GestureDetector(
              onTap: () => setState(() => _showToolbar = !_showToolbar),
              child: Icon(
                _showToolbar ? Icons.keyboard_hide : Icons.keyboard,
                color: SovColors.textSecondary,
                size: 20,
              ),
            ),
          ],

          // Disconnect button
          const SizedBox(width: SovSpacing.sm),
          GestureDetector(
            onTap: _disconnect,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: SovColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.power_settings_new,
                color: SovColors.error,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
