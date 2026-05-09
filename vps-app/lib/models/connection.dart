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

/// Connection model — holds server URL, credentials, and connection state.
/// All identity values are loaded from vps-config.yaml at build time via
/// the config_loader service.
library;

enum ConnectionState { disconnected, connecting, handshake, ready, error }

class ConnectionInfo {
  final String label;
  final String wsUrl;
  final String sshHost;
  final int sshPort;
  final String username;
  final String password;
  final bool rememberPassword;

  const ConnectionInfo({
    required this.label,
    this.wsUrl = '',
    this.sshHost = '127.0.0.1',
    this.sshPort = 2222,
    this.username = 'root',
    this.password = '',
    this.rememberPassword = false,
  });

  ConnectionInfo copyWith({
    String? label,
    String? wsUrl,
    String? sshHost,
    int? sshPort,
    String? username,
    String? password,
    bool? rememberPassword,
  }) {
    return ConnectionInfo(
      label: label ?? this.label,
      wsUrl: wsUrl ?? this.wsUrl,
      sshHost: sshHost ?? this.sshHost,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      password: password ?? this.password,
      rememberPassword: rememberPassword ?? this.rememberPassword,
    );
  }
}
