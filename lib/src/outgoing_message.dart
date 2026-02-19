/// Dart port of @hocuspocus/provider OutgoingMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessage.ts
library;

import 'dart:typed_data';

import 'package:yjs_dart/yjs_dart.dart' as encoding;

import 'types.dart';

/// Base class for all outgoing messages.
///
/// Mirrors: `OutgoingMessage` in OutgoingMessage.ts
abstract class OutgoingMessage {
  final encoding.Encoder encoder = encoding.createEncoder();

  /// The message type (set by subclasses).
  MessageType? get type;

  /// Serialize to bytes for sending over WebSocket.
  Uint8List toUint8Array() => encoding.toUint8Array(encoder);
}
