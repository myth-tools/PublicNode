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

import 'dart:ui';
import 'package:flutter/material.dart';
import '../app/constants.dart';

/// Industrial-Grade Progress Overlay for long-running operations.
/// Features a blurred background, animated indicator, and descriptive status.
class VpsProgressOverlay extends StatelessWidget {
  final String status;
  final double? progress; // null for indeterminate

  const VpsProgressOverlay({
    super.key,
    required this.status,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Frosted Glass Backdrop
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),

          Center(
            child: Container(
              padding: const EdgeInsets.all(SovSpacing.xl),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: SovColors.surface,
                borderRadius: BorderRadius.circular(SovSpacing.borderRadius),
                border: Border.all(color: SovColors.borderGlass),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Branding Circle
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SovColors.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        value: progress,
                        color: SovColors.accent,
                        strokeWidth: 3,
                        backgroundColor: SovColors.borderGlass,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'PROCESSING',
                    style: TextStyle(
                      color: SovColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: SovColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  if (progress != null) ...[
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        color: SovColors.accent,
                        backgroundColor: SovColors.borderGlass,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress! * 100).toInt()}%',
                      style: const TextStyle(
                        color: SovColors.textSecondary,
                        fontSize: 12,
                        fontFamily: SovFonts.mono,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Text(
                    'PublicNode VPS Industrial Engine',
                    style: TextStyle(
                      color: SovColors.textSecondary,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
