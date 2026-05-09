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

/// PublicNode dark theme with glassmorphism accents.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';

ThemeData buildPublicNodeTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SovColors.background,
    colorScheme: const ColorScheme.dark(
      primary: SovColors.accent,
      secondary: SovColors.accentPurple,
      surface: SovColors.surface,
      error: SovColors.error,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: SovColors.textPrimary,
      displayColor: SovColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SovColors.surfaceGlass,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
        borderSide: const BorderSide(color: SovColors.borderGlass),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
        borderSide: const BorderSide(color: SovColors.borderGlass),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
        borderSide: const BorderSide(color: SovColors.accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: SovColors.textSecondary),
      hintStyle: const TextStyle(color: SovColors.textSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SovColors.accent,
        foregroundColor: SovColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SovSpacing.borderRadiusSm),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: SovSpacing.lg,
          vertical: SovSpacing.md,
        ),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  );
}
