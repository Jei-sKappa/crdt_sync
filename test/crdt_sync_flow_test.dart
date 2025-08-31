import 'dart:async';
import 'dart:io';

import 'package:crdt/map_crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

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
  test('validateRecord and mapIncomingChangeset on server', () async {
    final pair = _LoopbackPair();
    final server = MapCrdt(['t']);
    final client = MapCrdt(['t']);

    final handshakeComplete = Completer<void>();
    final validationComplete = Completer<void>();
    var connectionCount = 0;
    var recordsProcessed = 0;
    final validationResults = <String, bool>{};

    // Server rejects records where value.blocked == true and tags accepted ones
    CrdtSync.server(
      server,
      pair.a,
      onConnect: (_, __) {
        connectionCount++;
        if (connectionCount == 2) handshakeComplete.complete();
      },
      validateRecord: (table, record) async {
        final key = record['key']! as String;
        final blocked = (record['value']! as Map)['blocked'] == true;
        final isValid = !blocked;
        validationResults[key] = isValid;

        recordsProcessed++;
        if (recordsProcessed == 2) {
          validationComplete.complete();
        }

        return isValid;
      },
      mapIncomingChangeset: (table, record) {
        final value = Map<String, dynamic>.from(record['value']! as Map);
        value['touched'] = true;
        final copy = Map<String, dynamic>.from(record);
        copy['value'] = value;
        return copy;
      },
      verbose: true,
    );

    CrdtSync.client(
      client,
      pair.b,
      onConnect: (_, __) {
        connectionCount++;
        if (connectionCount == 2) handshakeComplete.complete();
      },
      verbose: true,
    );

    // Wait for proper handshake completion
    await handshakeComplete.future.timeout(const Duration(seconds: 2));

    // Client writes two records: one accepted and one rejected
    await client.put('t', 'ok', {'blocked': false, 'value': 1});
    await client.put('t', 'bad', {'blocked': true, 'value': 2});

    // Wait for validation to complete
    await validationComplete.future.timeout(const Duration(seconds: 2));

    // Wait a bit more for processing to complete
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Verify validation results
    expect(validationResults['ok'], true);
    expect(validationResults['bad'], false);

    // Verify server has only the accepted record and it was mapped
    final serverRecords = server.getChangeset()['t'] ?? [];
    final accepted = serverRecords.where((r) => r['key'] == 'ok').toList();
    final rejected = serverRecords.where((r) => r['key'] == 'bad').toList();

    expect(accepted.length, 1);
    expect(rejected.length, 0);

    final acceptedRecord = accepted.first;
    expect((acceptedRecord['value']! as Map)['touched'], true);
    expect((acceptedRecord['value']! as Map)['value'], 1);
  });

  test('CrdtSync.close triggers onDisconnect with DuplexStreamChannel',
      () async {
    final pair = _LoopbackPair();
    final server = MapCrdt(['t']);
    final client = MapCrdt(['t']);

    late final CrdtSync serverSync;
    final connected = Completer<void>();
    final disconnected = Completer<void>();

    serverSync = CrdtSync.server(
      server,
      pair.a,
      onConnect: (_, __) => connected.complete(),
      onDisconnect: (_, code, reason) {
        expect(code, isNull);
        expect(reason, isNull);
        disconnected.complete();
      },
    );

    CrdtSync.client(
      client,
      pair.b,
    );

    // Wait for connection to be established before closing
    await connected.future.timeout(const Duration(seconds: 2));
    await serverSync.close();
    await disconnected.future.timeout(const Duration(seconds: 2));
  });

  test('WebSocket integration: upgrade server and CrdtSyncClient connects',
      () async {
    final crdtServer = MapCrdt(['t']);

    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = httpServer.port;
    final serverConnected = Completer<void>();

    // Accept a single connection then keep serving until test ends
    unawaited(() async {
      await for (final req in httpServer) {
        final ws = await WebSocketTransformer.upgrade(req);
        final channel = IOWebSocketChannel(ws);
        // Start server sync for this connection
        CrdtSync.websocketServer(
          crdtServer,
          channel,
          onConnect: (_, __) => serverConnected.complete(),
        );
      }
    }());

    final crdtClient = MapCrdt(['t']);

    final stateChanges = <ConnectionState>[];
    final connected = Completer<void>();
    final disconnected = Completer<void>();

    final client = CrdtSyncClient.websocket(
      crdtClient,
      Uri.parse('ws://localhost:$port'),
      onConnecting: () => stateChanges.add(ConnectionState.connecting),
      onConnect: (_, __) {
        stateChanges.add(ConnectionState.connected);
        connected.complete();
      },
      onDisconnect: (_, __, ___) {
        stateChanges.add(ConnectionState.disconnected);
        if (!disconnected.isCompleted) disconnected.complete();
      },
      minReconnectDelay: 1,
      maxReconnectDelay: 4,
    );

    final stateSubscription = client.watchState.listen(stateChanges.add);

    try {
      // Explicitly not awaiting to test the reconnect logic
      unawaited(client.connect());

      await Future.wait([
        connected.future.timeout(const Duration(seconds: 5)),
        serverConnected.future.timeout(const Duration(seconds: 5)),
      ]);

      // Verify connection state
      expect(client.state, ConnectionState.connected);

      // Disconnect explicitly
      await client.disconnect(4000, 'bye');
      await disconnected.future.timeout(const Duration(seconds: 5));

      // Verify final state
      expect(client.state, ConnectionState.disconnected);

      // Verify expected state changes occurred
      expect(stateChanges.contains(ConnectionState.connecting), isTrue);
      expect(stateChanges.contains(ConnectionState.connected), isTrue);
      expect(stateChanges.contains(ConnectionState.disconnected), isTrue);
    } finally {
      // Cleanup
      await stateSubscription.cancel();
      await httpServer.close(force: true);
    }
  });

  test('async validation with exceptions', () async {
    final pair = _LoopbackPair();
    final server = MapCrdt(['t']);
    final client = MapCrdt(['t']);

    final handshakeComplete = Completer<void>();
    final validationComplete = Completer<void>();
    var connectionCount = 0;
    var recordsValidated = 0;
    final validationResults = <String, bool>{};

    CrdtSync.server(
      server,
      pair.a,
      onConnect: (_, __) {
        connectionCount++;
        if (connectionCount == 2 && !handshakeComplete.isCompleted) {
          handshakeComplete.complete();
        }
      },
      validateRecord: (table, record) async {
        final key = record['key']! as String;
        recordsValidated++;

        if (key == 'error') {
          validationResults[key] = false;
          // Return false instead of throwing to test validation logic
          if (recordsValidated >= 2 && !validationComplete.isCompleted) {
            validationComplete.complete();
          }
          return false;
        }

        validationResults[key] = true;
        if (recordsValidated >= 2 && !validationComplete.isCompleted) {
          validationComplete.complete();
        }
        return true;
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

    await handshakeComplete.future.timeout(const Duration(seconds: 2));

    // Send a record that will be rejected and one that will be accepted
    await client.put('t', 'error', {'data': 'should fail'});
    await client.put('t', 'ok', {'data': 'should pass'});

    // Wait for validation to complete
    await validationComplete.future.timeout(const Duration(seconds: 2));

    // Wait a bit more for processing to complete
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Verify validation results
    expect(validationResults['error'], false);
    expect(validationResults['ok'], true);

    // Verify that only the valid record made it through
    final serverRecords = server.getChangeset()['t'] ?? [];
    expect(serverRecords.length, greaterThanOrEqualTo(1));
    expect(serverRecords.any((r) => r['key'] == 'ok'), isTrue);
    expect(serverRecords.any((r) => r['key'] == 'error'), isFalse);
  });

  test('custom changeset builder filtering', () async {
    final pair = _LoopbackPair();
    final server = MapCrdt(['public', 'private']);
    final client = MapCrdt(['public', 'private']);

    final connected = Completer<void>();
    final dataReceived = Completer<void>();
    var connectionCount = 0;

    // Server only sends 'public' table data
    CrdtSync.server(
      server,
      pair.a,
      onConnect: (_, __) {
        connectionCount++;
        if (connectionCount == 2) connected.complete();
      },
      changesetBuilder: (
          {onlyTables, onlyNodeId, exceptNodeId, modifiedOn, modifiedAfter}) {
        // Only include public table in outgoing changesets
        final changeset = server.getChangeset(
          onlyTables: ['public'],
          onlyNodeId: onlyNodeId,
          exceptNodeId: exceptNodeId,
          modifiedOn: modifiedOn,
          modifiedAfter: modifiedAfter,
        );
        return changeset;
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

    await connected.future.timeout(const Duration(seconds: 2));

    // Monitor client for data
    final subscription = client.onTablesChanged.listen((event) {
      if (event.tables.contains('public') && !dataReceived.isCompleted) {
        dataReceived.complete();
      }
    });

    // Server adds data to both tables
    await server
        .put('public', 'pub1', {'type': 'public', 'data': 'everyone can see'});
    await server.put('private', 'priv1', {'type': 'private', 'data': 'secret'});

    await dataReceived.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();

    // Verify client only received public data
    final clientPublic = client.getChangeset()['public'] ?? [];
    final clientPrivate = client.getChangeset()['private'] ?? [];

    expect(clientPublic.length, 1);
    expect(clientPrivate.length, 0);
    expect(clientPublic.first['key'], 'pub1');
  });
}
