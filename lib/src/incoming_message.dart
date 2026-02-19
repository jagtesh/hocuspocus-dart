/// Dart port of @hocuspocus/provider IncomingMessage.ts
///
/// Mirrors: hocuspocus v2.12.3 packages/provider/src/IncomingMessage.ts
library;

import 'dart:typed_data';

import 'package:yjs_dart/yjs_dart.dart' as decoding;
import 'package:yjs_dart/yjs_dart.dart' as encoding;

/// Wraps a raw WebSocket message with a decoder for reading and an encoder
/// for building a reply.
///
/// Mirrors: `IncomingMessage` in IncomingMessage.ts
class IncomingMessage {
  final Uint8List _data;
  late final decoding.Decoder decoder;
  late final encoding.Encoder encoder;

  IncomingMessage(this._data) {
    decoder = decoding.createDecoder(_data);
    encoder = encoding.createEncoder();
  }

  /// Read a variable-length unsigned integer.
  int readVarUint() => decoding.readVarUint(decoder);

  /// Read a variable-length string.
  String readVarString() => decoding.readVarString(decoder);

  /// Read a variable-length byte array.
  Uint8List readVarUint8Array() => decoding.readVarUint8Array(decoder);

  /// Write a variable-length unsigned integer to the reply encoder.
  void writeVarUint(int n) => encoding.writeVarUint(encoder, n);

  /// Write a variable-length string to the reply encoder.
  void writeVarString(String s) => encoding.writeVarString(encoder, s);

  /// Write a variable-length byte array to the reply encoder.
  void writeVarUint8Array(Uint8List bytes) =>
      encoding.writeVarUint8Array(encoder, bytes);

  /// Peek a variable-length string without advancing the decoder position.
  ///
  /// Mirrors: `peekVarString` in IncomingMessage.ts / lib0/decoding.js
  String peekVarString() {
    final clone = decoding.clone(decoder);
    return decoding.readVarString(clone);
  }

  /// Number of bytes written to the reply encoder so far.
  int length() => encoding.toUint8Array(encoder).length;

  /// Serialize the reply encoder to bytes.
  Uint8List toUint8Array() => encoding.toUint8Array(encoder);
}
