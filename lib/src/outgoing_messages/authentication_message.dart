/// Dart port of @hocuspocus/provider OutgoingMessages/AuthenticationMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/OutgoingMessages/AuthenticationMessage.ts
library;

import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;

import '../outgoing_message.dart';
import '../types.dart';

/// Sends an authentication token to the server.
///
/// Mirrors: `AuthenticationMessage` in OutgoingMessages/AuthenticationMessage.ts
class AuthenticationMessage extends OutgoingMessage {
  @override
  MessageType get type => MessageType.auth;

  AuthenticationMessage({
    required String documentName,
    required String token,
  }) {
    encoding.writeVarString(encoder, documentName);
    encoding.writeVarUint(encoder, MessageType.auth.value);
    encoding.writeVarString(encoder, token);
  }
}
