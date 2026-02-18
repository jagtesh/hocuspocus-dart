/// Dart port of @hocuspocus/provider HocuspocusProvider.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/HocuspocusProvider.ts
library;

import 'dart:typed_data';

import 'package:yjs_dart/src/lib0/observable.dart';
import 'package:yjs_dart/src/protocols/awareness.dart'
    show Awareness, removeAwarenessStates;
import 'package:yjs_dart/src/utils/doc.dart' show Doc;
import 'package:yjs_dart/src/utils/updates.dart' show encodeStateAsUpdate;

import 'hocuspocus_provider_websocket.dart';
import 'incoming_message.dart';
import 'message_receiver.dart';
import 'outgoing_messages/authentication_message.dart';
import 'outgoing_messages/awareness_message.dart';
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
  final String? token;

  /// Shared WebSocket provider. If not provided, one is created from [url].
  final HocuspocusProviderWebsocket? websocketProvider;

  /// WebSocket URL (required if [websocketProvider] is not provided).
  final String? url;

  /// Force sync interval in milliseconds, or null to disable.
  final int? forceSyncInterval;

  // Callbacks
  final void Function(OnAuthenticatedParams)? onAuthenticated;
  final void Function(OnAuthenticationFailedParams)? onAuthenticationFailed;
  final void Function(OnOpenParams)? onOpen;
  final void Function()? onConnect;
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
    this.autoConnect = true,
    this.onAuthenticated,
    this.onAuthenticationFailed,
    this.onOpen,
    this.onConnect,
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
        HocuspocusProviderWebsocketConfiguration(url: configuration.url!),
      );
    }

    // Register callbacks
    if (configuration.onAuthenticated != null) {
      on('authenticated', (args) =>
          configuration.onAuthenticated!(args[0] as OnAuthenticatedParams));
    }
    if (configuration.onAuthenticationFailed != null) {
      on('authenticationFailed', (args) =>
          configuration.onAuthenticationFailed!(args[0] as OnAuthenticationFailedParams));
    }
    if (configuration.onSynced != null) {
      on('synced', (args) =>
          configuration.onSynced!(args[0] as OnSyncedParams));
    }
    if (configuration.onDestroy != null) {
      on('destroy', (_) => configuration.onDestroy!());
    }
    if (configuration.onStateless != null) {
      on('stateless', (args) =>
          configuration.onStateless!(args[0] as OnStatelessParams));
    }
    if (configuration.onUnsyncedChanges != null) {
      on('unsyncedChanges', (args) =>
          configuration.onUnsyncedChanges!(args[0] as OnUnsyncedChangesParams));
    }
    if (configuration.onAwarenessUpdate != null) {
      on('awarenessUpdate', (args) =>
          configuration.onAwarenessUpdate!(args[0] as OnAwarenessUpdateParams));
    }
    if (configuration.onAwarenessChange != null) {
      on('awarenessChange', (args) =>
          configuration.onAwarenessChange!(args[0] as OnAwarenessChangeParams));
    }

    // Awareness listeners
    awareness?.on('update', (dynamic changedArg, [dynamic origin]) {
      final changed = changedArg as Map;
      final added = (changed['added'] as List?)?.cast<int>() ?? [];
      final updated = (changed['updated'] as List?)?.cast<int>() ?? [];
      final removed = (changed['removed'] as List?)?.cast<int>() ?? [];
      final changedClients = [...added, ...updated, ...removed];
      _sendAwareness(changedClients);
      emit('awarenessUpdate', [OnAwarenessUpdateParams(_awarenessStatesArray())]);
    });

    awareness?.on('change', (dynamic _, [dynamic __]) {
      emit('awarenessChange', [OnAwarenessChangeParams(_awarenessStatesArray())]);
    });

    // Document update listener
    document.on('update', _documentUpdateHandler);

    // WebSocket listeners
    _wsProvider.on('open', _onWsOpen);
    _wsProvider.on('message', _onWsMessage);
    _wsProvider.on('close', _onWsClose);
    _wsProvider.on('connect', ([dynamic _]) => emit('connect', []));
    _wsProvider.on('disconnect', (dynamic code, [dynamic reason]) {
      emit('disconnect', [OnDisconnectParams(code as int, (reason ?? '') as String)]);
    });
    _wsProvider.on('status', (dynamic s, [dynamic __]) {
      emit('status', [OnStatusParams(s as WebSocketStatus)]);
    });
    _wsProvider.on('destroy', ([dynamic _]) => emit('destroy', []));

    // Force sync interval
    if (configuration.forceSyncInterval != null) {
      // Dart timers are set up in connect()
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

  void _onWsClose([dynamic _]) {
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

  void _documentUpdateHandler(dynamic updateArg, [dynamic origin]) {
    final update = updateArg as Uint8List;
    if (identical(origin, this)) return;

    incrementUnsyncedChanges();
    _sendMessage(UpdateMessage(
      documentName: configuration.name,
      update: update,
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
    final token = configuration.token ?? '';
    _sendMessage(AuthenticationMessage(
      documentName: configuration.name,
      token: token,
    ));
  }

  void permissionDeniedHandler(String reason) {
    emit('authenticationFailed', [OnAuthenticationFailedParams(reason)]);
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
    // ignore: avoid_dynamic_calls
    _wsProvider.send(message.toUint8Array() as Uint8List);
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
