# hocuspocus-dart

A pure Dart port of the [Hocuspocus](https://github.com/ueberdosis/hocuspocus) WebSocket provider for Yjs CRDT collaboration.

Pinned to **hocuspocus v2.12.3** (vendored at `vendor/hocuspocus`).

## Quick Start

```dart
import 'package:hocuspocus_dart/hocuspocus_dart.dart';

final provider = HocuspocusProvider(
  HocuspocusProviderConfiguration(
    url: 'ws://localhost:1234',
    name: 'my-document',
  ),
);
```

## Feature Parity

This library aims for 100% feature parity with the **@hocuspocus/provider v2.12.3** JavaScript client.

| Feature | Status | Notes |
|---------|--------|-------|
| **Protocol** | ✅ Full | Sync, Awareness, Auth, Stateless, QueryAwareness |
| **Reconnection** | ✅ Full | Exponential backoff, max retries, message timeout |
| **Authentication** | ✅ Enhanced | Supports token as `String` or `FutureOr<String?> Function()` (async refresh) |
| **Connection** | ✅ Enhanced | Added `connectTimeout` configuration to prevent hanging |
| **Awareness** | ✅ Full | Shared presence state, local state updates |
| **Force Sync** | ✅ Full | Configurable interval to ensure consistency |
| **Callbacks** | ✅ Full | `onConnect`, `onDisconnect`, `onMessage`, `onSynced`, etc. |
| **Debug** | ✅ Full | `outgoingMessage` event for traffic inspection |

### What's Not Ported (Intentional)

- **BroadcastChannel** - Browser-specific cross-tab sync (irrelevant for native apps).
- **TiptapCollabProvider** - Tiptap Cloud-specific features (threads, comments) are out of scope.

## Dependencies

- [yjs-dart](https://github.com/jagtesh/yjs-dart) - Yjs CRDT library (path dependency)
- [web_socket_channel](https://pub.dev/packages/web_socket_channel) - WebSocket transport

## Development

```bash
dart pub get
dart analyze
dart test
```

## License

BSD 3-Clause License. Copyright (c) 2026 Jagtesh Chadha.
