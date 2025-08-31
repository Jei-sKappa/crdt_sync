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

    final serverConnected = Completer<(String, Object?)>();
    final clientConnected = Completer<(String, Object?)>();
    final dataReplicated = Completer<void>();

    // Start server
    CrdtSync.server(
      serverCrdt,
      pair.a,
      handshakeDataBuilder: (peerId, peerData) => {'from': 'server'},
      onConnect: (peerId, data) => serverConnected.complete((peerId, data)),
    );

    // Start client
    CrdtSync.client(
      clientCrdt,
      pair.b,
      handshakeDataBuilder: () => {'from': 'client'},
      onConnect: (peerId, data) => clientConnected.complete((peerId, data)),
    );

    // Wait for handshake completion
    final (serverPeer, serverData) =
        await serverConnected.future.timeout(const Duration(seconds: 2));
    final (clientPeer, clientData) =
        await clientConnected.future.timeout(const Duration(seconds: 2));

    expect(serverPeer, clientCrdt.nodeId);
    expect(clientPeer, serverCrdt.nodeId);
    expect(serverData, {'from': 'client'});
    expect(clientData, {'from': 'server'});

    // Monitor client for data replication using proper event stream
    final subscription = clientCrdt.onTablesChanged.listen((event) {
      if (event.tables.contains('t')) {
        final rows = clientCrdt.getChangeset()['t'] ?? [];
        final hasK1 =
            rows.any((e) => e['key'] == 'k1' && (e['value']! as Map)['v'] == 1);
        if (hasK1 && !dataReplicated.isCompleted) {
          dataReplicated.complete();
        }
      }
    });

    // Write data after handshake completion
    await serverCrdt.put('t', 'k1', {'v': 1});

    // Wait for replication to complete using event-driven pattern
    await dataReplicated.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();

    // Verify final state
    final clientRows = clientCrdt.getChangeset()['t'] ?? [];
    expect(clientRows.length, 1);
    expect(clientRows.first['key'], 'k1');
    expect((clientRows.first['value']! as Map)['v'], 1);
  });

  test('handshake with bidirectional data exchange', () async {
    final pair = _LoopbackPair();
    final serverCrdt = MapCrdt(['messages']);
    final clientCrdt = MapCrdt(['messages']);

    final handshakeComplete = Completer<void>();
    final allDataSynced = Completer<void>();
    var connectionCount = 0;

    void checkCompletion() {
      final serverRecords = serverCrdt.getChangeset()['messages']?.length ?? 0;
      final clientRecords = clientCrdt.getChangeset()['messages']?.length ?? 0;

      if (serverRecords >= 2 &&
          clientRecords >= 2 &&
          !allDataSynced.isCompleted) {
        allDataSynced.complete();
      }
    }

    CrdtSync.server(
      serverCrdt,
      pair.a,
      handshakeDataBuilder: (peerId, peerData) => {
        'role': 'server',
        'capabilities': ['admin']
      },
      onConnect: (peerId, data) {
        connectionCount++;
        if (connectionCount == 2 && !handshakeComplete.isCompleted) {
          handshakeComplete.complete();
        }
      },
    );

    CrdtSync.client(
      clientCrdt,
      pair.b,
      handshakeDataBuilder: () => {'role': 'client', 'user': 'alice'},
      onConnect: (peerId, data) {
        connectionCount++;
        if (connectionCount == 2 && !handshakeComplete.isCompleted) {
          handshakeComplete.complete();
        }
      },
    );

    await handshakeComplete.future.timeout(const Duration(seconds: 2));

    // Monitor both CRDTs for changes
    serverCrdt.onTablesChanged.listen((event) {
      if (event.tables.contains('messages')) {
        checkCompletion();
      }
    });

    clientCrdt.onTablesChanged.listen((event) {
      if (event.tables.contains('messages')) {
        checkCompletion();
      }
    });

    // Write from both sides
    await serverCrdt.put(
        'messages', 'm1', {'text': 'Hello from server', 'sender': 'server'});
    await clientCrdt.put(
        'messages', 'm2', {'text': 'Hello from client', 'sender': 'client'});

    await allDataSynced.future.timeout(const Duration(seconds: 3));

    // Verify both sides have all data
    final serverMessages = serverCrdt.getChangeset()['messages'] ?? [];
    final clientMessages = clientCrdt.getChangeset()['messages'] ?? [];

    expect(serverMessages.length, 2);
    expect(clientMessages.length, 2);

    // Check specific messages exist on both sides
    expect(serverMessages.any((m) => m['key'] == 'm1'), isTrue);
    expect(serverMessages.any((m) => m['key'] == 'm2'), isTrue);
    expect(clientMessages.any((m) => m['key'] == 'm1'), isTrue);
    expect(clientMessages.any((m) => m['key'] == 'm2'), isTrue);
  });

  test('handshake data exchange verification', () async {
    final pair = _LoopbackPair();
    final serverCrdt = MapCrdt(['test']);
    final clientCrdt = MapCrdt(['test']);

    final serverConnected = Completer<Map<String, dynamic>>();
    final clientConnected = Completer<Map<String, dynamic>>();

    CrdtSync.server(
      serverCrdt,
      pair.a,
      handshakeDataBuilder: (peerId, peerData) => {
        'server_id': 'test_server',
        'version': '1.0.0',
        'capabilities': ['sync', 'validate']
      },
      onConnect: (peerId, data) =>
          serverConnected.complete(data! as Map<String, dynamic>),
    );

    CrdtSync.client(
      clientCrdt,
      pair.b,
      handshakeDataBuilder: () =>
          {'client_id': 'test_client', 'version': '1.0.0', 'user': 'alice'},
      onConnect: (peerId, data) =>
          clientConnected.complete(data! as Map<String, dynamic>),
    );

    final serverData =
        await serverConnected.future.timeout(const Duration(seconds: 2));
    final clientData =
        await clientConnected.future.timeout(const Duration(seconds: 2));

    // Verify handshake data was exchanged correctly
    expect(serverData['client_id'], 'test_client');
    expect(serverData['user'], 'alice');
    expect(clientData['server_id'], 'test_server');
    expect((clientData['capabilities'] as List).contains('sync'), isTrue);
  });
}
