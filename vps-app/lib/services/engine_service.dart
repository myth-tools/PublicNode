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

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// EngineService — Industry-grade telemetry and cloud control.
/// Communicates with the vps-os engine API (/api/system/pulse).
class EngineService extends ChangeNotifier {
  Timer? _pulseTimer;
  Map<String, dynamic> _stats = {};
  List<dynamic> _procs = [];
  List<String> _logs = [];
  List<dynamic> _httpLogs = [];
  bool _isOnline = false;
  String? _error;
  String _baseUrl = '';
  String _password = '';

  // GUI State
  bool _guiEnabled = false;
  bool _guiRunning = false;
  String? _guiUrl;
  String _guiResolution = 'Unknown';
  String _guiDisplay = ':99';

  final http.Client _client = http.Client();

  bool get isOnline => _isOnline;
  Map<String, dynamic> get stats => _stats;
  List<dynamic> get procs => _procs;
  List<String> get logs => _logs;
  List<dynamic> get httpLogs => _httpLogs;
  String? get error => _error;

  // GUI Accessors
  bool get guiEnabled => _guiEnabled;
  bool get guiRunning => _guiRunning;
  String? get guiUrl => _guiUrl;
  String get guiResolution => _guiResolution;
  String get guiDisplay => _guiDisplay;

  void setGuiUrl(String url) {
    _guiUrl = url;
    notifyListeners();
  }

