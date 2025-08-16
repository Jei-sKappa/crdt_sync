import 'dart:async';

import 'package:crdt/map_crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:test/test.dart';

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
  group('Basic CRDT Sync Functionality', () {
    test('basic client-server sync with proper event synchronization',
        () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['users']);
      final client = MapCrdt(['users']);

      final serverConnected = Completer<String>();
      final clientConnected = Completer<String>();
      final dataReady = Completer<void>();

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (peerId, _) => serverConnected.complete(peerId),
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (peerId, _) => clientConnected.complete(peerId),
      );

      // Wait for proper handshake completion
      final serverPeerId =
          await serverConnected.future.timeout(Duration(seconds: 2));
      final clientPeerId =
          await clientConnected.future.timeout(Duration(seconds: 2));

      expect(serverPeerId, equals(client.nodeId));
      expect(clientPeerId, equals(server.nodeId));

      // Add data to client and wait for sync to server
      await client.put('users', 'user1', {'name': 'Alice', 'age': 30});

      // Use server's change stream to know when data arrives
      final subscription = server.onTablesChanged.listen((event) {
        if (event.tables.contains('users')) {
          dataReady.complete();
        }
      });

      await dataReady.future.timeout(Duration(seconds: 2));
      await subscription.cancel();

      // Verify data reached server
      final serverData = server.getChangeset()['users']!;
      expect(serverData.length, 1);
      expect(serverData.first['key'], 'user1');
      expect((serverData.first['value'] as Map)['name'], 'Alice');
    });

    test('server-to-client sync works correctly', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['products']);
      final client = MapCrdt(['products']);

      final handshakeComplete = Completer<void>();
      final dataReady = Completer<void>();
      var connectionCount = 0;

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2 && !handshakeComplete.isCompleted) {
            handshakeComplete.complete();
          }
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2 && !handshakeComplete.isCompleted) {
            handshakeComplete.complete();
          }
        },
      );

      await handshakeComplete.future.timeout(Duration(seconds: 2));

      // Wait for client to receive the data
      final subscription = client.onTablesChanged.listen((event) {
        if (event.tables.contains('products') && !dataReady.isCompleted) {
          dataReady.complete();
        }
      });

      // Add data to server after connection is established
      await server.put('products', 'prod1', {'name': 'Widget', 'price': 10.99});

      await dataReady.future.timeout(Duration(seconds: 2));
      await subscription.cancel();

      // Verify data reached client
      final clientData = client.getChangeset()['products']!;
      expect(clientData.length, 1);
      expect(clientData.first['key'], 'prod1');
      expect((clientData.first['value'] as Map)['name'], 'Widget');
    });

    test('multiple table sync works correctly', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['users', 'posts']);
      final client = MapCrdt(['users', 'posts']);

      final connected = Completer<void>();
      final allDataReceived = Completer<void>();
      var connectionCount = 0;
      var tablesReceived = <String>{};

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) connected.complete();
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) connected.complete();
        },
      );

      await connected.future.timeout(Duration(seconds: 2));

      // Monitor for both tables to receive data
      final subscription = server.onTablesChanged.listen((event) {
        tablesReceived.addAll(event.tables);
        if (tablesReceived.containsAll(['users', 'posts'])) {
          allDataReceived.complete();
        }
      });

      // Write to multiple tables from client
      await client.put('users', 'u1', {'name': 'Bob'});
      await client.put('posts', 'p1', {'title': 'Hello World', 'author': 'u1'});

      await allDataReceived.future.timeout(Duration(seconds: 2));
      await subscription.cancel();

      // Verify both tables have data
      final serverUsers = server.getChangeset()['users']!;
      final serverPosts = server.getChangeset()['posts']!;

      expect(serverUsers.length, 1);
      expect(serverPosts.length, 1);
      expect(serverUsers.first['key'], 'u1');
      expect(serverPosts.first['key'], 'p1');
    });

    test('connection cleanup works properly', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['test']);
      final client = MapCrdt(['test']);

      final connected = Completer<void>();
      final disconnected = Completer<void>();
      late CrdtSync serverSync;

      serverSync = CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          if (!connected.isCompleted) connected.complete();
        },
        onDisconnect: (_, __, ___) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );

      CrdtSync.client(client, pair.b);

      await connected.future.timeout(Duration(seconds: 2));

      // Store peer ID before closing
      final peerId = serverSync.peerId;
      expect(peerId, isNotNull);

      // Close the connection
      await serverSync.close();

      await disconnected.future.timeout(Duration(seconds: 2));
    });
  });

  group('Error Scenarios', () {
    test('validates peer node IDs are different', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['test']);
      final client = MapCrdt(['test']);

      final serverConnected = Completer<String>();
      final clientConnected = Completer<String>();

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (peerId, _) {
          expect(peerId, isNotEmpty);
          expect(peerId, isNot(equals(server.nodeId)));
          if (!serverConnected.isCompleted) serverConnected.complete(peerId);
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (peerId, _) {
          expect(peerId, isNotEmpty);
          expect(peerId, isNot(equals(client.nodeId)));
          if (!clientConnected.isCompleted) clientConnected.complete(peerId);
        },
      );

      final serverPeerId =
          await serverConnected.future.timeout(Duration(seconds: 2));
      final clientPeerId =
          await clientConnected.future.timeout(Duration(seconds: 2));

      // Verify peer IDs are correctly exchanged
      expect(serverPeerId, equals(client.nodeId));
      expect(clientPeerId, equals(server.nodeId));
    });

    test('handles connection drop during normal operation', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['test']);
      final client = MapCrdt(['test']);

      final connected = Completer<void>();
      final disconnected = Completer<void>();

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) => connected.complete(),
        onDisconnect: (_, __, ___) => disconnected.complete(),
      );

      CrdtSync.client(client, pair.b);

      await connected.future.timeout(Duration(seconds: 2));

      // Simulate connection drop
      await pair.a.close();

      await disconnected.future.timeout(Duration(seconds: 2));
    });
  });
}
