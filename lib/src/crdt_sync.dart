import 'dart:async';

import 'package:crdt/crdt.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'sync_protocol.dart';
import 'sync_channel.dart';

typedef ClientHandshakeDataBuilder = FutureOr<Object>? Function();
typedef ServerHandshakeDataBuilder = FutureOr<Object>? Function(
    String peerId, Object? peerData);
typedef ChangesetBuilder = FutureOr<CrdtChangeset> Function(
    {Iterable<String>? onlyTables,
    String? onlyNodeId,
    String? exceptNodeId,
    Hlc? modifiedOn,
    Hlc? modifiedAfter});
typedef RecordValidator = FutureOr<bool> Function(String table, CrdtRecord);
typedef ChangesetMapper = CrdtRecord Function(String table, CrdtRecord record);
typedef OnChangeset = void Function(
    String nodeId, Map<String, int> recordCounts);
typedef OnConnect = void Function(String peerId, Object? customData);
typedef OnDisconnect = void Function(String peerId, int? code, String? reason);
typedef OnCommunicationError = void Function(Object error, StackTrace st);

class CrdtSync {
  final bool isClient;
  final Crdt crdt;

  final ClientHandshakeDataBuilder? clientHandshakeDataBuilder;
  final ServerHandshakeDataBuilder? serverHandshakeDataBuilder;
  final ChangesetBuilder changesetBuilder;
  final RecordValidator? validateRecord;
  final ChangesetMapper? mapIncomingChangeset;
  final OnConnect? onConnect;
  final OnDisconnect? onDisconnect;
  final OnChangeset? onChangesetReceived;
  final OnChangeset? onChangesetSent;
  final OnCommunicationError? onCommunicationError;
  final bool verbose;

  late final SyncProtocol _syncProtocol;
  String? _peerId;
  // Per-connection watermark for outgoing deltas.
  // Always uses local node id semantics (as ensured by handshake parsing).
  late Hlc _lastSentModified;

  /// Represents the nodeId from the remote peer connected to this socket.
  String? get peerId => _peerId;

  /// Starts synchronization over a generic [SyncChannel] on the client side.
  ///
  /// Use [handshakeDataBuilder] to send connection metadata on the first frame.
  /// This can be useful to send server identifiers, or verification tokens.
  ///
  /// Use [changesetBuilder] if you want to specify a custom query to generate
  /// changesets.
  /// This can be useful for e.g. filtering records by user id server-side, or
  /// to transparently encrypt outgoing data.
  /// Defaults to calling [Crdt.getChangeset] for all tables in the database.
  ///
  /// If implemented, [validateRecord] will be called for each incoming record.
  /// Returning false prevents that record from being merged into the local
  /// database. This can be used for low-trust environments to e.g. avoid
  /// a user writing into tables it should not have access to.
  ///
  /// [mapIncomingChangeset] grants the oportunity to intercept and alter
  /// received changesets. This can be useful for e.g. decrypting incoming data.
  ///
  /// The [onConnect] and [onDisconnect] callbacks can be used to monitor the
  /// connection state.
  ///
  /// [onChangesetReceived] and [onChangesetSent] can be used to log the
  /// respective data transfers. This can be useful to identify data handling
  /// inefficiencies.
  ///
  /// Set [verbose] to true to spam your output with raw record payloads.
  CrdtSync.client(
    Crdt crdt,
    SyncChannel channel, {
    ClientHandshakeDataBuilder? handshakeDataBuilder,
    ChangesetBuilder? changesetBuilder,
    RecordValidator? validateRecord,
    ChangesetMapper? mapIncomingChangeset,
    OnConnect? onConnect,
    OnDisconnect? onDisconnect,
    OnCommunicationError? onCommunicationError,
    OnChangeset? onChangesetReceived,
    OnChangeset? onChangesetSent,
    bool verbose = false,
  }) : this._(
          crdt,
          channel,
          isClient: true,
          clientHandshakeDataBuilder: handshakeDataBuilder,
          changesetBuilder: changesetBuilder,
          validateRecord: validateRecord,
          mapIncomingChangeset: mapIncomingChangeset,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
          onCommunicationError: onCommunicationError,
          onChangesetReceived: onChangesetReceived,
          onChangesetSent: onChangesetSent,
          verbose: verbose,
        );

