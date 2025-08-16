import 'dart:async';
import 'dart:io';

import 'package:crdt/map_crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_server.dart';
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

class _ManualChannel implements SyncChannel {
  final _incoming = StreamController<String>();
  final _outgoing = StreamController<String>();
  final closed = Completer<void>();

  @override
  Stream<String> get stream => _incoming.stream;

  @override
  StreamSink<String> get sink => _outgoing.sink;

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!closed.isCompleted) closed.complete();
    await _outgoing.close();
    await _incoming.close();
  }

  void addIncoming(String data) => _incoming.add(data);
}

void main() {
  group('Robustness', () {
    test('exceptions in validateRecord and mapIncomingChangeset are contained',
        () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['t']);
      final client = MapCrdt(['t']);

      final connected = Completer<void>();
      final processed = Completer<void>();
      var connections = 0;
      var mapperCalled = 0;
      var validatorCalled = 0;

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 2 && !connected.isCompleted) connected.complete();
        },
        validateRecord: (table, record) {
          validatorCalled++;
          if ((record['key'] as String).startsWith('bad_valid')) {
            throw StateError('validator boom');
          }
          return true;
        },
        mapIncomingChangeset: (table, record) {
          mapperCalled++;
          if ((record['key'] as String).startsWith('bad_map')) {
            throw StateError('mapper boom');
          }
          return record;
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 2 && !connected.isCompleted) connected.complete();
        },
      );

      await connected.future.timeout(const Duration(seconds: 2));

      // Send 3 records: one trips validator, one trips mapper, one ok
      await client.put('t', 'bad_valid_1', {'x': 1});
      await client.put('t', 'bad_map_1', {'x': 2});
      await client.put('t', 'ok', {'x': 3});

      // Wait for the OK to arrive server-side
      final sub = server.onTablesChanged.listen((event) {
        if (event.tables.contains('t')) {
          final rows = server.getChangeset()['t'] ?? [];
          final hasOk = rows.any((r) => r['key'] == 'ok');
          if (hasOk && !processed.isCompleted) processed.complete();
        }
      });

      await processed.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // Only the good record should pass through
      final rows = server.getChangeset()['t'] ?? [];
      expect(rows.any((r) => r['key'] == 'ok'), isTrue);
      expect(rows.any((r) => r['key'] == 'bad_valid_1'), isFalse);
      expect(rows.any((r) => r['key'] == 'bad_map_1'), isFalse);
      expect(validatorCalled, greaterThanOrEqualTo(1));
      expect(mapperCalled, greaterThanOrEqualTo(1));
    });

    test('malformed JSON causes graceful close', () async {
      final server = MapCrdt(['t']);
      final channel = _ManualChannel();
      CrdtSync.server(server, channel);
      channel.addIncoming('not json');
      await channel.closed.future.timeout(const Duration(seconds: 1));
    });

    test('handshake supports null and large metadata', () async {
      final pair1 = _LoopbackPair();
      final server = MapCrdt(['t']);
      final client = MapCrdt(['t']);

      final serverConnected = Completer<Object?>();
      final clientConnected = Completer<Object?>();

      // Case 1: null metadata from client
      CrdtSync.server(
        server,
        pair1.a,
        onConnect: (_, data) => serverConnected.complete(data),
      );
      CrdtSync.client(
        client,
        pair1.b,
        handshakeDataBuilder: () => null,
        onConnect: (_, data) => clientConnected.complete(data),
      );

      final serverData1 =
          await serverConnected.future.timeout(const Duration(seconds: 2));
      final clientData1 =
          await clientConnected.future.timeout(const Duration(seconds: 2));

      expect(serverData1, isNull);
      // Server sends null by default unless configured, so allow null or map
      expect(clientData1, anyOf(isNull, isA<Map>()));

      // Case 2: large metadata from client
      final pair3 = _LoopbackPair();
      final serverLarge = Completer<Object?>();
      final clientLarge = Completer<Object?>();

      final large = {
        's': 'x' * 5000,
        'list': List.generate(1000, (i) => i),
        'map': {for (var i = 0; i < 100; i++) 'k$i': 'v$i'},
      };

      CrdtSync.server(
        server,
        pair3.a,
        onConnect: (_, data) => serverLarge.complete(data),
      );
      CrdtSync.client(
        client,
        pair3.b,
        handshakeDataBuilder: () => large,
        onConnect: (_, data) => clientLarge.complete(data),
      );

      final serverData2 =
          await serverLarge.future.timeout(const Duration(seconds: 2));
      final clientData2 =
          await clientLarge.future.timeout(const Duration(seconds: 2));

      expect(serverData2, isA<Map>());
      expect((serverData2 as Map)['s'], (large['s'] as String));
      expect(clientData2, anyOf(isNull, isA<Map>()));
    });

    test('mismatched tables are ignored safely', () async {
      final pair = _LoopbackPair();
      // Server knows only 'server_table'; client writes to 'unknown_table'
      final server = MapCrdt(['server_table']);
      final client = MapCrdt(['server_table', 'unknown_table']);

      final connected = Completer<void>();
      var connections = 0;

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 2 && !connected.isCompleted) connected.complete();
        },
      );
      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 2 && !connected.isCompleted) connected.complete();
        },
      );

      await connected.future.timeout(const Duration(seconds: 2));

      // Client writes to a table that server doesn't manage; should NOT break sync
      await client.put('unknown_table', 'u1', {'x': 1});

      // Also write to a shared table to verify sync continues normally
      final serverSawShared = Completer<void>();
      final sub = server.onTablesChanged.listen((event) {
        if (event.tables.contains('server_table')) {
          final rows = server.getChangeset()['server_table'] ?? [];
          if (rows.any((r) => r['key'] == 's1') &&
              !serverSawShared.isCompleted) {
            serverSawShared.complete();
          }
        }
      });
      await client.put('server_table', 's1', {'x': 2});
      await serverSawShared.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // Verify server ignored unknown table and accepted shared table
      final serverUnknown = server.getChangeset()['unknown_table'] ?? [];
      expect(serverUnknown.isEmpty, isTrue);
      final serverShared = server.getChangeset()['server_table'] ?? [];
      expect(serverShared.any((r) => r['key'] == 's1'), isTrue);
    });

    test('heartbeat/ping triggers disconnect callback after client closes',
        () async {
      final crdtServer = MapCrdt(['t']);
      final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = httpServer.port;

      final connected = Completer<void>();
      final disconnected = Completer<void>();

      // Accept connection and set up server with ping interval
      unawaited(() async {
        final request = await httpServer.first;
        await upgrade(
          crdtServer,
          request,
          pingInterval: const Duration(milliseconds: 100),
          onConnect: (_, __) {
            if (!connected.isCompleted) connected.complete();
          },
          onDisconnect: (_, __, ___) {
            if (!disconnected.isCompleted) disconnected.complete();
          },
        );
      }());

      // Proper WebSocket client using CrdtSync to ensure handshake completes
      final client = MapCrdt(['t']);
      final wsClient = IOWebSocketChannel.connect('ws://localhost:$port');
      final clientSync = CrdtSync.websocketClient(client, wsClient);

      // Wait for server to observe connect, then close the client
      await connected.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await clientSync.close(4000, 'bye');

      await disconnected.future.timeout(const Duration(seconds: 3));

      await httpServer.close(force: true);
    });
  });
}
