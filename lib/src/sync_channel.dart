import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal duplex text channel abstraction used by the sync layer.
///
/// Implementations must transport UTF-8 JSON strings over [stream]/[sink].
abstract class SyncChannel {
  /// Incoming message stream (each event is a JSON string).
  Stream<String> get stream;

  /// Outgoing sink (each event must be a JSON string).
  StreamSink<String> get sink;

  /// Completes when the channel is ready to use.
  Future<void> get ready;

  /// Optional close code/reason (WebSocket only).
  int? get closeCode;
  String? get closeReason;

  /// Close the channel.
  Future<void> close([int? code, String? reason]);
}

/// Adapter for [WebSocketChannel].
class WebSocketSyncChannel implements SyncChannel {
  WebSocketSyncChannel(this._socket);

  final WebSocketChannel _socket;

  late final StreamSink<String> _stringSink =
      _WebSocketSinkStreamSinkStringAdapter(_socket.sink);

  @override
  Stream<String> get stream => _socket.stream.cast<String>();

  @override
  StreamSink<String> get sink => _stringSink;

  @override
  Future<void> get ready => _socket.ready;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.sink.close(code, reason);
}

/// Simple in-memory duplex text channel built from a pair of streams/sinks.
class DuplexStreamChannel implements SyncChannel {
  DuplexStreamChannel({
    required Stream<String> incoming,
    required StreamSink<String> outgoing,
    Future<void>? ready,
  })  : _incoming = incoming,
        _outgoing = outgoing,
        _ready = ready ?? Future.value();

  final Stream<String> _incoming;
  final StreamSink<String> _outgoing;
  final Future<void> _ready;

  @override
  Stream<String> get stream => _incoming;

  @override
  StreamSink<String> get sink => _outgoing;

  @override
  Future<void> get ready => _ready;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> close([int? code, String? reason]) async {
    await _outgoing.close();
  }
}

class _WebSocketSinkStreamSinkStringAdapter implements StreamSink<String> {
  _WebSocketSinkStreamSinkStringAdapter(this._inner);

  final WebSocketSink _inner;

  @override
  void add(String data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<String> stream) => _inner.addStream(stream);

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> get done => _inner.done;
}