  /// Takes an established [WebSocket] connection to start synchronizing the
  /// supplied [crdt] with a remote CrdtSync instance.
  ///
  /// This is a convenience wrapper around [CrdtSync.client] that automatically
  /// wraps the WebSocket in a [WebSocketSyncChannel].
  ///
  /// See [CrdtSync.client] for a description of the parameters.
  CrdtSync.websocketClient(
    Crdt crdt,
    WebSocketChannel webSocket, {
    ClientHandshakeDataBuilder? handshakeDataBuilder,
    ChangesetBuilder? changesetBuilder,
    RecordValidator? validateRecord,
    ChangesetMapper? mapIncomingChangeset,
    OnConnect? onConnect,
    OnDisconnect? onDisconnect,
    OnCommunicationError? onCommunicationError,
    OnChangeset? onChangesetReceived,
    OnChangeset? onChangesetSent,
    bool verbose = false,
  }) : this._(
          crdt,
          WebSocketSyncChannel(webSocket),
          isClient: true,
          clientHandshakeDataBuilder: handshakeDataBuilder,
          changesetBuilder: changesetBuilder,
          validateRecord: validateRecord,
          mapIncomingChangeset: mapIncomingChangeset,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
          onCommunicationError: onCommunicationError,
          onChangesetReceived: onChangesetReceived,
          onChangesetSent: onChangesetSent,
          verbose: verbose,
        );

  /// Starts synchronization over a generic [SyncChannel] on the server side.
  ///
  /// See [CrdtSync.client] for a description of the parameters.
  CrdtSync.server(
    Crdt crdt,
    SyncChannel channel, {
    ServerHandshakeDataBuilder? handshakeDataBuilder,
    ChangesetBuilder? changesetBuilder,
    RecordValidator? validateRecord,
    ChangesetMapper? mapIncomingChangeset,
    OnConnect? onConnect,
    OnDisconnect? onDisconnect,
    OnCommunicationError? onCommunicationError,
    OnChangeset? onChangesetReceived,
    OnChangeset? onChangesetSent,
    bool verbose = false,
  }) : this._(
          crdt,
          channel,
          isClient: false,
          serverHandshakeDataBuilder: handshakeDataBuilder,
          changesetBuilder: changesetBuilder,
          validateRecord: validateRecord,
          mapIncomingChangeset: mapIncomingChangeset,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
          onCommunicationError: onCommunicationError,
          onChangesetReceived: onChangesetReceived,
          onChangesetSent: onChangesetSent,
          verbose: verbose,
        );

  /// Takes an established [WebSocket] connection to start synchronizing with
  /// another CrdtSync socket.
  ///
  /// This is a convenience wrapper around [CrdtSync.server] that automatically
  /// wraps the WebSocket in a [WebSocketSyncChannel].
  ///
  /// It's recommended that the supplied [socket] has a ping interval set to
  /// avoid stale connections. This can be done in the parent framework, e.g.
  /// by setting [pingInterval] in shelf_web_socket's [webSocketHandler].
  ///
  /// Also provided are [listen] and [upgrade] as helper functions to accept new
  /// connections, and upgrade existing ones, respectively.
  ///
  /// See [CrdtSync.server] for a description of the remaining parameters.
  CrdtSync.websocketServer(
    Crdt crdt,
    WebSocketChannel webSocket, {
    ServerHandshakeDataBuilder? handshakeDataBuilder,
    ChangesetBuilder? changesetBuilder,
    RecordValidator? validateRecord,
    ChangesetMapper? mapIncomingChangeset,
    OnConnect? onConnect,
    OnDisconnect? onDisconnect,
    OnCommunicationError? onCommunicationError,
    OnChangeset? onChangesetReceived,
    OnChangeset? onChangesetSent,
    bool verbose = false,
  }) : this._(
          crdt,
          WebSocketSyncChannel(webSocket),
          isClient: false,
          serverHandshakeDataBuilder: handshakeDataBuilder,
          changesetBuilder: changesetBuilder,
          validateRecord: validateRecord,
          mapIncomingChangeset: mapIncomingChangeset,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
          onCommunicationError: onCommunicationError,
          onChangesetReceived: onChangesetReceived,
          onChangesetSent: onChangesetSent,
          verbose: verbose,
        );

  CrdtSync._(
    this.crdt,
    SyncChannel channel, {
    required this.isClient,
    this.clientHandshakeDataBuilder,
    this.serverHandshakeDataBuilder,
    ChangesetBuilder? changesetBuilder,
    required this.validateRecord,
    required this.mapIncomingChangeset,
    required this.onConnect,
    required this.onDisconnect,
    required this.onCommunicationError,
    required this.onChangesetReceived,
    required this.onChangesetSent,
    required this.verbose,
  })  : changesetBuilder = changesetBuilder ?? crdt.getChangeset,
        assert((isClient && serverHandshakeDataBuilder == null) ||
            (!isClient && clientHandshakeDataBuilder == null)) {
    _handle(channel);
  }

