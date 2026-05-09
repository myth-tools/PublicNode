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

/// Design constants for the PublicNode Terminal app.
/// All values are derived from the master vps-config.yaml at runtime.
library;

import 'package:flutter/material.dart';

// --- PublicNode Color Palette ---
class SovColors {
  SovColors._();

  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF12121A);
  static const Color surfaceGlass = Color(0x0DFFFFFF); // 5% white
  static const Color borderGlass = Color(0x1AFFFFFF); // 10% white
  static const Color accent = Color(0xFF00D4FF); // Electric Cyan
  static const Color accentPurple = Color(0xFF7B2FBE);
  static const Color success = Color(0xFF00E676);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFD740);
  static const Color textPrimary = Color(0xFFE0E0E0);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color terminalBg = Color(0xFF000000);
  static const Color terminalFg = Color(0xFFE0E0E0);
  static const Color terminalCursor = Color(0xFF00D4FF);
}

// --- Spacing & Sizing ---
class SovSpacing {
  SovSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  static const double borderRadius = 16.0;
  static const double borderRadiusMd = 12.0;
  static const double borderRadiusSm = 8.0;
  static const double glassBlur = 20.0;
}

// --- Typography ---
class SovFonts {
  SovFonts._();

  static const String mono = 'JetBrains Mono';
  static const String ui = 'Inter';
  static const double terminalFontDesktop = 14.0;
  static const double terminalFontMobile = 12.0;
}
