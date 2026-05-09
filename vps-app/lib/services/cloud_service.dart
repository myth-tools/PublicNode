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

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'storage_service.dart';

enum CloudState { idle, checking, igniting, booting, online, error }

class CloudService extends ChangeNotifier {
  CloudState _state = CloudState.idle;
  String? _statusMessage;
  String? _errorMessage;
  double _progress = 0;
  final List<String> _bootLogs = [];
  final Set<String> _processedMessageIds = {};
  double _speedFactor = 1.0;

  // The session ID is generated at ignition and is the single source of truth.
  // ALL signals from ntfy must carry this tag to be accepted.
  String? _sessionId;

  final _remoteSignalController =
      StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get remoteSignals =>
      _remoteSignalController.stream;

  // Persistent client for HTTP Keep-Alive (Speed & Less overhead)
  final http.Client _client = http.Client();

  CloudState get state => _state;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  double get progress => _progress;
  List<String> get bootLogs => _bootLogs;
  String? get sessionId => _sessionId;

  // --- Real-Time Booting Telemetry (V3: Exact Accuracy) ---
  Stopwatch? _bootStopwatch;
  Timer? _analyticsTimer;
  int _signalsReceived = 0;
  int _milestonesReached = 0;

  Stopwatch? _lockStopwatch;
  bool _isWaitingForLock = false;

  double _smoothProgress = 0;

  String get elapsedText =>
      _formatDuration(_bootStopwatch?.elapsed ?? Duration.zero);
  String get etaText => _calculateUltraEta();
  String get lockTimeText =>
      _formatDuration(_lockStopwatch?.elapsed ?? Duration.zero);
  bool get isWaitingForLock => _isWaitingForLock;
  double get smoothProgress => _smoothProgress;
  int get signalsReceived => _signalsReceived;
  int get milestonesCount => _milestonesReached;

  final List<BootMilestone> _milestones = [
    BootMilestone(
      'WAITING FOR SYSTEM PACKAGE LOCKS...',
      0.05,
      15,
      'Checking system security...',
      displayName: 'Securing Environment',
    ),
    BootMilestone(
      'SYNCING PUBLICNODE ASSETS...',
      0.10,
      10,
      'Downloading core files...',
      displayName: 'Syncing Core Assets',
    ),
    BootMilestone(
      'SYSTEM VAULT: Ready',
      0.15,
      5,
      'Preparing backup storage...',
      displayName: 'Initializing Storage',
    ),
    BootMilestone(
      'PROVISIONING PROOT',
      0.25,
      20,
      'Setting up system core...',
      displayName: 'System Core Setup',
    ),
    BootMilestone(
      'SYSTEM VAULT: Initializing',
      0.35,
      15,
      'Preparing your workspace...',
      displayName: 'Preparing Workspace',
    ),
    BootMilestone(
      'POLISHING SHELL',
      0.40,
      10,
      'Optimizing your interface...',
      displayName: 'Polishing Interface',
    ),
    BootMilestone(
      'RESOURCES ARMORED',
      0.45,
      5,
      'System files secured.',
      displayName: 'Securing Files',
    ),
    BootMilestone(
      'MATERIALIZING ASSETS...',
      0.50,
      10,
      'Setting up system components...',
      displayName: 'Deploying Assets',
    ),
    BootMilestone(
      'OS CORE MATERIALIZED',
      0.55,
      5,
      'System core is ready.',
      displayName: 'System Core Ready',
    ),
    BootMilestone(
      'RESTORE PULSE',
      0.60,
      20,
      'Loading your saved data...',
      displayName: 'Restoring Data',
    ),
    BootMilestone(
      'RESTORE COMPLETE',
      0.65,
      5,
      'Data loading finished.',
      displayName: 'Loading Finished',
    ),
    BootMilestone(
      'LAUNCHING ENGINE...',
      0.75,
      10,
      'Starting background services...',
      displayName: 'Starting Services',
    ),
    BootMilestone(
      'ARMORING SSH',
      0.80,
      10,
      'Securing remote access...',
      displayName: 'Securing Access',
    ),
    BootMilestone(
      'WEBSOCKET BRIDGE ARMED',
      0.85,
      5,
      'Connection bridge is active.',
      displayName: 'Connecting Bridge',
    ),
    BootMilestone(
      'SSH DAEMON READY',
      0.90,
      5,
      'Remote connection is ready.',
      displayName: 'Remote Ready',
    ),
    BootMilestone(
      'STABILIZING BACKBONE...',
      0.95,
      10,
      'Finalizing connection...',
      displayName: 'Finalizing Hub',
    ),
    BootMilestone(
      'PUBLICNODE PERSISTENCE ONLINE',
      1.0,
      5,
      'System is fully operational.',
      displayName: 'All Systems Online',
    ),
  ];

