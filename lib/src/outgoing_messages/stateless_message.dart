/// Dart port of @hocuspocus/provider OutgoingMessages/StatelessMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/StatelessMessage.ts
library;

import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;

import '../outgoing_message.dart';
import '../types.dart';

/// Sends a stateless (arbitrary string) message to the server.
///
/// Mirrors: `StatelessMessage` in OutgoingMessages/StatelessMessage.ts
class StatelessMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.stateless;

  StatelessMessage({
    required String documentName,
    required String payload,
  }) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.stateless.value);
    encoding.writeVarString(encoder, payload);
  }
}
