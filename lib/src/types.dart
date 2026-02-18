/// Dart port of @hocuspocus/provider types.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/types.ts
library;

/// Message types used in the hocuspocus binary protocol.
///
/// Mirrors: `MessageType` enum in types.ts
enum MessageType {
  sync(0),
  awareness(1),
  auth(2),
  queryAwareness(3),
  stateless(5),
  close(7),
  syncStatus(8),
  ping(9),
  pong(10);

  final int value;
  const MessageType(this.value);

  static MessageType fromValue(int v) =>
      MessageType.values.firstWhere((e) => e.value == v,
          orElse: () => throw ArgumentError('Unknown MessageType: $v'));
}

/// WebSocket connection status.
///
/// Mirrors: `WebSocketStatus` enum in types.ts
enum WebSocketStatus {
  connecting,
  connected,
  disconnected,
}

/// Authorized scope returned by the server after authentication.
typedef AuthorizedScope = String; // 'read-write' | 'readonly'

// ---------------------------------------------------------------------------
// Callback parameter types
// ---------------------------------------------------------------------------

class OnAuthenticatedParams {
  final AuthorizedScope scope;
  const OnAuthenticatedParams(this.scope);
}

class OnAuthenticationFailedParams {
  final String reason;
  const OnAuthenticationFailedParams(this.reason);
}

class OnOpenParams {
  final Object? event;
  const OnOpenParams(this.event);
}

class OnMessageParams {
  final Object? event;
  final Object? message;
  const OnMessageParams(this.event, this.message);
}

class OnOutgoingMessageParams {
  final Object? message;
  const OnOutgoingMessageParams(this.message);
}

class OnStatusParams {
  final WebSocketStatus status;
  const OnStatusParams(this.status);
}

class OnSyncedParams {
  final bool state;
  const OnSyncedParams(this.state);
}

class OnUnsyncedChangesParams {
  final int number;
  const OnUnsyncedChangesParams(this.number);
}

class OnDisconnectParams {
  final int code;
  final String reason;
  const OnDisconnectParams(this.code, this.reason);
}

class OnCloseParams {
  final int code;
  final String reason;
  const OnCloseParams(this.code, this.reason);
}

class OnAwarenessUpdateParams {
  final List<Map<String, Object?>> states;
  const OnAwarenessUpdateParams(this.states);
}

class OnAwarenessChangeParams {
  final List<Map<String, Object?>> states;
  const OnAwarenessChangeParams(this.states);
}

class OnStatelessParams {
  final String payload;
  const OnStatelessParams(this.payload);
}
