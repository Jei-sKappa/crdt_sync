import 'dart:async';

import 'package:crdt/map_crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:test/test.dart';

/// Simple loopback pair to simulate two ends connected through duplex channels.
class _LoopbackPair {
  _LoopbackPair() {
    final aIn = StreamController<String>();
    final bIn = StreamController<String>();
    a = DuplexStreamChannel(incoming: aIn.stream, outgoing: bIn.sink);
    b = DuplexStreamChannel(incoming: bIn.stream, outgoing: aIn.sink);
  }

  late final DuplexStreamChannel a;
  late final DuplexStreamChannel b;
}

void main() {
  test('handshake exchange and initial sync over DuplexStreamChannel',
      () async {
    final pair = _LoopbackPair();

    final serverCrdt = MapCrdt(['t']);
    final clientCrdt = MapCrdt(['t']);

    // Connect first, then write to ensure we assert replication

    final serverConnected = Completer<(String, Object?)>();
    final clientConnected = Completer<(String, Object?)>();

    // Start server
    CrdtSync.serverWithChannel(
      serverCrdt,
      pair.a,
      handshakeDataBuilder: (peerId, peerData) => {'from': 'server'},
      onConnect: (peerId, data) => serverConnected.complete((peerId, data)),
      verbose: true,
    );

    // Start client
    CrdtSync.clientWithChannel(
      clientCrdt,
      pair.b,
      handshakeDataBuilder: () => {'from': 'client'},
      onConnect: (peerId, data) => clientConnected.complete((peerId, data)),
      verbose: true,
    );

    final (serverPeer, serverData) = await serverConnected.future;
    final (clientPeer, clientData) = await clientConnected.future;

    expect(serverPeer, clientCrdt.nodeId);
    expect(clientPeer, serverCrdt.nodeId);
    expect(serverData, {'from': 'client'});
    expect(clientData, {'from': 'server'});

    // After handshake, client should receive initial changeset from server
    // Wait for the client's CRDT to emit a change event
    // Write after handshake and verify replication on the client's next change event
    await serverCrdt.put('t', 'k1', {'v': 1});
    Future<bool> hasK1() async {
      final rows = clientCrdt.getChangeset()['t'] ?? [];
      return rows.any((e) => e['key'] == 'k1' && (e['value'] as Map)['v'] == 1);
    }

    final deadline2 = DateTime.now().add(const Duration(seconds: 2));
    var replicated = await hasK1();
    while (!replicated && DateTime.now().isBefore(deadline2)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      replicated = await hasK1();
    }
    expect(replicated, isTrue);
  });
}
