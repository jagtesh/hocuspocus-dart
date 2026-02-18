/// Dart port of @hocuspocus/provider OutgoingMessages/SyncStepOneMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/SyncStepOneMessage.ts
library;

import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;
import 'package:yjs_dart/src/protocols/sync.dart' show writeSyncStep1;

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
    // writeSyncStep1 takes a lib0 encoding.Encoder and writes the state vector
    final syncEncoder = encoding.createEncoder();
    writeSyncStep1(syncEncoder, document);
    encoding.writeVarUint8Array(encoder, encoding.toUint8Array(syncEncoder));
  }
}
