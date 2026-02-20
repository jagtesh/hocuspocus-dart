# Changelog

## 1.0.5

-   **Dependency**: Upgraded `yjs_dart` to `^1.1.12` to include the `YText.insert` CRDT duplication patch.

-   **Dep**: Bumped minimum `yjs_dart` dependency to `^1.1.11` to include `YArray` offline sync capabilities, bug fixes, and exact-schema structure exports.

## 1.0.3

-   **Fix**: Updated the `yjs_dart` package source to point to `pub.dev`.

## 1.0.2

-   **Fix**: Updated the `yjs_dart` package source to point to `pub.dev`. 

## 1.0.1

-   **Fix**: `SyncStepOneMessage` was wrapping the sync payload in `writeVarUint8Array`, prepending a spurious length byte. The server saw this as an unknown sync sub-tag (3) and rejected it. Fixed to write the payload directly via `writeSyncStep1`.
-   **Fix**: All `provider.on(event, callback)` listeners were incorrectly indexing into the argument as a list (`args[0]`). `Observable.emit` spreads args as positional parameters — callbacks now receive the value directly.
-   **Fix**: `_documentUpdateHandler` only accepted 2 args but `doc.emit('update', ...)` fires 4 (`update, origin, doc, transaction`). Added optional params to match the arity.
-   **Tests**: Added regression tests for all 3 bugs plus integration tests based on real observed message bytes (12-byte `SyncStep1` for `"default"` document).

## 1.0.0

- Initial release.
- Added `HocuspocusProvider` and WebSocket connectivity.
- Supports all standard Hocuspocus message types (Sync, Awareness, Auth, Stateless).
- Compatible with `yjs_dart` v1.1.2+.
