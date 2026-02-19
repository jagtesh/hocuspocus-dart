/// Dart port of @hocuspocus/provider OutgoingMessages/SyncStepTwoMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/SyncStepTwoMessage.ts
library;

import 'dart:typed_data';

import 'package:yjs_dart/yjs_dart.dart' as encoding;

import '../outgoing_message.dart';
import '../types.dart';

/// Sends a Yjs SyncStep2 (full state as update) to the server.
///
/// Mirrors: `SyncStepTwoMessage` in OutgoingMessages/SyncStepTwoMessage.ts
class SyncStepTwoMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.sync;

  SyncStepTwoMessage({
    required String documentName,
    required Uint8List update,
  }) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.sync.value);
    // SyncStep2 = type 1 in y-protocols/sync
    encoding.writeVarUint(encoder, 1);
    encoding.writeVarUint8Array(encoder, update);
  }
}
