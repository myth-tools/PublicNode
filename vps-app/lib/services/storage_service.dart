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

/// Secure credential storage service.
/// Uses flutter_secure_storage for encrypted on-device persistence.
/// Supports the "Remember Password" feature (option c).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    lOptions: LinuxOptions(),
  );

  // --- Key constants ---
  static const _keyWsUrl = 'sov_ws_url';
  static const _keySshHost = 'sov_ssh_host';
  static const _keySshPort = 'sov_ssh_port';
  static const _keyUsername = 'sov_username';
  static const _keyPassword = 'sov_password';
  static const _keyRemember = 'sov_remember';
  static const _keyKaggleUser = 'sov_kag_user';
  static const _keyKaggleKey = 'sov_kag_key';
  static const _keyHfToken = 'sov_hf_token';
  static const _keyKernelSlug = 'sov_kernel_slug';
  static const _keyVaultSlug = 'sov_vault_slug';
  static const _keyTopicPrefix = 'sov_topic_prefix';
  static const _keyGuiEnabled = 'sov_gui_enabled'; // GUI desktop toggle

  /// Save connection details securely.
  static Future<void> saveConnection({
    required String wsUrl,
    required String sshHost,
    required int sshPort,
    required String username,
    required String password,
    required bool remember,
  }) async {
    await _storage.write(key: _keyWsUrl, value: wsUrl);
    await _storage.write(key: _keySshHost, value: sshHost);
    await _storage.write(key: _keySshPort, value: sshPort.toString());
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyRemember, value: remember.toString());

    if (remember) {
      await _storage.write(key: _keyPassword, value: password);
    } else {
      await _storage.delete(key: _keyPassword);
    }
  }

  static Future<void> saveSettings({
    required String kaggleUser,
    required String kaggleKey,
    required String hfToken,
    String? vpsUser,
    String? kernelSlug,
    String? vaultSlug,
    String? topicPrefix,
    bool? guiEnabled,
  }) async {
    await _storage.write(key: _keyKaggleUser, value: kaggleUser);
    await _storage.write(key: _keyKaggleKey, value: kaggleKey);
    await _storage.write(key: _keyHfToken, value: hfToken);
    if (vpsUser != null) {
      await _storage.write(key: _keyUsername, value: vpsUser);
    }
    if (kernelSlug != null) {
      await _storage.write(key: _keyKernelSlug, value: kernelSlug);
    }
    if (vaultSlug != null) {
      await _storage.write(key: _keyVaultSlug, value: vaultSlug);
    }
    if (topicPrefix != null) {
      await _storage.write(key: _keyTopicPrefix, value: topicPrefix);
    }
    if (guiEnabled != null) {
      await _storage.write(key: _keyGuiEnabled, value: guiEnabled.toString());
    }
  }

  /// Save only the GUI enabled state (called from live toggle without re-saving all settings).
  static Future<void> saveGuiEnabled(bool enabled) async {
    await _storage.write(key: _keyGuiEnabled, value: enabled.toString());
  }

  /// Load saved connection details. Returns null values if not found.
  static Future<Map<String, String?>> loadConnection() async {
    return {
      'wsUrl': await _storage.read(key: _keyWsUrl),
      'sshHost': await _storage.read(key: _keySshHost),
      'sshPort': await _storage.read(key: _keySshPort),
      'username': await _storage.read(key: _keyUsername),
      'password': await _storage.read(key: _keyPassword),
      'remember': await _storage.read(key: _keyRemember),
      'kagUser': await _storage.read(key: _keyKaggleUser),
      'kagKey': await _storage.read(key: _keyKaggleKey),
      'hfToken': await _storage.read(key: _keyHfToken),
      'kernelSlug': await _storage.read(key: _keyKernelSlug),
      'vaultSlug': await _storage.read(key: _keyVaultSlug),
      'topicPrefix': await _storage.read(key: _keyTopicPrefix),
      'guiEnabled': await _storage.read(key: _keyGuiEnabled),
    };
  }

  /// Clear all stored credentials.
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
