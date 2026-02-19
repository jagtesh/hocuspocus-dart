/// Tests for hocuspocus-dart: MessageType, IncomingMessage, HocuspocusProvider.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:hocuspocus_dart/hocuspocus_dart.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yjs_dart/src/lib0/encoding.dart' as encoding;
import 'package:yjs_dart/src/utils/doc.dart' show Doc;

// ---------------------------------------------------------------------------
// Minimal fake WebSocket provider for tests that need send-tracking.
// ---------------------------------------------------------------------------

class _FakeWsProvider extends HocuspocusProviderWebsocket {
  final List<Uint8List> sent = [];

  _FakeWsProvider()
      : super(HocuspocusProviderWebsocketConfiguration(url: 'ws://test'));

  @override
  Future<void> connect() async {} // never connect to a real server in tests

  @override
  void send(Uint8List data) => sent.add(data);
}

// ---------------------------------------------------------------------------
// Mock WebSocketChannel for timeout testing.
// ---------------------------------------------------------------------------

class _MockWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  @override
  final Stream<dynamic> stream;
  @override
  final WebSocketSink sink;
  @override
  final Future<void> ready;

  _MockWebSocketChannel({
    Stream<dynamic>? stream,
    WebSocketSink? sink,
    required this.ready,
  })  : stream = stream ?? const Stream.empty(),
        sink = sink ?? _MockWebSocketSink();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class _MockWebSocketSink implements WebSocketSink {
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<dynamic> stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}
  @override
  Future get done => Future.value();
}

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

    test('peekVarString reads without consuming bytes', () {
      final enc = encoding.createEncoder();
      encoding.writeVarString(enc, 'my-document');
      final bytes = encoding.toUint8Array(enc);

      final msg = IncomingMessage(bytes);
      final peeked = msg.peekVarString();
      expect(peeked, equals('my-document'));
      // Decoder position unchanged — read again returns same value
      expect(msg.readVarString(), equals('my-document'));
    });
  });

  // ---------------------------------------------------------------------------
  // Outgoing messages
  // ---------------------------------------------------------------------------
  group('OutgoingMessages', () {
    test('AuthenticationMessage serializes documentName + auth type + token',
        () {
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

    test('StatelessMessage serializes documentName + stateless type + payload',
        () {
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

    test(
        'QueryAwarenessMessage serializes documentName + queryAwareness type',
        () {
      final msg = QueryAwarenessMessage(documentName: 'test-doc');
      final bytes = msg.toUint8Array();
      final incoming = IncomingMessage(bytes);
      expect(incoming.readVarString(), equals('test-doc'));
      expect(incoming.readVarUint(), equals(MessageType.queryAwareness.value));
    });

    test('CloseMessage serializes documentName + close type', () {
      final msg = CloseMessage(documentName: 'test-doc');
      final bytes = msg.toUint8Array();
      final incoming = IncomingMessage(bytes);
      expect(incoming.readVarString(), equals('test-doc'));
      expect(incoming.readVarUint(), equals(MessageType.close.value));
    });
  });

  // ---------------------------------------------------------------------------
  // HocuspocusProviderWebsocketConfiguration
  // ---------------------------------------------------------------------------
  group('HocuspocusProviderWebsocketConfiguration', () {
    test('resolvedUrl returns url unchanged when no parameters', () {
      final config = HocuspocusProviderWebsocketConfiguration(
        url: 'ws://localhost:1234',
      );
      expect(config.resolvedUrl, equals('ws://localhost:1234'));
    });

    test('resolvedUrl strips trailing slash', () {
      final config = HocuspocusProviderWebsocketConfiguration(
        url: 'ws://localhost:1234/',
      );
      expect(config.resolvedUrl, equals('ws://localhost:1234'));
    });

    test('resolvedUrl appends encoded query parameters', () {
      final config = HocuspocusProviderWebsocketConfiguration(
        url: 'ws://localhost:1234',
        parameters: {'room': 'my doc', 'v': '2'},
      );
      final resolved = config.resolvedUrl;
      expect(resolved, startsWith('ws://localhost:1234?'));
      expect(resolved, contains('room=my%20doc'));
      expect(resolved, contains('v=2'));
    });
  });

  // ---------------------------------------------------------------------------
  // HocuspocusProviderWebsocket - Connect Timeout
  // ---------------------------------------------------------------------------
  group('HocuspocusProviderWebsocket', () {
    test('connect succeeds if ready completes within timeout', () async {
      final completer = Completer<void>();
      final config = HocuspocusProviderWebsocketConfiguration(
        url: 'ws://localhost:1234',
        connectTimeout: 100,
      );
      
      final provider = HocuspocusProviderWebsocket(
        config,
        socketFactory: (uri) => _MockWebSocketChannel(ready: completer.future),
      );

      // Start connecting
      final future = provider.connect();
      
      // Complete ready immediately
      completer.complete();
      
      await future;
      expect(provider.status, equals(WebSocketStatus.connected));
      
      // Cleanup
      provider.destroy();
    });

    test('connect fails if ready times out', () async {
      final completer = Completer<void>();
      final config = HocuspocusProviderWebsocketConfiguration(
        url: 'ws://localhost:1234',
        connectTimeout: 50, // Short timeout
      );
      
      final provider = HocuspocusProviderWebsocket(
        config,
        socketFactory: (uri) => _MockWebSocketChannel(ready: completer.future),
      );

      // Start connecting
      await provider.connect();
      
      // connection attempt should have failed and called _onClose
      expect(provider.status, equals(WebSocketStatus.disconnected));
      
      provider.destroy();
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
          url: 'ws://localhost:1234',
          autoConnect: false,
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
          url: 'ws://localhost:1234',
          autoConnect: false,
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
          url: 'ws://localhost:1234',
          autoConnect: false,
        ),
      );
      expect(provider.synced, isFalse);
      provider.destroy();
    });

    test('synced setter emits synced event', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
        ),
      );
      var emitted = false;
      provider.on('synced', (_) => emitted = true);
      provider.synced = true;
      expect(emitted, isTrue);
      provider.destroy();
    });

    test('synced setter also emits sync alias event', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
        ),
      );
      var syncEmitted = false;
      provider.on('sync', (_) => syncEmitted = true);
      provider.synced = true;
      expect(syncEmitted, isTrue);
      provider.destroy();
    });

    test('incrementUnsyncedChanges / decrementUnsyncedChanges', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
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
          url: 'ws://localhost:1234',
          autoConnect: false,
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
          url: 'ws://localhost:1234',
          autoConnect: false,
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

    test('permissionDeniedHandler resets isAuthenticated', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
        ),
      );
      // Manually set authenticated state
      provider.isAuthenticated = true;
      provider.permissionDeniedHandler('denied');
      expect(provider.isAuthenticated, isFalse);
      provider.destroy();
    });

    test('authenticatedHandler sets isAuthenticated and emits authenticated',
        () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
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

    test('sendToken is a no-op when token is null', () {
      final fake = _FakeWsProvider();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          websocketProvider: fake,
          autoConnect: false,
          // token: null (default)
        ),
      );
      final countBefore = fake.sent.length;
      provider.sendToken();
      expect(fake.sent.length, equals(countBefore),
          reason: 'No message should be sent when token is null');
      provider.destroy();
    });

    test('sendToken sends message when token is set', () async {
      final fake = _FakeWsProvider();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          websocketProvider: fake,
          autoConnect: false,
          token: () => 'secret',
        ),
      );
      final countBefore = fake.sent.length;
      await provider.sendToken();
      expect(fake.sent.length, greaterThan(countBefore));
      // Verify the sent bytes decode as an AuthenticationMessage
      final incoming = IncomingMessage(fake.sent.last);
      expect(incoming.readVarString(), equals('test')); // documentName
      expect(incoming.readVarUint(), equals(MessageType.auth.value));
      expect(incoming.readVarString(), equals('secret')); // token
      provider.destroy();
    });

    test('sendToken awaits async token', () async {
      final fake = _FakeWsProvider();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          websocketProvider: fake,
          autoConnect: false,
          token: () async {
            await Future.delayed(Duration(milliseconds: 10));
            return 'async-secret';
          },
        ),
      );
      final countBefore = fake.sent.length;
      await provider.sendToken();
      expect(fake.sent.length, greaterThan(countBefore));
      
      final incoming = IncomingMessage(fake.sent.last);
      expect(incoming.readVarString(), equals('test'));
      expect(incoming.readVarUint(), equals(MessageType.auth.value));
      expect(incoming.readVarString(), equals('async-secret'));
      provider.destroy();
    });

    test('outgoingMessage event is emitted on send', () {
      final fake = _FakeWsProvider();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          websocketProvider: fake,
          autoConnect: false,
          token: () => 'tok',
        ),
      );
      var outgoingFired = false;
      provider.on('outgoingMessage', (_) => outgoingFired = true);
      provider.sendStateless('hello');
      expect(outgoingFired, isTrue);
      provider.destroy();
    });

    test('destroy cleans up without throwing', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
        ),
      );
      expect(() => provider.destroy(), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // Bug 1 — SyncStepOneMessage encoding regression
  //
  // The bug: the sync payload (state vector) was wrapped in writeVarUint8Array
  // which prepends a length byte. The server reads the sub-tag directly after
  // the outer MessageType.sync byte, so it saw the length as tag 3 (unknown).
  //
  // Fix: write via writeSyncStep1(encoder, doc) directly — no extra prefix.
  // ---------------------------------------------------------------------------
  group('SyncStepOneMessage encoding (Bug 1)', () {
    test('empty doc produces correct 12-byte SyncStep1 message', () {
      // Real bytes observed from server: [7, "default", 0, 0, 1, 0]
      // Breakdown:
      //   7        = length of "default" as varuint
      //   'd','e','f','a','u','l','t' = document name
      //   0        = MessageType.sync
      //   0        = messageSyncStep1 sub-tag
      //   1        = varuint(1): state vector has 1 byte following
      //   0        = varuint(0): 0 clients
      //
      // Total: 1 + 7 + 1 + 1 + 1 + 1 = 12 bytes
      final doc = Doc();
      final msg = SyncStepOneMessage(
        documentName: 'default',
        document: doc,
      );
      final bytes = msg.toUint8Array();

      // Must be exactly 12 bytes for an empty doc with name "default"
      expect(bytes.length, equals(12));

      // Parse and verify structure
      final incoming = IncomingMessage(bytes);
      expect(incoming.readVarString(), equals('default')); // doc name
      expect(incoming.readVarUint(), equals(MessageType.sync.value)); // 0

      // Sub-tag: must be 0 (messageSyncStep1), NOT a length byte
      final subTag = incoming.readVarUint();
      expect(subTag, equals(0),
          reason:
              'SyncStep1 sub-tag must be 0; if it is 3, the length prefix bug is back');
    });

    test('SyncStep1 sub-tag is always 0 regardless of state vector content',
        () {
      // Even after writing some content, the first byte of the sync payload
      // must always be the sub-tag 0 (messageSyncStep1), not a length.
      final doc = Doc();
      final m = doc.getMap<dynamic>('x')!;
      doc.transact((_) => m.set('key', 'value'));

      final msg = SyncStepOneMessage(
        documentName: 'room',
        document: doc,
      );
      final bytes = msg.toUint8Array();
      final incoming = IncomingMessage(bytes);
      incoming.readVarString(); // skip doc name
      incoming.readVarUint(); // skip outer MessageType.sync

      final subTag = incoming.readVarUint();
      expect(subTag, equals(0),
          reason: 'SyncStep1 sub-tag must be 0 (messageSyncStep1)');
    });

    test('SyncStepTwo sub-tag is always 1', () {
      // SyncStepTwoMessage encodes a full state-as-update.
      // The update payload for an empty doc is [0, 0] (0-length structs + 0-length ds).
      final msg = SyncStepTwoMessage(
        documentName: 'room',
        update: Uint8List.fromList([0, 0]),
      );
      final bytes = msg.toUint8Array();
      final incoming = IncomingMessage(bytes);
      incoming.readVarString(); // doc name
      incoming.readVarUint(); // MessageType.sync
      expect(incoming.readVarUint(), equals(1),
          reason: 'SyncStep2 sub-tag must be 1 (messageSyncStep2)');
    });

    test('UpdateMessage sub-tag is always 2', () {
      final msg = UpdateMessage(
        documentName: 'room',
        update: Uint8List.fromList([1, 0, 0]),
      );
      final bytes = msg.toUint8Array();
      final incoming = IncomingMessage(bytes);
      incoming.readVarString(); // doc name
      incoming.readVarUint(); // MessageType.sync
      expect(incoming.readVarUint(), equals(2),
          reason: 'Update sub-tag must be 2 (messageYjsUpdate)');
    });
  });

  // ---------------------------------------------------------------------------
  // Bug 2 — Observable.emit spreads args as positional params (not a list)
  //
  // Fixed: all provider.on() callbacks now receive the value directly, not
  // through args[0]. The synced setter test above already exercises this in
  // part; this section verifies the listener receives the correct typed value.
  // ---------------------------------------------------------------------------
  group('Observable callback arity (Bug 2)', () {
    test('synced event listener receives OnSyncedParams directly', () {
      final fake = _FakeWsProvider();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          websocketProvider: fake,
          autoConnect: false,
        ),
      );

      OnSyncedParams? received;
      provider.on('synced', (dynamic p) {
        // Args spread as positional: p IS the OnSyncedParams, not a list
        received = p as OnSyncedParams;
      });

      provider.synced = true;
      expect(received, isNotNull);
      expect(received!.state, isTrue);
      provider.destroy();
    });

    test('stateless event listener receives OnStatelessParams directly', () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
        ),
      );

      String? payload;
      provider.on('stateless', (dynamic p) {
        payload = (p as OnStatelessParams).payload;
      });

      provider.receiveStateless('hello');
      expect(payload, equals('hello'));
      provider.destroy();
    });

    test('authenticated event listener receives OnAuthenticatedParams directly',
        () {
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'test',
          url: 'ws://localhost:1234',
          autoConnect: false,
        ),
      );

      String? scope;
      provider.on('authenticated', (dynamic p) {
        scope = (p as OnAuthenticatedParams).scope;
      });

      provider.authenticatedHandler('read-write');
      expect(scope, equals('read-write'));
      provider.destroy();
    });
  });

  // ---------------------------------------------------------------------------
  // Bug 3 — _documentUpdateHandler must accept 4 args
  //
  // doc.emit('update', [update, origin, doc, transaction]) fires 4 positional
  // args. The old handler only accepted 2 which raised NoSuchMethodError.
  // ---------------------------------------------------------------------------
  group('documentUpdateHandler arity (Bug 3)', () {
    test('local doc changes send UpdateMessage without throwing', () {
      final fake = _FakeWsProvider();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'doc',
          websocketProvider: fake,
          autoConnect: false,
        ),
      );

      // Trigger a local doc update — this calls _documentUpdateHandler via
      // doc.on('update', _documentUpdateHandler)
      final m = provider.document.getMap<dynamic>('data')!;
      expect(() => provider.document.transact((_) => m.set('k', 'v')),
          returnsNormally,
          reason: 'documentUpdateHandler must accept 4 args without throwing');

      provider.destroy();
    });

    test('local update is sent as UpdateMessage with sync sub-tag 2', () {
      final fake = _FakeWsProvider();
      final provider = HocuspocusProvider(
        HocuspocusProviderConfiguration(
          name: 'doc',
          websocketProvider: fake,
          autoConnect: false,
        ),
      );

      // Connect so outgoing messages are sent
      final sentBefore = fake.sent.length;

      final m = provider.document.getMap<dynamic>('data')!;
      provider.document.transact((_) => m.set('k', 'v'));

      // An UpdateMessage should have been sent
      expect(fake.sent.length, greaterThan(sentBefore),
          reason: 'UpdateMessage should be sent for local changes');

      // The last sent message must be an UpdateMessage (sync sub-tag 2)
      final incoming = IncomingMessage(fake.sent.last);
      expect(incoming.readVarString(), equals('doc')); // doc name
      expect(incoming.readVarUint(), equals(MessageType.sync.value));
      expect(incoming.readVarUint(), equals(2),
          reason: 'UpdateMessage sub-tag must be 2');

      provider.destroy();
    });
  });

  // ---------------------------------------------------------------------------
  // Integration: real message format validation
  //
  // Based on actual bytes observed during the debugging session.
  // ---------------------------------------------------------------------------
  group('Integration: real message format', () {
    test('SyncStep1 for "default" doc is reproducible and 12 bytes', () {
      // The server rejects any SyncStep1 that isn't exactly this format.
      // Observed real traffic: [7, 100, 101, 102, 97, 117, 108, 116, 0, 0, 1, 0]
      final doc = Doc();
      final msg =
          SyncStepOneMessage(documentName: 'default', document: doc);
      final bytes = msg.toUint8Array();
      expect(bytes.length, equals(12));
      expect(bytes[0], equals(7),  reason: 'varuint length of "default"');
      expect(bytes[8], equals(0),  reason: 'MessageType.sync = 0');
      expect(bytes[9], equals(0),  reason: 'messageSyncStep1 sub-tag = 0');
      expect(bytes[10], equals(1), reason: 'state vector length = 1 byte');
      expect(bytes[11], equals(0), reason: 'state vector = varuint(0) = 0 clients');
    });

  });
}
