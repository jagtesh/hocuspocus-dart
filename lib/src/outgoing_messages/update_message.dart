/// Dart port of @hocuspocus/provider OutgoingMessages/UpdateMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/UpdateMessage.ts
library;

import 'dart:typed_data';

import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;

import '../outgoing_message.dart';
import '../types.dart';

/// Sends a Yjs document update to the server.
///
/// Mirrors: `UpdateMessage` in OutgoingMessages/UpdateMessage.ts
class UpdateMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.sync;

  UpdateMessage({
    required String documentName,
    required Uint8List update,
  }) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.sync.value);
    // Update = type 2 in y-protocols/sync
    encoding.writeVarUint(encoder, 2);
    encoding.writeVarUint8Array(encoder, update);
  }
}
