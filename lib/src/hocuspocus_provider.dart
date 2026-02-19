/// Dart port of @hocuspocus/provider HocuspocusProvider.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/HocuspocusProvider.ts
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:yjs_dart/yjs_dart.dart'
    show Awareness, removeAwarenessStates, Doc, Observable;

import 'hocuspocus_provider_websocket.dart';
import 'incoming_message.dart';
import 'message_receiver.dart';
import 'outgoing_messages/authentication_message.dart';
import 'outgoing_messages/awareness_message.dart';
import 'outgoing_messages/close_message.dart';
import 'outgoing_messages/stateless_message.dart';
import 'outgoing_messages/sync_step_one_message.dart';
import 'outgoing_messages/update_message.dart';
import 'types.dart';

/// Configuration for [HocuspocusProvider].
class HocuspocusProviderConfiguration {
  /// The document name / room identifier.
  final String name;

  /// The Yjs document. Created automatically if not provided.
  final Doc? document;

  /// The Awareness instance. Created automatically if not provided.
  /// Pass `null` to disable awareness.
  final Awareness? awareness;

  /// Authentication token (or null for no auth).
  ///
  /// Can be a static string or a function returning a Future.
  final FutureOr<String?> Function()? token;

  /// Shared WebSocket provider. If not provided, one is created from [url].
  final HocuspocusProviderWebsocket? websocketProvider;

  /// WebSocket URL (required if [websocketProvider] is not provided).
  final String? url;

  /// Force sync interval in milliseconds, or null to disable.
  final int? forceSyncInterval;

  /// Connection timeout in milliseconds (default: 10000).
  final int connectTimeout;

  // Callbacks
  final void Function(OnAuthenticatedParams)? onAuthenticated;
  final void Function(OnAuthenticationFailedParams)? onAuthenticationFailed;
  final void Function(OnOpenParams)? onOpen;
  final void Function()? onConnect;
  final void Function(OnMessageParams)? onMessage;
  final void Function(OnOutgoingMessageParams)? onOutgoingMessage;
  final void Function(OnStatusParams)? onStatus;
  final void Function(OnSyncedParams)? onSynced;
  final void Function(OnDisconnectParams)? onDisconnect;
  final void Function(OnCloseParams)? onClose;
  final void Function()? onDestroy;
  final void Function(OnAwarenessUpdateParams)? onAwarenessUpdate;
  final void Function(OnAwarenessChangeParams)? onAwarenessChange;
  final void Function(OnStatelessParams)? onStateless;
  final void Function(OnUnsyncedChangesParams)? onUnsyncedChanges;

  /// Whether to automatically connect on construction (default: true).
  final bool autoConnect;

  const HocuspocusProviderConfiguration({
    required this.name,
    this.document,
    this.awareness,
    this.token,
    this.websocketProvider,
    this.url,
    this.forceSyncInterval,
    this.connectTimeout = 10000,
    this.autoConnect = true,
    this.onAuthenticated,
    this.onAuthenticationFailed,
    this.onOpen,
    this.onConnect,
    this.onMessage,
    this.onOutgoingMessage,
    this.onStatus,
    this.onSynced,
    this.onDisconnect,
    this.onClose,
    this.onDestroy,
    this.onAwarenessUpdate,
    this.onAwarenessChange,
    this.onStateless,
    this.onUnsyncedChanges,
  }) : assert(
          websocketProvider != null || url != null,
          'Either websocketProvider or url must be provided',
        );
}

/// The main hocuspocus provider — connects a Yjs document to a hocuspocus
/// WebSocket server and keeps it in sync.
///
/// Mirrors: `HocuspocusProvider` in HocuspocusProvider.ts
class HocuspocusProvider extends Observable<String> {
  final HocuspocusProviderConfiguration configuration;

  late final Doc document;
  late final Awareness? awareness;
  late final HocuspocusProviderWebsocket _wsProvider;

  bool _isSynced = false;
  bool isAuthenticated = false;
  AuthorizedScope? authorizedScope;
  int _unsyncedChanges = 0;
  bool _manageSocket = false;
  Timer? _forceSyncTimer;

