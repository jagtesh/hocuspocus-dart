/// Dart port of @hocuspocus/provider HocuspocusProviderWebsocket.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/HocuspocusProviderWebsocket.ts
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yjs_dart/src/lib0/observable.dart';

import 'types.dart';

/// Configuration for [HocuspocusProviderWebsocket].
class HocuspocusProviderWebsocketConfiguration {
  /// The WebSocket server URL.
  final String url;

  /// Minimum reconnect delay in milliseconds (default: 1000).
  final int minDelay;

  /// Maximum reconnect delay in milliseconds (default: 30000).
  final int maxDelay;

  /// Maximum number of reconnect attempts (default: unlimited = -1).
  final int maxRetries;

  /// Timeout for reconnect if no message received (ms, default: 30000).
  final int messageReconnectTimeout;

  const HocuspocusProviderWebsocketConfiguration({
    required this.url,
    this.minDelay = 1000,
    this.maxDelay = 30000,
    this.maxRetries = -1,
    this.messageReconnectTimeout = 30000,
  });
}

/// Manages the WebSocket connection with automatic reconnect.
///
/// Mirrors: `HocuspocusProviderWebsocket` in HocuspocusProviderWebsocket.ts
///
/// Emits: 'open', 'close', 'message', 'connect', 'disconnect', 'status', 'destroy'
class HocuspocusProviderWebsocket extends Observable<String> {
  final HocuspocusProviderWebsocketConfiguration configuration;

  WebSocketStatus _status = WebSocketStatus.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _messageReconnectTimer;

  int _retryCount = 0;
  bool _destroyed = false;

  HocuspocusProviderWebsocket(this.configuration);

  WebSocketStatus get status => _status;

  bool get isConnected => _status == WebSocketStatus.connected;

  /// Connect to the WebSocket server.
  Future<void> connect() async {
    if (_destroyed) return;
    if (_status == WebSocketStatus.connecting ||
        _status == WebSocketStatus.connected) return;

    _setStatus(WebSocketStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(configuration.url));
      await _channel!.ready;
      _onOpen();
    } catch (e) {
      _onClose(1006, 'Connection failed: $e');
    }
  }

  void _onOpen() {
    _retryCount = 0;
    _setStatus(WebSocketStatus.connected);
    _resetMessageReconnectTimer();

    _subscription = _channel!.stream.listen(
      (data) {
        _resetMessageReconnectTimer();
        Uint8List bytes;
        if (data is Uint8List) {
          bytes = data;
        } else if (data is List<int>) {
          bytes = Uint8List.fromList(data);
        } else {
          return;
        }
        emit('message', [bytes]);
      },
      onDone: () => _onClose(1000, 'Connection closed'),
      onError: (e) => _onClose(1006, 'Error: $e'),
    );

    emit('open', []);
    emit('connect', []);
  }

  void _onClose(int code, String reason) {
    _subscription?.cancel();
    _subscription = null;
    _messageReconnectTimer?.cancel();
    _messageReconnectTimer = null;

    final wasConnected = _status == WebSocketStatus.connected;
    _setStatus(WebSocketStatus.disconnected);

    if (wasConnected) {
      emit('disconnect', [code, reason]);
    }
    emit('close', [code, reason]);

    if (!_destroyed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (configuration.maxRetries >= 0 &&
        _retryCount >= configuration.maxRetries) {
      return;
    }

    final delay = _computeDelay();
    _retryCount++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), connect);
  }

  int _computeDelay() {
    final delay = configuration.minDelay * (1 << _retryCount.clamp(0, 10));
    return delay.clamp(configuration.minDelay, configuration.maxDelay);
  }

  void _resetMessageReconnectTimer() {
    _messageReconnectTimer?.cancel();
    _messageReconnectTimer = Timer(
      Duration(milliseconds: configuration.messageReconnectTimeout),
      () {
        _channel?.sink.close();
        _onClose(4000, 'Message reconnect timeout');
      },
    );
  }

  void _setStatus(WebSocketStatus s) {
    if (_status == s) return;
    _status = s;
    emit('status', [s]);
  }

  /// Send raw bytes over the WebSocket.
  void send(Uint8List data) {
    if (_status != WebSocketStatus.connected) return;
    _channel?.sink.add(data);
  }

  /// Disconnect from the server (will not reconnect).
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
  }

  @override
  void destroy() {
    _destroyed = true;
    _reconnectTimer?.cancel();
    _messageReconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    emit('destroy', []);
    super.destroy();
  }
}
