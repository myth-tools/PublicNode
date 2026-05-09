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

/// SSH connection manager for the PublicNode Terminal app.
/// Handles both WebSocket (mobile) and direct TCP (desktop) connections
/// using dartssh2. Exposes an xterm Terminal for the UI to bind.
library;

import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/connection.dart' as model;
import 'ws_transport.dart';

class SshService extends ChangeNotifier {
  SSHClient? _client;
  SSHSession? _session;
  Terminal? _terminal;
  model.ConnectionState _state = model.ConnectionState.disconnected;
  String _statusMessage = '';
  String? _errorMessage;
  WebSocketSSHSocket? _wsSocket;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  // --- Public Getters ---
  Terminal? get terminal => _terminal;
  model.ConnectionState get state => _state;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _state == model.ConnectionState.ready;

  /// Update connection state and notify UI listeners.
  void _setState(model.ConnectionState s, [String msg = '']) {
    _state = s;
    _statusMessage = msg;
    if (s != model.ConnectionState.error) _errorMessage = null;
    notifyListeners();
  }

  model.ConnectionInfo? _lastInfo;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  /// Connect using the best available transport.
  Future<void> connect(
    model.ConnectionInfo info, {
    int? width,
    int? height,
  }) async {
    _lastInfo = info;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    await _performConnect(info, width: width, height: height);
  }

  Future<void> _performConnect(
    model.ConnectionInfo info, {
    int? width,
    int? height,
  }) async {
    try {
      _setState(model.ConnectionState.connecting, 'Connecting to server...');

      final bool isUrl = info.wsUrl.contains('://') ||
          info.wsUrl.contains('.trycloudflare.com');

      if (isUrl) {
        await _connectViaWebSocket(info, width: width, height: height);
      } else {
        await _connectViaTcp(info, width: width, height: height);
      }
    } catch (e) {
      _state = model.ConnectionState.error;
      _errorMessage = e.toString();
      _statusMessage = 'Connection failed';
      notifyListeners();
      _startReconnectionLoop();
    }
  }

