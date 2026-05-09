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

/// Animated connection status indicator pill.
library;

import 'package:flutter/material.dart';
import '../app/constants.dart';
import '../models/connection.dart' as model;

class StatusIndicator extends StatefulWidget {
  final model.ConnectionState state;
  final String message;

  const StatusIndicator({
    super.key,
    required this.state,
    required this.message,
  });

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.state == model.ConnectionState.connecting ||
        widget.state == model.ConnectionState.handshake) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _dotColor {
    switch (widget.state) {
      case model.ConnectionState.disconnected:
        return SovColors.textSecondary;
      case model.ConnectionState.connecting:
      case model.ConnectionState.handshake:
        return SovColors.warning;
      case model.ConnectionState.ready:
        return SovColors.success;
      case model.ConnectionState.error:
        return SovColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SovSpacing.md,
            vertical: SovSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: SovColors.surfaceGlass,
            borderRadius: BorderRadius.circular(SovSpacing.xxl),
            border: Border.all(color: SovColors.borderGlass),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: _pulseAnimation.value,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _dotColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: SovSpacing.sm),
              Text(
                widget.message,
                style: const TextStyle(
                  color: SovColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
