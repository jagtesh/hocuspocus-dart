/// Tests for hocuspocus-dart: MessageType, IncomingMessage, HocuspocusProvider.
library;

import 'dart:typed_data';

import 'package:hocuspocus_dart/hocuspocus_dart.dart';
import 'package:test/test.dart';
import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;
import 'package:yjs_dart/src/utils/doc.dart' show Doc;

void main() {
  // ---------------------------------------------------------------------------
  // MessageType
  // ---------------------------------------------------------------------------
  group('MessageType', () {
    test('values match hocuspocus protocol', () {
      expect(MessageType.sync.value, equals(0));
      expect(MessageType.awareness.value, equals(1));
      expect(MessageType.auth.value, equals(2));
      expect(MessageType.queryAwareness.value, equals(3));
      expect(MessageType.stateless.value, equals(5));
      expect(MessageType.close.value, equals(7));
      expect(MessageType.syncStatus.value, equals(8));
      expect(MessageType.ping.value, equals(9));
      expect(MessageType.pong.value, equals(10));
    });

    test('fromValue round-trips', () {
      for (final type in MessageType.values) {
        expect(MessageType.fromValue(type.value), equals(type));
      }
    });

    test('fromValue throws for unknown value', () {
      expect(() => MessageType.fromValue(99), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  // IncomingMessage
  // ---------------------------------------------------------------------------
  group('IncomingMessage', () {
    test('readVarUint reads what was written', () {
      final enc = encoding.createEncoder();
      encoding.writeVarUint(enc, 42);
      encoding.writeVarUint(enc, 7);
      final bytes = encoding.toUint8Array(enc);

      final msg = IncomingMessage(bytes);
      expect(msg.readVarUint(), equals(42));
      expect(msg.readVarUint(), equals(7));
    });

    test('readVarString reads what was written', () {
      final enc = encoding.createEncoder();
      encoding.writeVarString(enc, 'my-document');
      final bytes = encoding.toUint8Array(enc);

      final msg = IncomingMessage(bytes);
      expect(msg.readVarString(), equals('my-document'));
    });

    test('writeVarUint to reply encoder and toUint8Array', () {
      final msg = IncomingMessage(Uint8List(0));
      msg.writeVarUint(99);
      final reply = msg.toUint8Array();
      expect(reply, isNotEmpty);

      // Verify the written value
      final replyMsg = IncomingMessage(reply);
      expect(replyMsg.readVarUint(), equals(99));
    });

    test('length() tracks written bytes', () {
      final msg = IncomingMessage(Uint8List(0));
      final before = msg.length();
      msg.writeVarUint(1);
      expect(msg.length(), greaterThan(before));
    });
  });

  // ---------------------------------------------------------------------------
  // Outgoing messages
  // ---------------------------------------------------------------------------
  group('OutgoingMessages', () {
    test('AuthenticationMessage serializes documentName + auth type + token', () {
      final msg = AuthenticationMessage(
        documentName: 'test-doc',
        token: 'my-token',
      );
      final bytes = msg.toUint8Array();
      expect(bytes, isNotEmpty);

      // Verify structure: documentName, MessageType.auth, token
      final incoming = IncomingMessage(bytes);
      expect(incoming.readVarString(), equals('test-doc'));
      expect(incoming.readVarUint(), equals(MessageType.auth.value));
      expect(incoming.readVarString(), equals('my-token'));
    });

    test('StatelessMessage serializes documentName + stateless type + payload', () {
      final msg = StatelessMessage(
        documentName: 'test-doc',
        payload: 'hello world',
      );
      final bytes = msg.toUint8Array();
      final incoming = IncomingMessage(bytes);
      expect(incoming.readVarString(), equals('test-doc'));
      expect(incoming.readVarUint(), equals(MessageType.stateless.value));
      expect(incoming.readVarString(), equals('hello world'));
    });

    test('QueryAwarenessMessage serializes documentName + queryAwareness type', () {
      final msg = QueryAwarenessMessage(documentName: 'test-doc');
      final bytes = msg.toUint8Array();
      final incoming = IncomingMessage(bytes);
      expect(incoming.readVarString(), equals('test-doc'));
      expect(incoming.readVarUint(), equals(MessageType.queryAwareness.value));
    });
  });

  // ---------------------------------------------------------------------------
  // HocuspocusProvider
  // ---------------------------------------------------------------------------
  group('HocuspocusProvider', () {
    test('creates Doc and Awareness automatically', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      expect(provider.document, isNotNull);
      expect(provider.awareness, isNotNull);
      provider.destroy();
    });

    test('uses provided document', () {
      final doc = Doc();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
          document: doc,
        ),
      );
      expect(provider.document, same(doc));
      provider.destroy();
    });

    test('synced starts false', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      expect(provider.synced, isFalse);
      provider.destroy();
    });

    test('synced setter emits synced event', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      var emitted = false;
      provider.on('synced', (_) => emitted = true);
      provider.synced = true;
      expect(emitted, isTrue);
      provider.destroy();
    });

    test('incrementUnsyncedChanges / decrementUnsyncedChanges', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      expect(provider.hasUnsyncedChanges, isFalse);
      provider.incrementUnsyncedChanges();
      expect(provider.hasUnsyncedChanges, isTrue);
      provider.decrementUnsyncedChanges();
      expect(provider.hasUnsyncedChanges, isFalse);
      provider.destroy();
    });

    test('receiveStateless emits stateless event', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      String? received;
      provider.on('stateless', (dynamic p) {
        received = (p as OnStatelessParams).payload;
      });
      provider.receiveStateless('ping-payload');
      expect(received, equals('ping-payload'));
      provider.destroy();
    });

    test('permissionDeniedHandler emits authenticationFailed', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      String? reason;
      provider.on('authenticationFailed', (dynamic p) {
        reason = (p as OnAuthenticationFailedParams).reason;
      });
      provider.permissionDeniedHandler('not authorized');
      expect(reason, equals('not authorized'));
      provider.destroy();
    });

    test('authenticatedHandler sets isAuthenticated and emits authenticated', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      String? scope;
      provider.on('authenticated', (dynamic p) {
        scope = (p as OnAuthenticatedParams).scope;
      });
      provider.authenticatedHandler('read-write');
      expect(provider.isAuthenticated, isTrue);
      expect(provider.authorizedScope, equals('read-write'));
      expect(scope, equals('read-write'));
      provider.destroy();
    });

    test('destroy cleans up without throwing', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234', autoConnect: false,
        ),
      );
      expect(() => provider.destroy(), returnsNormally);
    });
  });
}
