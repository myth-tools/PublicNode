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

/// WebSocket-based SSHSocket transport for mobile clients.
/// Wraps a WebSocket channel to satisfy dartssh2's SSHSocket interface,
/// allowing SSH traffic to flow over wss:// through Cloudflare tunnels.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A custom SSH socket that routes SSH binary traffic over a WebSocket.
/// Used on mobile (Android/iOS) where spawning `cloudflared` is not possible.
class WebSocketSSHSocket implements SSHSocket {
  final WebSocketChannel _channel;
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>();
  final StreamController<Uint8List> _outgoing = StreamController<Uint8List>();
  bool _closed = false;

  WebSocketSSHSocket(this._channel) {
    // Pipe WebSocket → SSH
    _channel.stream.listen(
      (message) {
        if (_closed) return;
        if (message is Uint8List) {
          _incoming.add(message);
        } else if (message is List<int>) {
          _incoming.add(Uint8List.fromList(message));
        } else if (message is String) {
          _incoming.add(Uint8List.fromList(message.codeUnits));
        }
      },
      onDone: () => close(),
      onError: (Object error) => _incoming.addError(error),
    );

    // Pipe SSH → WebSocket
    _outgoing.stream.listen(
      (data) => _channel.sink.add(data),
      onDone: () => _channel.sink.close(),
      onError: (Object error) => _channel.sink.addError(error),
    );
  }

  /// Connect to a WebSocket URL and return the transport.
  static Future<WebSocketSSHSocket> connect(String url) async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    await channel.ready;
    return WebSocketSSHSocket(channel);
  }

  @override
  Stream<Uint8List> get stream => _incoming.stream;

  @override
  StreamSink<Uint8List> get sink => _outgoing.sink;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _outgoing.close();
    await _incoming.close();
    await _channel.sink.close();
  }

  @override
  void destroy() {
    close();
  }

  @override
  Future<void> get done => _outgoing.done;
}