  HocuspocusProvider(this.configuration) {
    // Set up document
    document = configuration.document ?? Doc();

    // Set up awareness
    if (configuration.awareness != null) {
      awareness = configuration.awareness;
    } else {
      awareness = Awareness(document);
    }

    // Set up WebSocket provider
    if (configuration.websocketProvider != null) {
      _wsProvider = configuration.websocketProvider!;
    } else {
      _manageSocket = true;
      _wsProvider = HocuspocusProviderWebsocket(
        HocuspocusProviderWebsocketConfiguration(
          url: configuration.url!,
          connectTimeout: configuration.connectTimeout,
        ),
      );
    }

    // Register callbacks
    // Note: Observable.emit calls Function.apply(f, args), so listeners receive
    // args spread as positional parameters (not as a list).
    if (configuration.onAuthenticated != null) {
      on('authenticated', (dynamic p) =>
          configuration.onAuthenticated!(p as OnAuthenticatedParams));
    }
    if (configuration.onAuthenticationFailed != null) {
      on('authenticationFailed', (dynamic p) =>
          configuration.onAuthenticationFailed!(
              p as OnAuthenticationFailedParams));
    }
    if (configuration.onSynced != null) {
      on('synced', (dynamic p) =>
          configuration.onSynced!(p as OnSyncedParams));
    }
    if (configuration.onDestroy != null) {
      on('destroy', (_) => configuration.onDestroy!());
    }
    if (configuration.onStateless != null) {
      on('stateless', (dynamic p) =>
          configuration.onStateless!(p as OnStatelessParams));
    }
    if (configuration.onUnsyncedChanges != null) {
      on('unsyncedChanges', (dynamic p) =>
          configuration.onUnsyncedChanges!(
              p as OnUnsyncedChangesParams));
    }
    if (configuration.onAwarenessUpdate != null) {
      on('awarenessUpdate', (dynamic p) =>
          configuration.onAwarenessUpdate!(
              p as OnAwarenessUpdateParams));
    }
    if (configuration.onAwarenessChange != null) {
      on('awarenessChange', (dynamic p) =>
          configuration.onAwarenessChange!(
              p as OnAwarenessChangeParams));
    }
    if (configuration.onMessage != null) {
      on('message', (dynamic p) =>
          configuration.onMessage!(p as OnMessageParams));
    }
    if (configuration.onOutgoingMessage != null) {
      on('outgoingMessage', (dynamic p) =>
          configuration.onOutgoingMessage!(
              p as OnOutgoingMessageParams));
    }

    // Awareness listeners
    awareness?.on('update', (dynamic changedArg, [dynamic origin]) {
      final changed = changedArg as Map;
      final added = (changed['added'] as List?)?.cast<int>() ?? [];
      final updated = (changed['updated'] as List?)?.cast<int>() ?? [];
      final removed = (changed['removed'] as List?)?.cast<int>() ?? [];
      final changedClients = [...added, ...updated, ...removed];
      _sendAwareness(changedClients);
      emit('awarenessUpdate',
          [OnAwarenessUpdateParams(_awarenessStatesArray())]);
    });

    awareness?.on('change', (dynamic _, [dynamic __]) {
      emit('awarenessChange',
          [OnAwarenessChangeParams(_awarenessStatesArray())]);
    });

    // Document update listener
    document.on('update', _documentUpdateHandler);

    // WebSocket listeners
    _wsProvider.on('open', _onWsOpen);
    _wsProvider.on('message', _onWsMessage);
    _wsProvider.on('close', _onWsClose);
    _wsProvider.on('connect', ([dynamic _]) => emit('connect', []));
    _wsProvider.on('disconnect', (dynamic code, [dynamic reason]) {
      emit('disconnect',
          [OnDisconnectParams(code as int, (reason ?? '') as String)]);
    });
    _wsProvider.on('status', (dynamic s, [dynamic __]) {
      emit('status', [OnStatusParams(s as WebSocketStatus)]);
    });
    _wsProvider.on('destroy', ([dynamic _]) => emit('destroy', []));

    // Force sync interval
    if (configuration.forceSyncInterval != null) {
      _forceSyncTimer = Timer.periodic(
        Duration(milliseconds: configuration.forceSyncInterval!),
        (_) => forceSync(),
      );
    }

    if (_manageSocket && configuration.autoConnect) {
      connect();
    }
  }

  // ---------------------------------------------------------------------------
  // Sync state
  // ---------------------------------------------------------------------------

  bool get synced => _isSynced;

  set synced(bool state) {
    if (_isSynced == state) return;
    _isSynced = state;
    if (state) {
      emit('synced', [OnSyncedParams(true)]);
      emit('sync', [OnSyncedParams(true)]); // backward-compat alias
    }
  }

  bool get hasUnsyncedChanges => _unsyncedChanges > 0;

  void incrementUnsyncedChanges() {
    _unsyncedChanges++;
    emit('unsyncedChanges', [OnUnsyncedChangesParams(_unsyncedChanges)]);
  }

  void decrementUnsyncedChanges() {
    if (_unsyncedChanges > 0) _unsyncedChanges--;
    if (_unsyncedChanges == 0) synced = true;
    emit('unsyncedChanges', [OnUnsyncedChangesParams(_unsyncedChanges)]);
  }

  void _resetUnsyncedChanges() {
    _unsyncedChanges = 1;
    emit('unsyncedChanges', [OnUnsyncedChangesParams(_unsyncedChanges)]);
  }

  // ---------------------------------------------------------------------------
  // WebSocket event handlers
  // ---------------------------------------------------------------------------

  void _onWsOpen([dynamic _]) {
    isAuthenticated = false;
    emit('open', [OnOpenParams(null)]);
    sendToken();
    startSync();
  }

