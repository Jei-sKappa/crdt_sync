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

    final serverReceived = Completer<Map<String, int>>();
    final clientSent = Completer<Map<String, int>>();

    // Server rejects records where value.blocked == true and tags accepted ones
    CrdtSync.serverWithChannel(
      server,
      pair.a,
      validateRecord: (table, record) async {
        final blocked = (record['value'] as Map)['blocked'] == true;
        return !blocked;
      },
      mapIncomingChangeset: (table, record) {
        final value = Map<String, dynamic>.from(record['value'] as Map);
        value['touched'] = true;
        final copy = Map<String, dynamic>.from(record);
        copy['value'] = value;
        return copy;
      },
      onChangesetReceived: (_, counts) {
        if (!serverReceived.isCompleted) serverReceived.complete(counts);
      },
      verbose: true,
    );

    CrdtSync.clientWithChannel(
      client,
      pair.b,
      onChangesetSent: (_, counts) {
        if (!clientSent.isCompleted) clientSent.complete(counts);
      },
      verbose: true,
    );

    // Wait for handshake
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Client writes two records: one accepted and one rejected
    await client.put('t', 'ok', {'blocked': false, 'value': 1});
    // Allow a tiny delay to avoid coalescing with the next write in some schedulers
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await client.put('t', 'bad', {'blocked': true, 'value': 2});

    // Wait for transfer and merge (first send may batch)
    final sentCounts =
        await clientSent.future.timeout(const Duration(seconds: 2));
    // Two puts may coalesce by table-level batching; assert at least one record sent
    expect(sentCounts['t'], inInclusiveRange(1, 2));

    final recvCounts =
        await serverReceived.future.timeout(const Duration(seconds: 2));
    expect(recvCounts['t'], 1);

    // Verify server has only the accepted record and it was mapped
    // Wait until server CRDT reports a change
    Future<List<Map<String, dynamic>>> getServerRecords() async =>
        (server.getChangeset()['t'] ?? [])
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
    List<Map<String, dynamic>> serverRecords = await getServerRecords();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (serverRecords.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      serverRecords = await getServerRecords();
    }
    final accepted = serverRecords.where((r) => r['key'] == 'ok').toList();
    expect(accepted, isNotEmpty);
    final acceptedRecord = accepted.first;
    expect((acceptedRecord['value'] as Map)['touched'], true);
  });

  test('CrdtSync.close triggers onDisconnect with DuplexStreamChannel',
      () async {
    final pair = _LoopbackPair();
    final server = MapCrdt(['t']);
    final client = MapCrdt(['t']);

    late final CrdtSync serverSync;
    final disconnected = Completer<void>();

    serverSync = CrdtSync.serverWithChannel(
      server,
      pair.a,
      onDisconnect: (_, code, reason) {
        expect(code, isNull);
        expect(reason, isNull);
        disconnected.complete();
      },
    );

    CrdtSync.clientWithChannel(
      client,
      pair.b,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await serverSync.close();
    await disconnected.future.timeout(const Duration(seconds: 2));
  });

  test('WebSocket integration: upgrade server and CrdtSyncClient connects',
      () async {
    final crdtServer = MapCrdt(['t']);

    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = httpServer.port;

    // Accept a single connection then keep serving until test ends
    unawaited(() async {
      await for (final req in httpServer) {
        final ws = await WebSocketTransformer.upgrade(req);
        final channel = IOWebSocketChannel(ws);
        // Start server sync for this connection
        CrdtSync.server(crdtServer, channel);
      }
    }());

    final crdtClient = MapCrdt(['t']);

    final stateChanges = <SocketState>[];
    final connected = Completer<void>();
    final disconnected = Completer<void>();

    final client = CrdtSyncClient(
      crdtClient,
      Uri.parse('ws://localhost:$port'),
      onConnecting: () => stateChanges.add(SocketState.connecting),
      onConnect: (_, __) {
        stateChanges.add(SocketState.connected);
        connected.complete();
      },
      onDisconnect: (_, __, ___) {
        stateChanges.add(SocketState.disconnected);
        if (!disconnected.isCompleted) disconnected.complete();
      },
    );
    client.watchState.listen(stateChanges.add);

    client.connect();
    await connected.future.timeout(const Duration(seconds: 5));

    // Disconnect explicitly
    await client.disconnect(4000, 'bye');
    await disconnected.future.timeout(const Duration(seconds: 5));

    // Cleanup
    await httpServer.close(force: true);

    // Verify expected state changes occurred
    expect(stateChanges.contains(SocketState.connecting), isTrue);
    expect(stateChanges.contains(SocketState.connected), isTrue);
    expect(stateChanges.contains(SocketState.disconnected), isTrue);
  });
}
