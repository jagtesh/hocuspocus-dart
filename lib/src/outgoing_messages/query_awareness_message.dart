/// Dart port of @hocuspocus/provider OutgoingMessages/QueryAwarenessMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/QueryAwarenessMessage.ts
library;

import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;

import '../outgoing_message.dart';
import '../types.dart';

/// Requests awareness states from the server.
///
/// Mirrors: `QueryAwarenessMessage` in OutgoingMessages/QueryAwarenessMessage.ts
class QueryAwarenessMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.queryAwareness;

  QueryAwarenessMessage({required String documentName}) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.queryAwareness.value);
  }
}
