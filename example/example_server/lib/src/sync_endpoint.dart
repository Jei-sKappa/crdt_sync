import 'dart:async';

import 'package:serverpod/serverpod.dart';

import 'package:crdt_sync/crdt_sync.dart';
import 'crdt_store.dart';

/// Streaming endpoint that bridges Serverpod streaming with crdt_sync.
class SyncEndpoint extends Endpoint {
  /// A streaming method exposed by Serverpod that we use to transport the
  /// CRDT sync frames as plain UTF-8 JSON strings.
  ///
  /// The server returns the outgoing stream to the client, while receiving
  /// client frames on [fromClient].
  Stream<String> crdtStream(Session session, Stream<String> fromClient) async* {
    final toClient = StreamController<String>();

    // Bridge the Serverpod duplex streams with crdt_sync
    final channel = DuplexStreamChannel(
      incoming: fromClient,
      outgoing: toClient.sink,
    );

    // Start sync over the duplex channel
    CrdtSync.server(
      mapCrdt,
      channel,
      handshakeDataBuilder: (peerId, peerData) => {
        'server': 'example_server',
        'peerId': peerId,
      },
      // verbose: true,
    );

    // Yield messages to the client
    yield* toClient.stream;
  }
}
