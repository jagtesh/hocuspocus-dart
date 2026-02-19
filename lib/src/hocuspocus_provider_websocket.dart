/// Dart port of @hocuspocus/provider HocuspocusProviderWebsocket.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/HocuspocusProviderWebsocket.ts
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yjs_dart/yjs_dart.dart' show Observable;

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

  /// URL query parameters appended to the WebSocket URL.
  ///
  /// Keys and values are percent-encoded automatically.
  final Map<String, String> parameters;

  /// Timeout for connection attempts in milliseconds (default: 10000).
  final int connectTimeout;

  const HocuspocusProviderWebsocketConfiguration({
    required this.url,
    this.minDelay = 1000,
    this.maxDelay = 30000,
    this.maxRetries = -1,
    this.messageReconnectTimeout = 30000,
    this.parameters = const {},
    this.connectTimeout = 10000,
  });

  /// Returns the URL with [parameters] encoded as a query string.
  String get resolvedUrl {
    if (parameters.isEmpty) {
      // Strip trailing slash to match JS behaviour
      final u = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      return u;
    }
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final query = parameters.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$base?$query';
  }
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

  /// Messages queued while the connection is being established.
  final List<Uint8List> _messageQueue = [];

  final WebSocketChannel Function(Uri) _socketFactory;

  HocuspocusProviderWebsocket(
    this.configuration, {
    WebSocketChannel Function(Uri)? socketFactory,
  }) : _socketFactory = socketFactory ?? ((uri) => WebSocketChannel.connect(uri));

  WebSocketStatus get status => _status;

  bool get isConnected => _status == WebSocketStatus.connected;

  /// Connect to the WebSocket server.
  Future<void> connect() async {
    if (_destroyed) return;
    if (_status == WebSocketStatus.connecting ||
        _status == WebSocketStatus.connected) {
      return;
    }

    _setStatus(WebSocketStatus.connecting);

    try {
      _channel = _socketFactory(Uri.parse(configuration.resolvedUrl));
      await _channel!.ready
          .timeout(Duration(milliseconds: configuration.connectTimeout));
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
      onDone: () { 
        _onClose(1000, 'Connection closed');
      },
      onError: (e) {
        _onClose(1006, 'Error: $e');
      },
    );

    // Flush queued messages now that we're connected
    for (final msg in _messageQueue) {
      _channel?.sink.add(msg);
    }
    _messageQueue.clear();

    emit('open', []);
    emit('connect', []);
  }

  void _onClose(int code, String reason) {
    _subscription?.cancel();
    _subscription = null;
    _messageReconnectTimer?.cancel();
    _messageReconnectTimer = null;

    // Drop messages that were queued for a connection that never completed
    _messageQueue.clear();

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
  ///
  /// - If connected, sends immediately.
  /// - If connecting, queues the message and flushes on open.
  /// - If disconnected, drops the message.
  void send(Uint8List data) {
    if (_status == WebSocketStatus.connected) {
      _channel?.sink.add(data);
    } else if (_status == WebSocketStatus.connecting) {
      _messageQueue.add(data);
    }
    // Disconnected: drop silently (no server to receive it)
  }

  /// Disconnect from the server (will not reconnect).
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _messageQueue.clear();
    _channel?.sink.close();
  }

  @override
  void destroy() {
    _destroyed = true;
    _reconnectTimer?.cancel();
    _messageReconnectTimer?.cancel();
    _subscription?.cancel();
    _messageQueue.clear();
    _channel?.sink.close();
    emit('destroy', []);
    super.destroy();
  }
}
