import 'dart:async';
import 'dart:math';

import 'package:crdt/crdt.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'crdt_sync.dart';
import 'sync_channel.dart';

const _minDelay = 2; // In seconds. Minimum is 2 because 1² = 1.
const _maxDelay = 10;

enum ConnectionState { disconnected, connecting, connected }

typedef ChannelFactory = Future<SyncChannel> Function();

class CrdtSyncClient {
  final Crdt crdt;
  final ChannelFactory channelFactory;
  final ClientHandshakeDataBuilder? handshakeDataBuilder;
  final ChangesetBuilder? changesetBuilder;
  final RecordValidator? validateRecord;
  final ChangesetMapper? mapIncomingChangeset;
  final void Function()? onConnecting;
  final OnConnect? onConnect;
  final OnDisconnect? onDisconnect;
  final OnChangeset? onChangesetReceived;
  final OnChangeset? onChangesetSent;
  final bool verbose;

  CrdtSync? _crdtSync;

  var _onlineMode = false;
  var _state = ConnectionState.disconnected;
  final _stateController = StreamController<ConnectionState>.broadcast();

  var _reconnectDelay = _minDelay; // in seconds
  Timer? _reconnectTimer;

  /// Get the current connection state.
  ConnectionState get state => _state;

  /// Stream connection state changes.
  Stream<ConnectionState> get watchState => _stateController.stream;

  /// A client that automatically manages the connection state of an
  /// underlying [CrdtSync].
  ///
  /// Use [onConnecting] to monitor the state of outgoing connection attempts.
  ///
  /// The [channelFactory] is called each time a connection attempt is made.
  /// It should create and return a new [SyncChannel] instance.
  ///
  /// See [CrdtSync.client] for a description of the remaining parameters.
  CrdtSyncClient(
    this.crdt,
    this.channelFactory, {
    this.handshakeDataBuilder,
    this.changesetBuilder,
    this.validateRecord,
    this.mapIncomingChangeset,
    this.onConnecting,
    this.onConnect,
    this.onDisconnect,
    this.onChangesetReceived,
    this.onChangesetSent,
    this.verbose = false,
  });

  /// Creates a WebSocket-based client.
  ///
  /// This is a convenience constructor that creates a [ChannelFactory] for
  /// WebSocket connections to the specified [uri].
  factory CrdtSyncClient.websocket(
    Crdt crdt,
    Uri uri, {
    ClientHandshakeDataBuilder? handshakeDataBuilder,
    ChangesetBuilder? changesetBuilder,
    RecordValidator? validateRecord,
    ChangesetMapper? mapIncomingChangeset,
    void Function()? onConnecting,
    OnConnect? onConnect,
    OnDisconnect? onDisconnect,
    OnChangeset? onChangesetReceived,
    OnChangeset? onChangesetSent,
    bool verbose = false,
  }) {
    assert({'ws', 'wss'}.contains(uri.scheme));
    return CrdtSyncClient(
      crdt,
      () async {
        final socket = WebSocketChannel.connect(uri);
        await socket.ready;
        return WebSocketSyncChannel(socket);
      },
      handshakeDataBuilder: handshakeDataBuilder,
      changesetBuilder: changesetBuilder,
      validateRecord: validateRecord,
      mapIncomingChangeset: mapIncomingChangeset,
      onConnecting: onConnecting,
      onConnect: onConnect,
      onDisconnect: onDisconnect,
      onChangesetReceived: onChangesetReceived,
      onChangesetSent: onChangesetSent,
      verbose: verbose,
    );
  }

  /// Start trying to connect using the provided [channelFactory].
  /// The client will continuously try to connect using exponential backoff
  /// until it succeeds.
  void connect() async {
    if (_state != ConnectionState.disconnected) return;
    _onlineMode = true;
    _reconnectTimer?.cancel();

    _setState(ConnectionState.connecting);
    onConnecting?.call();

    try {
      final channel = await channelFactory();
      _crdtSync = CrdtSync.client(
        crdt,
        channel,
        handshakeDataBuilder: handshakeDataBuilder,
        changesetBuilder: changesetBuilder,
        validateRecord: validateRecord,
        mapIncomingChangeset: mapIncomingChangeset,
        onConnect: (remoteNodeId, remoteInfo) {
          _reconnectDelay = _minDelay;
          _setState(ConnectionState.connected);
          onConnect?.call(remoteNodeId, remoteInfo);
        },
        onChangesetReceived: onChangesetReceived,
        onChangesetSent: onChangesetSent,
        onDisconnect: (remoteNodeId, code, reason) {
          _setState(ConnectionState.disconnected);
          onDisconnect?.call(remoteNodeId, code, reason);
          _crdtSync = null;
          _maybeReconnect();
        },
        verbose: verbose,
      );
    } catch (e) {
      _log('$e');
      _setState(ConnectionState.disconnected);
      _maybeReconnect();
    }
  }

  /// Disconnect from the server, and stop attempting to reconnect.
  Future<void> disconnect([int? code, String? reason]) async {
    if (!_onlineMode) return;
    _onlineMode = false;
    _reconnectTimer?.cancel();
    _reconnectDelay = _minDelay;

    await _crdtSync?.close(code, reason);
    _setState(ConnectionState.disconnected);
  }

  void _maybeReconnect() {
    if (_onlineMode) {
      _reconnectTimer =
          Timer(Duration(seconds: _reconnectDelay), () => connect());
      _log('Reconnecting in ${_reconnectDelay}s…');
      _reconnectDelay = min(_reconnectDelay * 2, _maxDelay);
    }
  }

  void _setState(ConnectionState state) {
    if (_state == state) return;
    _state = state;
    _stateController.add(state);
  }

  void _log(String msg) {
    if (verbose) print(msg);
  }
}