  List<BootMilestone> get allMilestones => _milestones;

  List<String> get recentLogs => _bootLogs.length > 5
      ? _bootLogs.sublist(_bootLogs.length - 5)
      : _bootLogs;

  String get currentTaskDescription {
    for (var m in _milestones.reversed) {
      if (m.reached) return m.description;
    }
    return 'Initializing...';
  }

  // Cached identity properties (loaded from StorageService)
  String _username = '';
  String _apiKey = '';
  String _kernelSlug = 'publicnode-vps-engine';

  String get username => _username;
  String get apiKey => _apiKey;
  String get kernelSlug => _kernelSlug;

  String _time() =>
      "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";

  /// Load cached identity from storage (call on service init or when needed).
  Future<void> loadIdentity() async {
    final saved = await StorageService.loadConnection();
    _username = saved['kagUser'] ?? '';
    _apiKey = saved['kagKey'] ?? '';
    _kernelSlug = saved['kernelSlug'] ?? 'publicnode-vps-engine';
  }

  void _setState(CloudState state, [String? message]) {
    _state = state;
    _statusMessage = message;
    if (message != null && state != CloudState.idle) {
      _bootLogs.add("[${_time()}] $message");
      // Cap logs at 500 entries (Memory optimization)
      if (_bootLogs.length > 500) _bootLogs.removeAt(0);
    }
    notifyListeners();
  }