  void _onWsMessage(dynamic dataArg, [dynamic __]) {
    final data = dataArg as Uint8List;
    final message = IncomingMessage(data);

    // Read and re-write the document name prefix
    final documentName = message.readVarString();
    message.writeVarString(documentName);

    emit('message', [OnMessageParams(null, message)]);
    MessageReceiver(message).apply(this, true);
  }

  void _onWsClose(dynamic code, [dynamic reason]) {
    isAuthenticated = false;
    synced = false;

    // Remove all remote awareness states
    final aw = awareness;
    if (aw != null) {
      final remoteClients = aw.getStates().keys
          .where((c) => c != document.clientID)
          .toList();
      removeAwarenessStates(aw, remoteClients, this);
    }
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  void startSync() {
    _resetUnsyncedChanges();
    _sendMessage(SyncStepOneMessage(
      documentName: configuration.name,
      document: document,
    ));

    final aw = awareness;
    if (aw != null && aw.getLocalState() != null) {
      _sendAwareness([document.clientID]);
    }
  }

  void forceSync() {
    _resetUnsyncedChanges();
    _sendMessage(SyncStepOneMessage(
      documentName: configuration.name,
      document: document,
    ));
  }

  // ---------------------------------------------------------------------------
  // Document update handler
  // ---------------------------------------------------------------------------

  // doc.emit('update', [update, origin, doc, transaction])
  void _documentUpdateHandler(dynamic update,
      [dynamic origin, dynamic doc, dynamic transaction]) {
    final updateBytes = update as Uint8List;
    if (identical(origin, this)) return;

    incrementUnsyncedChanges();
    _sendMessage(UpdateMessage(
      documentName: configuration.name,
      update: updateBytes,
    ));
  }

  // ---------------------------------------------------------------------------
  // Awareness
  // ---------------------------------------------------------------------------

  void _sendAwareness(List<int> clients) {
    final aw = awareness;
    if (aw == null) return;
    _sendMessage(AwarenessMessage(
      documentName: configuration.name,
      awareness: aw,
      clients: clients,
    ));
  }

  List<Map<String, Object?>> _awarenessStatesArray() {
    final aw = awareness;
    if (aw == null) return [];
    return aw.getStates().entries.map((e) {
      final state = Map<String, Object?>.from(e.value as Map? ?? {});
      state['clientId'] = e.key;
      return state;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<void> sendToken() async {
    final tokenFunc = configuration.token;
    if (tokenFunc == null) return;

    final token = await tokenFunc();
    if (token == null || token.isEmpty) return;

    _sendMessage(AuthenticationMessage(
      documentName: configuration.name,
      token: token,
    ));
  }

  void permissionDeniedHandler(String reason) {
    isAuthenticated = false;
    emit('authenticationFailed', [OnAuthenticationFailedParams(reason)]);
    disconnect();
  }

  void authenticatedHandler(String scope) {
    isAuthenticated = true;
    authorizedScope = scope;
    emit('authenticated', [OnAuthenticatedParams(scope)]);
  }

  // ---------------------------------------------------------------------------
  // Stateless
  // ---------------------------------------------------------------------------

  void receiveStateless(String payload) {
    emit('stateless', [OnStatelessParams(payload)]);
  }

  void sendStateless(String payload) {
    _sendMessage(StatelessMessage(
      documentName: configuration.name,
      payload: payload,
    ));
  }

  // ---------------------------------------------------------------------------
  // Close
  // ---------------------------------------------------------------------------

  void onClose() => _onWsClose([]);

  void emitClose(String reason) {
    emit('close', [OnCloseParams(1000, reason)]);
  }

  // ---------------------------------------------------------------------------
  // Send helpers
  // ---------------------------------------------------------------------------

  void _sendMessage(dynamic message) {
    emit('outgoingMessage', [OnOutgoingMessageParams(message)]);
    // ignore: avoid_dynamic_calls
    final bytes = message.toUint8Array() as Uint8List;
    _wsProvider.send(bytes);
  }

  /// Send raw bytes (used by MessageReceiver for replies).
  void sendRaw(Uint8List bytes) => _wsProvider.send(bytes);

  // ---------------------------------------------------------------------------
  // Connect / Disconnect / Destroy
  // ---------------------------------------------------------------------------

  Future<void> connect() => _wsProvider.connect();

  void disconnect() => _wsProvider.disconnect();

  @override
  void destroy() {
    // Cancel periodic timers before disconnect
    _forceSyncTimer?.cancel();
    _forceSyncTimer = null;

    // Gracefully tell the server we're closing
    _sendMessage(CloseMessage(documentName: configuration.name));

    emit('destroy', []);

    final aw = awareness;
    if (aw != null) {
      removeAwarenessStates(aw, [document.clientID], 'provider destroy');
      aw.destroy();
    }

    document.off('update', _documentUpdateHandler);

    if (_manageSocket) {
      _wsProvider.destroy();
    }

    super.destroy();
  }
}
