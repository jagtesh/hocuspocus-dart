/// Dart port of @hocuspocus/provider MessageReceiver.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/MessageReceiver.ts
library;

import 'package:yjs_dart/yjs_dart.dart' as decoding;
import 'package:yjs_dart/yjs_dart.dart'
    show
        applyAwarenessUpdate,
        encodeAwarenessUpdate,
        readSyncMessage,
        messageSyncStep2;
import 'package:yjs_dart/yjs_dart.dart' show Doc;

import 'incoming_message.dart';
import 'types.dart';

/// Dispatches an incoming binary message to the appropriate handler.
///
/// Mirrors: `MessageReceiver` in MessageReceiver.ts
class MessageReceiver {
  final IncomingMessage message;

  MessageReceiver(this.message);

  /// Apply the message to [provider].
  ///
  /// If [emitSynced] is true, emits the 'synced' event when SyncStep2 is received.
  void apply(dynamic provider, bool emitSynced) {
    final msgTypeInt = message.readVarUint();
    final type = MessageType.fromValue(msgTypeInt);
    final emptyMessageLength = message.length();
    
    // ignore: avoid_print
    // print('DEBUG: MessageReceiver apply type=$type ($msgTypeInt)');

    switch (type) {
      case MessageType.sync:
        _applySyncMessage(provider, emitSynced);
        break;

      case MessageType.awareness:
        _applyAwarenessMessage(provider);
        break;

      case MessageType.auth:
        _applyAuthMessage(provider);
        break;

      case MessageType.queryAwareness:
        _applyQueryAwarenessMessage(provider);
        break;

      case MessageType.stateless:
        final payload = decoding.readVarString(message.decoder);
        // ignore: avoid_dynamic_calls
        provider.receiveStateless(payload);
        break;

      case MessageType.syncStatus:
        final applied = decoding.readVarInt(message.decoder) == 1;
        _applySyncStatusMessage(provider, applied);
        break;

      case MessageType.close:
        final reason = decoding.readVarString(message.decoder);
        // ignore: avoid_dynamic_calls
        provider.onClose();
        // ignore: avoid_dynamic_calls
        provider.emitClose(reason);
        break;

      case MessageType.ping:
        // Reply with pong
        message.writeVarUint(MessageType.pong.value);
        break;

      case MessageType.pong:
        // Nothing to do
        break;
    }

    // If a reply was written, send it back
    if (message.length() > emptyMessageLength + 1) {
      // ignore: avoid_dynamic_calls
      provider.sendRaw(message.toUint8Array());
    }
  }

  void _applySyncMessage(dynamic provider, bool emitSynced) {
    message.writeVarUint(MessageType.sync.value);

    // ignore: avoid_dynamic_calls
    final doc = provider.document as Doc;
    // print('DEBUG: MessageReceiver _applySyncMessage doc=${doc.guid}');
    final syncMessageType = readSyncMessage(
      message.decoder,
      message.encoder,
      doc,
      provider,
    );

    if (emitSynced && syncMessageType == messageSyncStep2) {
      // ignore: avoid_dynamic_calls
      provider.synced = true;
    }
  }

  void _applySyncStatusMessage(dynamic provider, bool applied) {
    if (applied) {
      // ignore: avoid_dynamic_calls
      provider.decrementUnsyncedChanges();
    }
  }

  void _applyAwarenessMessage(dynamic provider) {
    // ignore: avoid_dynamic_calls
    final awareness = provider.awareness;
    if (awareness == null) return;

    final update = message.readVarUint8Array();
    applyAwarenessUpdate(awareness, update, provider);
  }

  void _applyAuthMessage(dynamic provider) {
    // Auth message format (hocuspocus-specific, superset of y-protocols/auth):
    //   0 = permission denied  → string reason
    //   1 = authenticated      → string scope
    //   2 = token required     → (no payload)
    final authType = decoding.readVarUint(message.decoder);
    switch (authType) {
      case 0: // permission denied
        final reason = decoding.readVarString(message.decoder);
        // ignore: avoid_dynamic_calls
        provider.permissionDeniedHandler(reason);
        break;
      case 1: // authenticated
        final scope = decoding.readVarString(message.decoder);
        // ignore: avoid_dynamic_calls
        provider.authenticatedHandler(scope);
        break;
      case 2: // token required
        // ignore: avoid_dynamic_calls
        provider.sendToken();
        break;
    }
  }

  void _applyQueryAwarenessMessage(dynamic provider) {
    // ignore: avoid_dynamic_calls
    final awareness = provider.awareness;
    if (awareness == null) return;

    // ignore: avoid_dynamic_calls
    final clients = List<int>.from(awareness.getStates().keys);
    message.writeVarUint(MessageType.awareness.value);
    message.writeVarUint8Array(encodeAwarenessUpdate(awareness, clients));
  }
}