  void _startReconnectionLoop() {
    if (_lastInfo == null || _reconnectAttempts >= 10) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_state == model.ConnectionState.error ||
          _state == model.ConnectionState.disconnected) {
        _reconnectAttempts++;
        _performConnect(_lastInfo!);
      }
    });
  }

  /// Direct TCP connection (Desktop — lowest latency).
  Future<void> _connectViaTcp(
    model.ConnectionInfo info, {
    int? width,
    int? height,
  }) async {
    _setState(
        model.ConnectionState.connecting, 'Starting direct connection...');

    final socket = await SSHSocket.connect(
      info.sshHost,
      info.sshPort,
      timeout: const Duration(seconds: 15),
    );

    _setState(model.ConnectionState.handshake, 'Starting secure login...');

    _client = SSHClient(
      socket,
      username: info.username,
      onPasswordRequest: () => info.password,
      keepAliveInterval: const Duration(seconds: 30),
    );

    await _startShell(initialWidth: width, initialHeight: height);
  }

  /// WebSocket connection (Mobile — universal).
  Future<void> _connectViaWebSocket(
    model.ConnectionInfo info, {
    int? width,
    int? height,
  }) async {
    _setState(model.ConnectionState.connecting, 'Connecting to cloud...');

    String rawUrl = info.wsUrl.trim();
    debugPrint('[DEBUG] Original wsUrl: "$rawUrl"');

    // 1. Strip fragments and queries immediately
    if (rawUrl.contains('#')) rawUrl = rawUrl.split('#')[0];
    if (rawUrl.contains('?')) rawUrl = rawUrl.split('?')[0];

    // 2. Ensure correct protocol and remove any accidental double-slashes
    if (rawUrl.startsWith('https://')) {
      rawUrl = rawUrl.replaceFirst('https://', 'wss://');
    } else if (rawUrl.startsWith('http:' '//')) {
      rawUrl = rawUrl.replaceFirst('http:' '//', 'ws://');
    } else if (!rawUrl.startsWith('wss://') && !rawUrl.startsWith('ws://')) {
      rawUrl = 'wss://$rawUrl';
    }

    // 3. Strict URI Reconstruction to eliminate :0 or malformed components
    Uri uri = Uri.parse(rawUrl);
    // Cloudflare tunnels always use standard TLS ports (443)
    if (uri.scheme == 'wss' && (uri.port == 0 || uri.port == 80)) {
      uri = uri.replace(port: 443);
    }

    // Final sanitized URL (no fragments, no trailing dots, correct port)
    final wsUrl = uri.replace(fragment: null).toString().replaceAll(':0', '');
    debugPrint('[DEBUG] Sanitized wsUrl: "$wsUrl"');

    // V7.2 Resilience: Multi-Stage Handshake Retry
    int retryCount = 0;
    const maxRetries = 5;

    while (retryCount < maxRetries) {
      try {
        _wsSocket = await WebSocketSSHSocket.connect(wsUrl);
        debugPrint(
            '[DEBUG] WebSocket handshake successful on attempt ${retryCount + 1}');
        break;
      } catch (e) {
        retryCount++;
        debugPrint(
            '[DEBUG] WebSocket handshake failed (Attempt $retryCount): $e');
        if (retryCount >= maxRetries) {
          debugPrint('[DEBUG] Max retries reached. Connection abandoned.');
          rethrow;
        }
        _setState(model.ConnectionState.connecting,
            'Connection unstable, retrying ($retryCount/$maxRetries)...');
        await Future.delayed(Duration(seconds: 1 + retryCount));
      }
    }

    _setState(model.ConnectionState.handshake, 'Starting secure login...');

    _client = SSHClient(
      _wsSocket!,
      username: info.username,
      onPasswordRequest: () => info.password,
      keepAliveInterval: const Duration(seconds: 30),
    );

    await _startShell(initialWidth: width, initialHeight: height);
  }

  /// Request a PTY and start an interactive shell session.
  Future<void> _startShell({int? initialWidth, int? initialHeight}) async {
    _setState(model.ConnectionState.handshake, 'Starting terminal...');

    try {
      _session = await _client!
          .shell(
            pty: SSHPtyConfig(
              width: initialWidth ?? 80,
              height: initialHeight ?? 24,
              type: 'xterm-256color',
            ),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('TTY Initialization Failed: $e');
    }

    if (_terminal == null) {
      _terminal = Terminal(maxLines: 100000);
      _terminal!.onResize = (width, height, pixelWidth, pixelHeight) {
        if (width > 10 && height > 5) {
          resizePty(width, height);
        }
      };
      _terminal!.setCursorVisibleMode(true); // Ensure cursor starts visible
    } else {
      _terminal!.write('\r\n[Reconnected to session]\r\n');
    }

    _setState(model.ConnectionState.ready, 'Terminal is ready');
    _reconnectAttempts = 0;

    // Industrial Hardening: Keep screen awake during active terminal session
    try {
      WakelockPlus.enable();
    } catch (_) {}

    // Send the correct actual dimensions to the PTY after bash has fully started.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_terminal != null && _state == model.ConnectionState.ready) {
        resizePty(_terminal!.viewWidth, _terminal!.viewHeight);
        // Force the prompt to redraw with the new correct dimensions
        send('\n');
      }
    });

    // --- Clean Resource Transition ---
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    // Do NOT close the session here, as we just started it!

    // Pipe SSH stdout → Terminal display (Robust UTF-8 Decoding)
    _stdoutSub = _session!.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      (data) {
        if (_state != model.ConnectionState.ready) return;
        _terminal!.write(data);
      },
      onError: (e) {
        debugPrint('[SSH] Stdout Error: $e');
        _terminal!.write('\r\n[SSH Error: $e]\r\n');
      },
      onDone: () {
        if (_state != model.ConnectionState.disconnected) {
          _setState(model.ConnectionState.error, 'Connection lost');
          _startReconnectionLoop();
        }
      },
      cancelOnError: false,
    );

    _stderrSub = _session!.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (data) => _terminal!.write(data),
          onError: (e) => debugPrint('[SSH] Stderr Error: $e'),
          cancelOnError: false,
        );

    // Pipe Terminal input → SSH stdin
    _terminal!.onOutput = (data) {
      if (_state == model.ConnectionState.ready) {
        _session!.stdin.add(utf8.encode(data));
      }
    };
  }

  /// Manually send data to the SSH session (e.g., for pasting).
  void send(String data) {
    if (_state == model.ConnectionState.ready) {
      _session?.stdin.add(utf8.encode(data));
    }
  }

  /// Deep Clear: Reset both local buffer and remote shell state
  void clearTerminal() {
    if (_terminal != null) {
      _terminal!.write('\x1b[2J\x1b[H'); // Clear screen and home cursor
      send('clear\n');
      notifyListeners();
    }
  }

  /// Resize the remote PTY when the terminal widget resizes.
  void resizePty(int width, int height) {
    if (width < 10 || height < 5) {
      return; // Guard against tiny invalid dimensions
    }
    try {
      _session?.resizeTerminal(width, height);
    } catch (_) {
      // Ignore resize errors during connection transitions
    }
  }

  /// Disconnect and clean up all resources.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _lastInfo = null;

    if (_state == model.ConnectionState.disconnected) return;

    try {
      _session?.close();
      _client?.close();
      await _wsSocket?.close();
    } catch (_) {
      // Best effort cleanup
    } finally {
      _session = null;
      _client = null;
      _wsSocket = null;
      _terminal = null;
      _setState(model.ConnectionState.disconnected, 'Disconnected');

      // Release wake lock
      try {
        WakelockPlus.disable();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
