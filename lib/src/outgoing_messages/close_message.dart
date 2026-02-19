/// Dart port of @hocuspocus/provider OutgoingMessages/CloseMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/CloseMessage.ts
library;

import 'package:yjs_dart/yjs_dart.dart' as encoding;

import '../outgoing_message.dart';
import '../types.dart';

/// Asks the server to close the connection for this document.
///
/// Mirrors: `CloseMessage` in OutgoingMessages/CloseMessage.ts
class CloseMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.close;

  CloseMessage({required String documentName}) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.close.value);
  }
}