  Future<bool> systemSave() async {
    try {
      final uri = _baseUrl.startsWith('https')
          ? Uri.parse('$_baseUrl/api/system/save')
          : Uri.parse('$_baseUrl/api/system/save');

      final response = await _client.post(
        uri,
        headers: {'X-PublicNode-Key': _password},
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 202;
    } catch (e) {
      debugPrint('SYSTEM VAULT: Save failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> systemVaultStatus() async {
    try {
      final uri = _baseUrl.startsWith('https')
          ? Uri.parse('$_baseUrl/api/system/vault/status')
          : Uri.parse('$_baseUrl/api/system/vault/status');

      final response = await _client.get(
        uri,
        headers: {'X-PublicNode-Key': _password},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('SYSTEM VAULT: Status check failed: $e');
    }
    return {'configured': false, 'archive_exists': false};
  }

  Future<List<dynamic>> systemVaultHistory() async {
    try {
      final uri = _baseUrl.startsWith('https')
          ? Uri.parse('$_baseUrl/api/system/vault/history')
          : Uri.parse('$_baseUrl/api/system/vault/history');

      final response = await _client.get(
        uri,
        headers: {'X-PublicNode-Key': _password},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('SYSTEM VAULT: History fetch failed: $e');
    }
    return [];
  }

  void startMonitoring(String baseUrl, String password) {
    _baseUrl = baseUrl;
    _password = password;
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchPulse(baseUrl, password),
    );
    _fetchPulse(baseUrl, password);
  }

  void stopMonitoring() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _isOnline = false;
    notifyListeners();
  }

  Future<void> _fetchPulse(String baseUrl, String password) async {
    try {
      final trimmedBase = baseUrl.trim();
      final cleanBase = trimmedBase
          .replaceFirst('wss://', '')
          .replaceFirst('ws://', '')
          .replaceFirst('https://', '')
          .replaceFirst('http:' '//', '')
          .split('/')
          .first;

      final isSecure = trimmedBase.startsWith('wss://') ||
          trimmedBase.startsWith('https://');

      if (cleanBase.isEmpty) return; // Prevent "No host" errors

      final uri = isSecure
          ? Uri.https(cleanBase, '/api/system/pulse')
          : Uri.http(cleanBase, '/api/system/pulse');

      final response = await _client.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${password.trim()}',
          'X-PublicNode-Key': password.trim(),
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _stats = data['stats'] ?? {};
        _procs = data['procs'] ?? [];
        _logs = List<String>.from(data['logs'] ?? []);
        _httpLogs = List<dynamic>.from(data['http_logs'] ?? []);

        if (!_isOnline) {
          _isOnline = true;
        }
        _error = null;

        // Also fetch GUI status in the background if we're online
        _fetchGuiStatus();
      } else {
        _isOnline = false;
        _error = 'Engine Error: ${response.statusCode}';
      }
    } catch (e) {
      _isOnline = false;
      _error = _translateError(e);
    }
    notifyListeners();
  }

  Future<void> _fetchGuiStatus() async {
    if (_baseUrl.isEmpty) return;
    try {
      // V12: Normalize URL same way as _fetchPulse to handle wss:// prefixes
      final trimmedBase = _baseUrl.trim();
      final cleanBase = trimmedBase
          .replaceFirst('wss://', '')
          .replaceFirst('ws://', '')
          .replaceFirst('https://', '')
          .replaceFirst('http:' '//', '')
          .split('/')
          .first;

      if (cleanBase.isEmpty) return;

      final isSecure = trimmedBase.startsWith('wss://') ||
          trimmedBase.startsWith('https://');

      final uri = isSecure
          ? Uri.https(cleanBase, '/api/gui/status')
          : Uri.http(cleanBase, '/api/gui/status');

      final response = await _client.get(
        uri,
        headers: {'X-PublicNode-Key': _password},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _guiEnabled = data['enabled'] ?? false;
        _guiRunning = data['running'] ?? false;
        _guiResolution = data['resolution'] ?? 'Unknown';
        _guiDisplay = data['display'] ?? ':99';

        // Only update _guiUrl if the backend provides one, otherwise preserve the injected one
        if (data['url'] != null) {
          _guiUrl = data['url'];
        }

        // V12: If GUI is disabled, clear any stale guiUrl to prevent gray screen
        if (!_guiEnabled) {
          _guiUrl = null;
        }

        notifyListeners();
      }
    } catch (_) {
      // Silently fail GUI status checks if the engine doesn't support it yet
    }
  }

  Future<Map<String, dynamic>> fetchGuiDiagnostics() async {
    if (_baseUrl.isEmpty) return {};
    try {
      final uri = Uri.parse('$_baseUrl/api/gui/diagnostic');
      final response = await _client.get(
        uri,
        headers: {'X-PublicNode-Key': _password},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('GUI DIAGNOSTICS FAILED: $e');
    }
    return {'error': 'Failed to reach diagnostic endpoint'};
  }

  Future<List<String>> fetchGuiLogs() async {
    if (_baseUrl.isEmpty) return [];
    try {
      final uri = Uri.parse('$_baseUrl/api/gui/logs');
      final response = await _client.get(
        uri,
        headers: {'X-PublicNode-Key': _password},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['logs'] ?? []);
      }
    } catch (e) {
      debugPrint('GUI LOGS FETCH FAILED: $e');
    }
    return ['Error: Failed to fetch GUI logs from engine.'];
  }

  /// Toggle the GUI desktop state on the VPS
  Future<bool> setGuiEnabled(bool enabled) async {
    if (_baseUrl.isEmpty) return false;
    try {
      final endpoint = enabled ? '/api/gui/start' : '/api/gui/stop';
      final uri = _baseUrl.startsWith('https')
          ? Uri.parse('$_baseUrl$endpoint')
          : Uri.parse('$_baseUrl$endpoint');

      final response = await _client.post(
        uri,
        headers: {'X-PublicNode-Key': _password},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await _fetchGuiStatus();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('GUI TOGGLE FAILED: $e');
      return false;
    }
  }

  /// Update arbitrary engine settings (e.g. enabling GUI via config)
  Future<bool> updateEngineSettings(Map<String, dynamic> settings) async {
    if (_baseUrl.isEmpty) return false;
    try {
      final uri = _baseUrl.startsWith('https')
          ? Uri.parse('$_baseUrl/api/settings/update')
          : Uri.parse('$_baseUrl/api/settings/update');

      final response = await _client
          .post(
            uri,
            headers: {
              'X-PublicNode-Key': _password,
              'Content-Type': 'application/json',
            },
            body: json.encode(settings),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SETTINGS UPDATE FAILED: $e');
      return false;
    }
  }

  String _translateError(dynamic e) {
    final errStr = e.toString().toLowerCase();
    if (errStr.contains('timeoutexception')) {
      return 'Connection Timeout: The VPS engine is taking longer than expected to respond. Please check your internet connection.';
    } else if (errStr.contains('connection refused') ||
        errStr.contains('errno 111')) {
      return 'Connection Refused: The VPS engine appears to be offline or starting up. Try again in a few moments.';
    } else if (errStr.contains('handshake_failed')) {
      return 'Security Handshake Failed: There was a problem establishing a secure connection to your VPS.';
    } else if (errStr.contains('failed host lookup')) {
      return 'Network Error: Could not resolve the VPS address. Please check your connection.';
    }
    return e.toString();
  }

  /// Trigger a manual telemetry update.
  Future<void> refreshPulse() async {
    await _fetchPulse(_baseUrl, _password);
  }

  /// Industry-Grade Termination: Properly shut down the Kaggle engine.
  Future<bool> powerOff() async {
    try {
      final trimmedBase = _baseUrl.trim();
      final cleanBase = trimmedBase
          .replaceFirst(RegExp(r'(https?|wss?)://'), '')
          .split('/')
          .first;

      final isSecure = trimmedBase.startsWith('wss://') ||
          trimmedBase.startsWith('https://');

      if (cleanBase.isEmpty) return false;

      final uri = isSecure
          ? Uri.https(cleanBase, '/api/system/shutdown')
          : Uri.http(cleanBase, '/api/system/shutdown');

      final response = await _client.post(
        uri,
        headers: {
          'X-PublicNode-Key': _password.trim(),
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        stopMonitoring();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('POWER OFF: Shutdown request failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    _client.close();
    super.dispose();
  }
}
