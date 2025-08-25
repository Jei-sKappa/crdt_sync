import 'dart:async';

import 'package:serverpod/serverpod.dart';

import 'package:crdt_sync/crdt_sync.dart';
import 'crdt_store.dart';

/// Streaming endpoint that bridges Serverpod streaming with crdt_sync.
class SyncEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  /// A streaming method exposed by Serverpod that we use to transport the
  /// CRDT sync frames as plain UTF-8 JSON strings.
  ///
  /// The server returns the outgoing stream to the client, while receiving
  /// client frames on [fromClient].
  Stream<String> crdtStream(Session session, Stream<String> fromClient) async* {
    final userIdentifier = (await session.authenticated)?.userIdentifier;

    if (userIdentifier == null) {
      throw Exception('User not authenticated');
    }

    final toClient = StreamController<String>();

    // Bridge the Serverpod duplex streams with crdt_sync
    final channel = DuplexStreamChannel(
      incoming: fromClient,
      outgoing: toClient.sink,
    );

    final crdt = await createCrdt();

    // Start sync over the duplex channel
    CrdtSync.server(
      crdt,
      channel,
      handshakeDataBuilder: (peerId, peerData) => {
        'server': 'example_server',
        'peerId': peerId,
      },
      changesetBuilder: ({
        exceptNodeId,
        modifiedAfter,
        modifiedOn,
        onlyNodeId,
        onlyTables,
      }) {
        return crdt.getChangeset(
          customQueries: {
            'todos': (
              'SELECT id, title, done, hlc, node_id, modified, is_deleted FROM todos WHERE user_id = ?1',
              [userIdentifier]
            ),
          },
          exceptNodeId: exceptNodeId,
          modifiedAfter: modifiedAfter,
          modifiedOn: modifiedOn,
          onlyNodeId: onlyNodeId,
          onlyTables: onlyTables,
        );
      },
      validateRecord: (table, record) {
        switch (table) {
          case 'todos':
            return true;
          default:
            return false;
        }
      },
      mapIncomingChangeset: (table, record) {
        switch (table) {
          case 'todos':
            final recordWithUserId = Map<String, Object?>.from(record);
            recordWithUserId['user_id'] = userIdentifier;
            return recordWithUserId;
          default:
            throw Exception('Unknown table: $table');
        }
      },
      // verbose: true,
    );

    // Yield messages to the client
    yield* toClient.stream;
  }
}