  Future<void> _handle(SyncChannel channel) async {
    StreamSubscription? localSubscription;

    _syncProtocol = SyncProtocol(
      channel,
      crdt.nodeId,
      onDisconnect: (code, reason) {
        localSubscription?.cancel();
        if (_peerId != null) onDisconnect?.call(_peerId!, code, reason);
      },
      onChangeset: _mergeChangeset,
      verbose: verbose,
    );

    try {
      final handshake = await _performHandshake();
      _peerId = handshake.nodeId;
      
      // Initialize per-connection watermark from the peer handshake.
      _lastSentModified = handshake.lastModified;

      onConnect?.call(_peerId!, handshake.data);

      // Monitor for changes and send them immediately
      localSubscription = crdt.onTablesChanged
          .where((e) => e.tables.isNotEmpty)
          .asyncMap((e) => changesetBuilder(
                onlyTables: e.tables,
                onlyNodeId: isClient ? crdt.nodeId : null,
                exceptNodeId: isClient ? null : _peerId,
                modifiedAfter: _lastSentModified,
              ))
          .listen(_sendChangeset);

      // Send changeset since last sync.
      // This is done after monitoring to prevent losing changes that happen
      // exactly between both calls.
      final changeset = await changesetBuilder(
        onlyNodeId: isClient ? crdt.nodeId : null,
        exceptNodeId: isClient ? null : _peerId,
        modifiedAfter: handshake.lastModified,
      );
      _sendChangeset(changeset);
    } catch (e, st) {
      onCommunicationError?.call(e, st);
      await localSubscription?.cancel();
      await _syncProtocol.close();
      _logException(e, st);
    }
  }

  /// Close the connection.
  ///
  /// Supply an optional [code] and [reason] to be forwarded to the peer.
  /// See https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent/code for
  /// a list of permissible codes.
  Future<void> close([int? code, String? reason]) =>
      _syncProtocol.close(code, reason);

  Future<Handshake> _performHandshake() async {
    if (isClient) {
      // Introduce ourselves
      _syncProtocol.sendHandshake(
        crdt.nodeId,
        await crdt.getLastModified(exceptNodeId: crdt.nodeId),
        await clientHandshakeDataBuilder?.call(),
      );
      return await _syncProtocol.receiveHandshake();
    } else {
      // A good client always introduces itself first
      final handshake = await _syncProtocol.receiveHandshake();
      _syncProtocol.sendHandshake(
        crdt.nodeId,
        await crdt.getLastModified(onlyNodeId: handshake.nodeId),
        await serverHandshakeDataBuilder?.call(
            handshake.nodeId, handshake.data),
      );
      return handshake;
    }
  }

  void _sendChangeset(CrdtChangeset changeset) {
    if (changeset.recordCount == 0) return;
    _syncProtocol.sendChangeset(changeset);
    onChangesetSent?.call(
        _peerId!, changeset.map((key, value) => MapEntry(key, value.length)));

    // Update per-connection watermark to the max 'modified' we just sent.
    final maxSent = _maxModifiedInChangeset(changeset);
    if (maxSent != null && maxSent.compareTo(_lastSentModified) > 0) {
      _lastSentModified = maxSent;
    }
  }

  Future<void> _mergeChangeset(CrdtChangeset changeset) async {
    // Filter out records which fail validation
    if (validateRecord != null) {
      final validatedChangeset = <String, CrdtTableChangeset>{};
      for (final entry in changeset.entries) {
        final table = entry.key;
        final validatedRecords = <CrdtRecord>[];
        for (final record in entry.value) {
          try {
            final isValid = await validateRecord!(table, record);
            if (isValid) validatedRecords.add(record);
          } catch (e, st) {
            _logException(e, st);
            // Skip records that cause validator exceptions
          }
        }
        if (validatedRecords.isNotEmpty) {
          validatedChangeset[table] = validatedRecords;
        }
      }
      changeset = validatedChangeset;
    }

    // Allow implementation to intercept and modify records
    if (mapIncomingChangeset != null) {
      final mappedChangeset = <String, CrdtTableChangeset>{};
      for (final entry in changeset.entries) {
        final table = entry.key;
        final mappedRecords = <CrdtRecord>[];
        for (final record in entry.value) {
          try {
            mappedRecords.add(mapIncomingChangeset!(table, record));
          } catch (e, st) {
            _logException(e, st);
            // Skip records that cause mapper exceptions
          }
        }
        if (mappedRecords.isNotEmpty) {
          mappedChangeset[table] = mappedRecords;
        }
      }
      changeset = mappedChangeset;
    }

    // Notify and merge
    onChangesetReceived?.call(
        _peerId!, changeset.map((key, value) => MapEntry(key, value.length)));
    try {
      await crdt.merge(changeset);
    } catch (e, st) {
      _logException(e, st);
    }
  }

  Hlc? _maxModifiedInChangeset(CrdtChangeset changeset) {
    Hlc? max;
    for (final table in changeset.values) {
      for (final record in table) {
        final raw = record['modified'];
        if (raw == null) continue;
        final hlc = raw is Hlc ? raw : Hlc.parse(raw as String);
        if (max == null || hlc.compareTo(max) > 0) {
          max = hlc;
        }
      }
    }
    return max;
  }

  void _logException(Object error, StackTrace st) {
    print(verbose ? '$error\n$st' : '$error');
  }
}
