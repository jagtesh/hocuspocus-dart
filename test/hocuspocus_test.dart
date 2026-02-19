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
}
