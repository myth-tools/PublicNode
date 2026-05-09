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

/// Glassmorphic card widget — the signature visual element of PublicNode Terminal.
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import '../app/constants.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blur;
  final bool hasTechnicalGrid;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SovSpacing.lg),
    this.borderRadius = SovSpacing.borderRadius,
    this.blur = SovSpacing.glassBlur,
    this.hasTechnicalGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: SovColors.surfaceGlass,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: SovColors.borderGlass, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (hasTechnicalGrid)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TechnicalGridPainter(),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _TechnicalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SovColors.accent.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;

    const spacing = 20.0;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
