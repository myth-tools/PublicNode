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

/// Main entry point for the PublicNode Terminal app.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/theme.dart';
import 'screens/connect_screen.dart';
import 'services/ssh_service.dart';
import 'services/cloud_service.dart';
import 'services/engine_service.dart';
import 'services/navigation_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PublicNodeTerminalApp());
}

class PublicNodeTerminalApp extends StatelessWidget {
  const PublicNodeTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SshService()),
        ChangeNotifierProvider(create: (_) => CloudService()),
        ChangeNotifierProvider(create: (_) => EngineService()),
        ChangeNotifierProvider(create: (_) => NavigationService()),
      ],
      child: MaterialApp(
        title: 'PublicNode VPS',
        theme: buildPublicNodeTheme(),
        darkTheme: buildPublicNodeTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const ConnectScreen(),
      ),
    );
  }
}
