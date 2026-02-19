/// hocuspocus_dart — A pure Dart port of the hocuspocus WebSocket provider.
///
/// Pinned to hocuspocus JS v2.12.3 (see vendor/hocuspocus).
///
/// Usage:
/// ```dart
/// import 'package:hocuspocus_dart/hocuspocus_dart.dart';
///
/// final provider = HocuspocusProvider(
///   HocuspocusProviderConfiguration(
///     url: 'ws://localhost:1234',
///     name: 'my-document',
///   ),
/// );
/// ```
library hocuspocus_dart;

export 'src/hocuspocus_provider.dart';
export 'src/hocuspocus_provider_websocket.dart';
export 'src/incoming_message.dart';
export 'src/message_receiver.dart';
export 'src/outgoing_message.dart';
export 'src/outgoing_messages/authentication_message.dart';
export 'src/outgoing_messages/awareness_message.dart';
export 'src/outgoing_messages/close_message.dart';
export 'src/outgoing_messages/query_awareness_message.dart';
export 'src/outgoing_messages/stateless_message.dart';
export 'src/outgoing_messages/sync_step_one_message.dart';
export 'src/outgoing_messages/sync_step_two_message.dart';
export 'src/outgoing_messages/update_message.dart';
export 'src/types.dart';