  /// Get the current status of the Kaggle kernel (running, error, queued, etc.).
  Future<String> getKernelStatus(
    String user,
    String key,
    String kernelSlug,
  ) async {
    final auth = base64.encode(utf8.encode('$user:$key'));
    try {
      final response = await _client.get(
        Uri.parse(
          'https://www.kaggle.com/api/v1/kernels/status/$user/$kernelSlug',
        ),
        headers: {
          'Authorization': 'Basic $auth',
          'Accept': 'application/json',
          'User-Agent': 'PublicNode-Terminal/1.0',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status']?.toString().toLowerCase() ?? 'unknown';
      } else {
        return 'unknown';
      }
    } catch (e) {
      return 'unknown';
    }
  }

  /// Fetch the latest stdout logs from the Kaggle kernel.
  Future<String> fetchKernelLogs(
    String user,
    String key,
    String kernelSlug,
  ) async {
    final auth = base64.encode(utf8.encode('$user:$key'));
    try {
      final response = await _client.get(
        Uri.parse(
          'https://www.kaggle.com/api/v1/kernels/output/$user/$kernelSlug',
        ),
        headers: {
          'Authorization': 'Basic $auth',
          'Accept': 'application/json',
          'User-Agent': 'PublicNode-Terminal/1.0',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        // The output API returns the full notebook JSON or log stream
        final data = json.decode(response.body);
        final logStream = data['logStream'] as List?;
        if (logStream != null && logStream.isNotEmpty) {
          return logStream.map((e) => e['data'] ?? '').join('\n');
        }
        return 'No logs available in output stream.';
      }
      return 'Kaggle Log API Error: ${response.statusCode}';
    } catch (e) {
      return 'Failed to fetch logs: $e';
    }
  }

  /// Validate Kaggle credentials.
  Future<Map<String, dynamic>> validateKaggle(String user, String key) async {
    final cleanUser = user.trim();
    final cleanKey = key.trim();
    if (cleanUser.isEmpty || cleanKey.isEmpty) {
      return {'valid': false, 'message': 'Incomplete credentials'};
    }

    final auth = base64.encode(utf8.encode('$cleanUser:$cleanKey'));
    try {
      // Use kernels/list which is more robust for auth checks
      final response = await _client.get(
        Uri.parse(
          'https://www.kaggle.com/api/v1/kernels/list?user=$user&pageSize=1',
        ),
        headers: {
          'Authorization': 'Basic $auth',
          'User-Agent': 'PublicNode-Terminal/0.1.0',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'valid': true, 'message': 'Verified'};
      } else if (response.statusCode == 401) {
        return {
          'valid': false,
          'message': 'Unauthorized',
          'guide': 'Check your Kaggle API key. It may be expired or revoked.',
        };
      } else {
        String errorMsg = 'Invalid Credentials';
        try {
          final decoded = json.decode(response.body);
          errorMsg = decoded['message'] ?? decoded['error'] ?? errorMsg;
        } catch (_) {}

        return {
          'valid': false,
          'message': errorMsg,
          'guide':
              'Verify your username matches exactly what is in kaggle.json',
        };
      }
    } catch (e) {
      String msg = 'Network Error';
      String guide = 'Check your internet or Kaggle API status';

      if (e.toString().contains('SocketException')) {
        msg = 'Connection Blocked';
        guide = 'Kaggle is unreachable. Check your VPN, Firewall, or ISP.';
      } else if (e is TimeoutException) {
        msg = 'Request Timed Out';
        guide = 'The connection is too slow. Try a more stable network.';
      }

      return {
        'valid': false,
        'message': msg,
        'guide': guide,
      };
    }
  }

  /// Validate HuggingFace token and check "WRITE" permission.
  Future<Map<String, dynamic>> validateHuggingFace(String token) async {
    final sanitizedToken = token.trim();
    if (sanitizedToken.isEmpty) {
      return {'valid': false, 'message': 'Token required'};
    }

    try {
      final response = await _client.get(
        Uri.parse('https://huggingface.co/api/whoami-v2'),
        headers: {
          'Authorization': 'Bearer $sanitizedToken',
          'User-Agent': 'PublicNode-Terminal/0.1.0',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Robust role detection across different HF API versions/token types
        String role = '';
        if (data['auth']?['accessToken']?['role'] != null) {
          role = data['auth']['accessToken']['role'].toString().toLowerCase();
        } else if (data['token']?['role'] != null) {
          role = data['token']['role'].toString().toLowerCase();
        }

        if (role == 'write' || role == 'admin' || role == 'own') {
          return {'valid': true, 'message': 'Verified ($role Access)'};
        } else {
          return {
            'valid': false,
            'message': 'Read-Only Token ($role)',
            'guide':
                'Go to HF Settings -> Access Tokens and create a "WRITE" token.',
          };
        }
      } else if (response.statusCode == 401) {
        return {
          'valid': false,
          'message': 'Invalid Token',
          'guide': 'Ensure you copied the entire token string correctly.',
        };
      } else {
        return {
          'valid': false,
          'message': 'HF API Error (${response.statusCode})',
          'guide': 'HuggingFace services might be experiencing issues.',
        };
      }
    } catch (e) {
      return {
        'valid': false,
        'message': 'Connection Error',
        'guide': 'Check your network or firewall settings',
      };
    }
  }

  /// Patch notebook using simple string replacement - SAFE and won't break JSON
  String _patchNotebookSafely(
    String notebookContent, {
    required String signalTopic,
    required String vpsPassB64,
    required String kagUser,
    required String hfToken,
    required String hfRepo,
    required String sessionId,
    required bool guiEnabled,
  }) {
    try {
      final Map<String, dynamic> nb = json.decode(notebookContent);
      final List<dynamic> cells = nb['cells'] ?? [];

      final replacements = {
        'SIGNAL_TOPIC': signalTopic,
        'VPS_PASS_B64': vpsPassB64,
        'KAG_USER': kagUser,
        'HF_TOKEN': hfToken,
        'HF_REPO': hfRepo,
        'SESSION_ID': sessionId,
        'GUI_ENABLED': guiEnabled ? 'true' : 'false',
      };

      for (var cell in cells) {
        if (cell['cell_type'] == 'code') {
          var source = cell['source'];
          if (source == null) continue;

          // Normalize source to a single string for robust regex matching
          String sourceStr =
              (source is List) ? source.join('') : source.toString();
          bool wasList = source is List;

          replacements.forEach((key, value) {
            // Regex: Start of line, optional whitespace, key, then '=' with optional whitespace.
            // (\n?) at the end ensures we capture and preserve the newline if present.
            final regex = RegExp(
              '^(\\s*)$key(\\s*=\\s*).*(\n?)',
              multiLine: true,
            );
            sourceStr = sourceStr.replaceAllMapped(regex, (match) {
              final indent = match.group(1) ?? '';
              final equals = match.group(2) ?? ' = ';
              final newline = match.group(3) ?? '';
              return "$indent$key$equals'$value'$newline";
            });
          });

          if (wasList) {
            // Re-split into list of strings, each ending with \n to match Jupyter style
            final lines = sourceStr.split(RegExp(r'(?<=\n)'));
            // Remove empty strings but keep lines that are just \n
            cell['source'] = lines.where((l) => l.isNotEmpty).toList();
          } else {
            cell['source'] = sourceStr;
          }
        }
      }

      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(nb);
    } catch (e) {
      debugPrint('CRITICAL: Failed to parse/patch notebook JSON: $e');
      return notebookContent;
    }
  }

  /// Ignite the VPS! This calls the Kaggle API to start the kernel.
  /// Generates a fresh SESSION_ID and clears all previous log state.
  Future<void> igniteVps({
    String? user,
    String? key,
    required String kernelSlug,
    required String notebookContent,
    bool guiEnabled = false,
  }) async {
    // --- CRITICAL: Reset all state FIRST before ignition ---
    _bootLogs.clear();
    _sessionId = 's${DateTime.now().millisecondsSinceEpoch}';
    _processedMessageIds.clear();
    _state = CloudState.igniting;
    _statusMessage = 'Sending ignition pulse to Kaggle...';
    _errorMessage = null;
    _progress = 0.0;
    _smoothProgress = 0.0;
    _signalsReceived = 0;
    _milestonesReached = 0;
    _speedFactor = 1.0;
    for (var m in _milestones) {
      m.reached = false;
      m.actualTime = null;
    }

    // Start Analytics
    _bootStopwatch = Stopwatch()..start();
    _lockStopwatch = null;
    _isWaitingForLock = false;
    _analyticsTimer?.cancel();
    _analyticsTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_state == CloudState.booting || _state == CloudState.igniting) {
        // Smoothly interpolate towards target progress
        if (_smoothProgress < _progress) {
          // Rapidly catch up to the authoritative milestone signal
          _smoothProgress += 0.01;
          if (_smoothProgress > _progress) _smoothProgress = _progress;
        } else if (_smoothProgress < 0.99) {
          // --- Industry Grade Predictive Crawl ---
          // Find the upcoming milestone to estimate speed
          BootMilestone? next;
          for (var m in _milestones) {
            if (!m.reached) {
              next = m;
              break;
            }
          }

          if (next != null) {
            // Calculate progress gap to the next target
            final gap = next.progress - _smoothProgress;
            if (gap > 0) {
              // Distribute gap over expected duration (10 ticks per second)
              // We crawl at 40% of expected speed to ensure we don't hit the next
              // milestone before the real signal arrives.
              final increment = (gap / (next.expectedSeconds * 10)) * 0.4;
              _smoothProgress += increment.clamp(0.0001, 0.0008);
            }
          } else {
            // Heartbeat for final stabilization
            _smoothProgress += 0.0001;
          }
        }
        notifyListeners();
      }
    });

    notifyListeners();

    String finalUser = user ?? '';
    String finalKey = key ?? '';

    if (user == null || key == null) {
      final saved = await StorageService.loadConnection();
      finalUser = saved['kagUser'] ?? '';
      finalKey = saved['kagKey'] ?? '';
    }

    if (finalUser.isEmpty || finalKey.isEmpty) {
      _setState(CloudState.error, 'Kaggle credentials not configured.');
      throw Exception(
        'Kaggle credentials not configured. Please go to Settings.',
      );
    }

    final auth = base64.encode(utf8.encode('$finalUser:$finalKey'));

    try {
      // 1. Prepare Dynamic Content
      final bytes = utf8.encode(finalUser);
      final hash = sha256.convert(bytes).toString().substring(0, 12);

      // Load settings to get topic prefix
      final settings = await StorageService.loadConnection();
      final topicPrefix = settings['topicPrefix'] ?? 'vps-root';
      final signalTopic = "$topicPrefix-$hash";

      final savedPass = settings['password'] ?? '';
      final vpsPass = savedPass.isNotEmpty
          ? savedPass
          : 'vps-${DateTime.now().millisecondsSinceEpoch}';
      final vpsPassB64 = base64.encode(utf8.encode(vpsPass));
      final hfToken = settings['hfToken'] ?? '';

      final hfRepo = settings['hfRepo'] ?? '';

      // 2. Patch notebook using string replacement (SAFE - doesn't break JSON)
      final customizedNotebook = _patchNotebookSafely(
        notebookContent,
        signalTopic: signalTopic,
        vpsPassB64: vpsPassB64,
        kagUser: finalUser,
        hfToken: hfToken,
        hfRepo: hfRepo,
        sessionId: _sessionId!,
        guiEnabled: guiEnabled,
      );

      // Validate JSON integrity before sending (CRITICAL)
      try {
        json.decode(customizedNotebook);
        // Log the first few chars and length for sanity check
        debugPrint(
          'INFO: Notebook payload validated. Length: ${customizedNotebook.length}. Start: ${customizedNotebook.substring(0, 50)}',
        );
      } catch (e) {
        debugPrint('CRITICAL: Patched notebook JSON validation failed: $e');
        _setState(
          CloudState.error,
          'Internal Error: Corrupt notebook payload.',
        );
        throw Exception('Failed to generate valid notebook JSON. Check logs.');
      }

      final response = await _client
          .post(
            Uri.parse('https://www.kaggle.com/api/v1/kernels/push'),
            headers: {
              'Authorization': 'Basic $auth',
              'Content-Type': 'application/json',
              'User-Agent': 'PublicNode-Terminal/1.0',
            },
            body: json.encode({
              'slug': '$finalUser/$kernelSlug',
              'newTitle': kernelSlug,
              'text': customizedNotebook,
              'language': 'python',
              'kernelType': 'notebook',
              'isPrivate': true,
              'enableGpu': false,
              'enableInternet': true,
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        _setState(
          CloudState.booting,
          'PublicNode Engine Started [$_sessionId]. Connecting to cloud...',
        );
        _progress = 0.1;
      } else {
        final errorBody = response.body;
        debugPrint('Kaggle API Error (${response.statusCode}): $errorBody');
        throw Exception(
          'Kaggle API Error (${response.statusCode}): $errorBody',
        );
      }
    } catch (e) {
      _state = CloudState.error;
      _errorMessage = 'Ignition Failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Update the status message directly (useful for progress polling)
  void updateBootStatus(String message) {
    _bootLogs.add("[${_time()}] $message");
    if (_bootLogs.length > 500) _bootLogs.removeAt(0);

    // Exact Milestone Logic: Sequential Hardening
    for (int i = 0; i < _milestones.length; i++) {
      final m = _milestones[i];
      final cleanMsg = message.toUpperCase();
      final cleanName = m.name.toUpperCase();

      if (cleanMsg.contains(cleanName)) {
        // Mark this and all PREVIOUS milestones as reached
        for (int j = 0; j <= i; j++) {
          if (!_milestones[j].reached) {
            _milestones[j].reached = true;
            _milestones[j].actualTime ??= _bootStopwatch?.elapsed;
            _milestonesReached++;
          }
        }

        if (m.progress > _progress) {
          _progress = m.progress;
          _statusMessage = message;
        }

        // Ensure smoothProgress jumps to the new baseline if it was lagging
        if (_smoothProgress < _progress) {
          // Rapidly catch up, but keep a small animation buffer
          _smoothProgress = _progress - 0.01;
        }

        // Update Trend Analysis: Speed Factor
        _updateSpeedFactor();
        break;
      }
    }

    // Specific logic for Package Lock
    if (message.contains('WAITING FOR SYSTEM PACKAGE LOCKS...')) {
      _isWaitingForLock = true;
      _lockStopwatch ??= Stopwatch()..start();
    } else if (_isWaitingForLock) {
      if (!message.contains('WAITING FOR SYSTEM PACKAGE LOCKS...')) {
        _isWaitingForLock = false;
        _lockStopwatch?.stop();
      }
    }

    notifyListeners();
  }

  void _updateSpeedFactor() {
    if (_bootStopwatch == null) return;

    double expectedElapsed = 0;
    double actualElapsed = 0;

    for (var m in _milestones) {
      if (m.reached && m.actualTime != null) {
        expectedElapsed += m.expectedSeconds;
        actualElapsed = m.actualTime!.inSeconds.toDouble();
      }
    }

    if (expectedElapsed > 0) {
      // 0.8 damping to avoid wild swings
      final rawFactor = actualElapsed / expectedElapsed;
      _speedFactor = (_speedFactor * 0.2) + (rawFactor * 0.8);
    }
  }

  String _calculateUltraEta() {
    if (_bootStopwatch == null || !_bootStopwatch!.isRunning) return '--:--';
    if (_progress >= 1.0) return 'Ready';

    double remainingExpected = 0;
    for (var m in _milestones) {
      if (!m.reached) {
        remainingExpected += m.expectedSeconds;
      }
    }

    final remaining = Duration(
      seconds: (remainingExpected * _speedFactor).toInt(),
    );
    if (remaining.inSeconds < 5) return 'Finalizing...';
    return _formatDuration(remaining);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  /// Poll ntfy.sh for cloud signals (STATUS logs, WS URL, Password).
  /// Uses JSON API for message deduplication.
  Future<Map<String, String>> fetchCloudSignals() async {
    if (_sessionId == null) return {};
    if (_state != CloudState.booting && _state != CloudState.igniting) {
      return {};
    }

    try {
      final saved = await StorageService.loadConnection();
      final kagUser = saved['kagUser'] ?? '';
      final topicPrefix = saved['topicPrefix'] ?? 'vps-root';

      if (kagUser.isEmpty) return {};

      final bytes = utf8.encode(kagUser);
      final hash = sha256.convert(bytes).toString().substring(0, 12);
      final signalTopic = "$topicPrefix-$hash";

      // Use JSON API to get unique message IDs. poll=1 returns cached messages and closes connection immediately.
      final response = await _client.get(
        Uri.parse('https://ntfy.sh/$signalTopic/json?since=20m&poll=1'),
        headers: {'User-Agent': 'PublicNode-Terminal/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return {};

      final lines = response.body.split('\n');
      String wsUrl = '';
      String apiUrl = '';
      String guiUrl = '';
      String password = '';

      for (final line in lines) {
        if (line.isEmpty) continue;

        try {
          final data = json.decode(line);
          if (data['event'] != 'message') continue;

          final msgId = data['id']?.toString() ?? '';
          if (msgId.isEmpty || _processedMessageIds.contains(msgId)) continue;
          // HARDEN: Cap dedup set to prevent unbounded memory growth
          if (_processedMessageIds.length > 1000) _processedMessageIds.clear();

          final rawContent = data['message']?.toString() ?? '';
          if (rawContent.isEmpty) continue;

          // --- 1. Handle plain-text STATUS logs ---
          if (rawContent.startsWith('STATUS:')) {
            var msg = rawContent.substring(7).trim();
            if (msg.startsWith('[$_sessionId]')) {
              msg = msg.substring(_sessionId!.length + 2).trim();
              _signalsReceived++;
              updateBootStatus(msg);
              _processedMessageIds.add(msgId);

              if (msg.contains('❌') ||
                  msg.toLowerCase().contains('critical failure')) {
                _state = CloudState.error;
                _errorMessage = msg;
                notifyListeners();
              }
            }
            continue;
          }

          // --- 2. Handle base64-encoded connection signals (API: / WS: / PASS:) ---
          try {
            final decoded = utf8.decode(base64.decode(rawContent));

            String? extract(String d, String p) {
              if (!d.startsWith(p)) return null;
              final payload = d.substring(p.length);
              if (!payload.startsWith('[$_sessionId]')) return null;
              return payload.substring(_sessionId!.length + 2).trim();
            }

            final api = extract(decoded, 'API:');
            if (api != null && api.isNotEmpty) {
              apiUrl = api;
              _processedMessageIds.add(msgId);
            }

            final ws = extract(decoded, 'WS:');
            if (ws != null && ws.isNotEmpty) {
              wsUrl = ws;
              _processedMessageIds.add(msgId);
            }

            final pass = extract(decoded, 'PASS:');
            if (pass != null && pass.isNotEmpty) {
              password = pass;
              _processedMessageIds.add(msgId);
            }

            final gui = extract(decoded, 'GUI:');
            if (gui != null && gui.isNotEmpty) {
              guiUrl = gui;
              _processedMessageIds.add(msgId);
            }

            // --- Remote Server Notifications (V8: Industry Grade) ---
            if (rawContent.startsWith('STATUS:')) {
              final match =
                  RegExp(r'STATUS: \[(.*?)\] (.*)').firstMatch(rawContent);
              if (match != null) {
                final sigSession = match.group(1);
                final message = match.group(2);

                if (sigSession == _sessionId &&
                    !_processedMessageIds.contains(msgId)) {
                  _remoteSignalController.add({
                    'type': 'status',
                    'message': message!,
                  });
                  _processedMessageIds.add(msgId);
                }
              }
            }
          } catch (_) {
            // Not base64 or not our signal
          }
        } catch (_) {}
      }

      return {
        'wsUrl': wsUrl,
        'password': password,
        'apiUrl': apiUrl,
        'guiUrl': guiUrl
      };
    } catch (e) {
      debugPrint('Fetch error: $e');
      return {};
    }
  }

  /// Send a control signal (SAVE or KILL) to the VPS
  Future<void> sendControlSignal(String signal) async {
    try {
      final saved = await StorageService.loadConnection();
      final kagUser = saved['kagUser'] ?? '';
      final topicPrefix = saved['topicPrefix'] ?? 'vps-root';

      if (kagUser.isEmpty) return;

      final bytes = utf8.encode(kagUser);
      final hash = sha256.convert(bytes).toString().substring(0, 12);
      final signalTopic = "$topicPrefix-$hash-control";

      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = "$signal:$timestamp";

      await _client.post(
        Uri.parse('https://ntfy.sh/$signalTopic'),
        body: payload,
        headers: {'User-Agent': 'PublicNode-Terminal/1.0'},
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Ignore control signal errors to avoid blocking UI
    }
  }

  void reset() {
    _state = CloudState.idle;
    _errorMessage = null;
    _statusMessage = null;
    _progress = 0;
    _sessionId = null;
    _bootLogs.clear();
    _bootStopwatch?.stop();
    _bootStopwatch = null;
    _analyticsTimer?.cancel();
    _lockStopwatch?.stop();
    _lockStopwatch = null;
    _isWaitingForLock = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _analyticsTimer?.cancel();
    _client.close();
    super.dispose();
  }
}

class BootMilestone {
  final String name;
  final String displayName;
  final double progress;
  final int expectedSeconds;
  final String description;
  bool reached = false;
  Duration? actualTime;

  BootMilestone(
    this.name,
    this.progress,
    this.expectedSeconds,
    this.description, {
    required this.displayName,
  });
}
