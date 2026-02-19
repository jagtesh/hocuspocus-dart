/// Dart port of @hocuspocus/provider OutgoingMessages/SyncStepOneMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/SyncStepOneMessage.ts
library;

import 'package:yjs_dart/yjs_dart.dart' as encoding;
import 'package:yjs_dart/yjs_dart.dart' show writeSyncStep1;

import '../outgoing_message.dart';
import '../types.dart';

/// Sends a Yjs SyncStep1 (state vector) to the server.
///
/// Mirrors: `SyncStepOneMessage` in OutgoingMessages/SyncStepOneMessage.ts
class SyncStepOneMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.sync;

  SyncStepOneMessage({
    required String documentName,
    required dynamic document,
  }) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.sync.value);
    // writeSyncStep1 writes [messageSyncStep1, stateVector...] — must be written
    // directly (no length prefix) so the server sees the sub-tag immediately.
    writeSyncStep1(encoder, document);
  }
}
