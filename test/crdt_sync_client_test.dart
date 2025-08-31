import 'dart:async';
import 'dart:io';

import 'package:crdt/map_crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  group('CrdtSyncClient Reconnection', () {
    late HttpServer server;
    late int port;
    late MapCrdt serverCrdt;

    setUp(() async {
      serverCrdt = MapCrdt(['test']);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('exponential backoff reconnection strategy', () async {
      var connectionAttempts = 0;
      final connectionTimes = <DateTime>[];

      // Server that rejects first few connections
      unawaited(() async {
        await for (final req in server) {
          connectionAttempts++;
          connectionTimes.add(DateTime.now());

          if (connectionAttempts <= 2) {
            // Reject first two connections
            req.response.statusCode = 503;
            await req.response.close();
          } else {
            // Accept third connection
            final ws = await WebSocketTransformer.upgrade(req);
            final channel = IOWebSocketChannel(ws);
            CrdtSync.websocketServer(serverCrdt, channel);
          }
        }
      }());

      final client = MapCrdt(['test']);
      final stateChanges = <ConnectionState>[];
      final connected = Completer<void>();

      final syncClient = CrdtSyncClient.websocket(
        client,
        Uri.parse('ws://localhost:$port'),
        onConnecting: () => stateChanges.add(ConnectionState.connecting),
        onConnect: (_, __) {
          stateChanges.add(ConnectionState.connected);
          connected.complete();
        },
        onDisconnect: (_, __, ___) =>
            stateChanges.add(ConnectionState.disconnected),
        minReconnectDelay: 1,
        maxReconnectDelay: 4,
      );

      // Explicitly not awaiting to test the reconnect logic
      unawaited(syncClient.connect());
      await connected.future.timeout(const Duration(seconds: 8));

      // Verify exponential backoff occurred
      expect(connectionAttempts, 3);
      expect(connectionTimes.length, 3);

      // Check that delays increased (allowing some tolerance for timing)
      if (connectionTimes.length >= 3) {
        final delay1 =
            connectionTimes[1].difference(connectionTimes[0]).inMilliseconds;
        final delay2 =
            connectionTimes[2].difference(connectionTimes[1]).inMilliseconds;

        expect(delay1, greaterThanOrEqualTo(800)); // First retry after ~1s
        expect(delay2, greaterThanOrEqualTo(1800)); // Second retry after ~2s
      }

      // Verify final state
      expect(syncClient.state, ConnectionState.connected);
      expect(stateChanges.contains(ConnectionState.connecting), isTrue);
      expect(stateChanges.contains(ConnectionState.connected), isTrue);

      await syncClient.disconnect();
    });

    test('reconnection after unexpected disconnect', () async {
      var serverConnections = 0;
      late IOWebSocketChannel firstConnection;

      unawaited(() async {
        await for (final req in server) {
          serverConnections++;
          final ws = await WebSocketTransformer.upgrade(req);
          final channel = IOWebSocketChannel(ws);

          if (serverConnections == 1) {
            firstConnection = channel;
          }

          CrdtSync.websocketServer(serverCrdt, channel);
        }
      }());

      final client = MapCrdt(['test']);
      final connected = Completer<void>();
      final disconnected = Completer<void>();
      final reconnected = Completer<void>();
      var connectCount = 0;

      final syncClient = CrdtSyncClient.websocket(
        client,
        Uri.parse('ws://localhost:$port'),
        onConnect: (_, __) {
          connectCount++;
          if (connectCount == 1) {
            connected.complete();
          } else if (connectCount == 2) {
            reconnected.complete();
          }
        },
        onDisconnect: (_, __, ___) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
        minReconnectDelay: 1,
        maxReconnectDelay: 4,
      );

      // Explicitly not awaiting to test the reconnect logic
      unawaited(syncClient.connect());
      await connected.future.timeout(const Duration(seconds: 5));

      // Force disconnect the first connection
      await firstConnection.sink.close();
      await disconnected.future.timeout(const Duration(seconds: 5));

      // Wait for automatic reconnection
      await reconnected.future.timeout(const Duration(seconds: 10));

      expect(serverConnections, 2);
      expect(connectCount, 2);
      expect(syncClient.state, ConnectionState.connected);

      await syncClient.disconnect();
    });

    test('manual disconnect stops automatic reconnection', () async {
      var connectionAttempts = 0;

      // Server that always rejects connections
      unawaited(() async {
        await for (final req in server) {
          connectionAttempts++;
          req.response.statusCode = 503;
          await req.response.close();
        }
      }());

      final client = MapCrdt(['test']);
      final syncClient = CrdtSyncClient.websocket(
        client,
        Uri.parse('ws://localhost:$port'),
        minReconnectDelay: 1,
        maxReconnectDelay: 1,
      );

      // Explicitly not awaiting to test the reconnect logic
      unawaited(syncClient.connect());

      // Let it try to connect for a bit
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // Manually disconnect
      await syncClient.disconnect();

      final attemptsBeforeDisconnect = connectionAttempts;

      // Wait a bit more and verify no more connection attempts
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(connectionAttempts, attemptsBeforeDisconnect);
      expect(syncClient.state, ConnectionState.disconnected);
    });

    test('state transitions and watchState stream', () async {
      unawaited(() async {
        await for (final req in server) {
          final ws = await WebSocketTransformer.upgrade(req);
          final channel = IOWebSocketChannel(ws);
          CrdtSync.websocketServer(serverCrdt, channel);
        }
      }());

      final client = MapCrdt(['test']);
      final stateChanges = <ConnectionState>[];
      final connected = Completer<void>();
      final disconnected = Completer<void>();

      final syncClient = CrdtSyncClient.websocket(
        client,
        Uri.parse('ws://localhost:$port'),
        onConnect: (_, __) => connected.complete(),
        onDisconnect: (_, __, ___) => disconnected.complete(),
        minReconnectDelay: 1,
        maxReconnectDelay: 4,
      );

      final subscription = syncClient.watchState.listen(stateChanges.add);

      try {
        expect(syncClient.state, ConnectionState.disconnected);

        // Explicitly not awaiting to test the reconnect logic
        unawaited(syncClient.connect());
        await connected.future.timeout(const Duration(seconds: 5));

        expect(syncClient.state, ConnectionState.connected);

        await syncClient.disconnect();
        await disconnected.future.timeout(const Duration(seconds: 5));

        expect(syncClient.state, ConnectionState.disconnected);

        // Verify state change sequence
        expect(
            stateChanges,
            containsAllInOrder([
              ConnectionState.connecting,
              ConnectionState.connected,
              ConnectionState.disconnected,
            ]));
      } finally {
        await subscription.cancel();
      }
    });

    test('data persistence across reconnections', () async {
      var serverConnections = 0;
      late IOWebSocketChannel firstConnection;

      unawaited(() async {
        await for (final req in server) {
          serverConnections++;
          final ws = await WebSocketTransformer.upgrade(req);
          final channel = IOWebSocketChannel(ws);

          if (serverConnections == 1) {
            firstConnection = channel;
          }

          CrdtSync.websocketServer(serverCrdt, channel);
        }
      }());

      final client = MapCrdt(['test']);
      final connected = Completer<void>();
      final disconnected = Completer<void>();
      final reconnected = Completer<void>();
      final dataReplicated = Completer<void>();
      var connectCount = 0;

      final syncClient = CrdtSyncClient.websocket(
        client,
        Uri.parse('ws://localhost:$port'),
        onConnect: (_, __) {
          connectCount++;
          if (connectCount == 1) {
            connected.complete();
          } else if (connectCount == 2) {
            reconnected.complete();
          }
        },
        onDisconnect: (_, __, ___) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
        minReconnectDelay: 1,
        maxReconnectDelay: 4,
      );

      // Explicitly not awaiting to test the reconnect logic
      unawaited(syncClient.connect());
      await connected.future.timeout(const Duration(seconds: 5));

      // Add data while connected
      await client.put('test', 'offline_data', {'created': 'while_connected'});

      // Force disconnect
      await firstConnection.sink.close();
      await disconnected.future.timeout(const Duration(seconds: 5));

      // Add data while disconnected
      await client
          .put('test', 'offline_data2', {'created': 'while_disconnected'});

      // Monitor server for data arrival after reconnection
      final subscription = serverCrdt.onTablesChanged.listen((event) {
        if (event.tables.contains('test')) {
          final records = serverCrdt.getChangeset()['test'] ?? [];
          if (records.length >= 2 && !dataReplicated.isCompleted) {
            dataReplicated.complete();
          }
        }
      });

      // Wait for automatic reconnection
      await reconnected.future.timeout(const Duration(seconds: 10));

      // Wait for offline data to sync
      await dataReplicated.future.timeout(const Duration(seconds: 5));
      await subscription.cancel();

      // Verify all data reached server
      final serverRecords = serverCrdt.getChangeset()['test'] ?? [];
      expect(serverRecords.length, 2);

      final keys = serverRecords.map((r) => r['key']).toSet();
      expect(keys, containsAll(['offline_data', 'offline_data2']));

      await syncClient.disconnect();
    });

    test('connection failure with invalid URI', () async {
      final client = MapCrdt(['test']);
      final stateChanges = <ConnectionState>[];

      final syncClient = CrdtSyncClient.websocket(
        client,
        Uri.parse('ws://nonexistent.example.com:12345'),
        onConnecting: () => stateChanges.add(ConnectionState.connecting),
        onConnect: (_, __) => stateChanges.add(ConnectionState.connected),
        onDisconnect: (_, __, ___) =>
            stateChanges.add(ConnectionState.disconnected),
        minReconnectDelay: 1,
        maxReconnectDelay: 1,
      );

      final subscription = syncClient.watchState.listen(stateChanges.add);

      try {
        // Explicitly not awaiting to test the reconnect logic
        unawaited(syncClient.connect());

        // Wait for multiple failed connection attempts
        await Future<void>.delayed(const Duration(milliseconds: 1500));

        await syncClient.disconnect();

        // Should have attempted to connect multiple times
        final connectingCount =
            stateChanges.where((s) => s == ConnectionState.connecting).length;
        expect(connectingCount, greaterThan(1));

        // Should never have connected
        expect(stateChanges.contains(ConnectionState.connected), isFalse);

        // Should have disconnected after manual disconnect
        expect(stateChanges.contains(ConnectionState.disconnected), isTrue);
      } finally {
        await subscription.cancel();
      }
    });
  });
}
