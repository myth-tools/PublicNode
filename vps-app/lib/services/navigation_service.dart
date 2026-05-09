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

class NavigationService extends ChangeNotifier {
  int _currentIndex = 0;
  String? _pendingTerminalCommand;
  String? _pendingExplorerPath;

  int get currentIndex => _currentIndex;
  String? get pendingTerminalCommand => _pendingTerminalCommand;
  String? get pendingExplorerPath => _pendingExplorerPath;

  void setTab(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  void openInTerminal(String path) {
    _pendingTerminalCommand = 'cd "$path" && clear\n';
    _currentIndex = 0; // Assuming Terminal is index 0
    notifyListeners();
  }

  void openInExplorer(String path) {
    _pendingExplorerPath = path;
    _currentIndex = 2; // Assuming File Explorer is index 2
    notifyListeners();
  }

  void clearTerminalCommand() {
    _pendingTerminalCommand = null;
  }

  void clearExplorerPath() {
    _pendingExplorerPath = null;
  }
}
