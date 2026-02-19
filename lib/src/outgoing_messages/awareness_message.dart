/// Dart port of @hocuspocus/provider OutgoingMessages/AwarenessMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/AwarenessMessage.ts
library;

import 'package:yjs_dart/yjs_dart.dart' as encoding;
import 'package:yjs_dart/yjs_dart.dart' show encodeAwarenessUpdate;

import '../outgoing_message.dart';
import '../types.dart';

/// Sends awareness state updates to the server.
///
/// Mirrors: `AwarenessMessage` in OutgoingMessages/AwarenessMessage.ts
class AwarenessMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.awareness;

  AwarenessMessage({
    required String documentName,
    required dynamic awareness,
    required List<int> clients,
  }) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.awareness.value);
    encoding.writeVarUint8Array(
      encoder,
      encodeAwarenessUpdate(awareness, clients),
    );
  }
}
