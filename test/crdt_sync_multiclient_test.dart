import 'dart:async';

import 'package:crdt/crdt.dart';
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
  group('Multi-client consistency', () {
    test('fan-out replication across two clients via server', () async {
      final pairA = _LoopbackPair();
      final pairB = _LoopbackPair();

      final server = MapCrdt(['msgs']);
      final clientA = MapCrdt(['msgs']);
      final clientB = MapCrdt(['msgs']);

      final connected = Completer<void>();
      var connections = 0;

      // Start server-side syncs for both connections
      CrdtSync.server(
        server,
        pairA.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );
      CrdtSync.server(
        server,
        pairB.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );

      // Start clients
      CrdtSync.client(
        clientA,
        pairA.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );
      CrdtSync.client(
        clientB,
        pairB.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );

      await connected.future.timeout(const Duration(seconds: 3));

      // A writes -> expect server and B receive
      final serverSawA1 = Completer<void>();
      final bSawA1 = Completer<void>();
      final subServer1 = server.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = server.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'a1') && !serverSawA1.isCompleted) {
            serverSawA1.complete();
          }
        }
      });
      final subB1 = clientB.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = clientB.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'a1') && !bSawA1.isCompleted) {
            bSawA1.complete();
          }
        }
      });

      await clientA.put('msgs', 'a1', {'from': 'A'});
      await Future.wait([
        serverSawA1.future.timeout(const Duration(seconds: 3)),
        bSawA1.future.timeout(const Duration(seconds: 3)),
      ]);
      await subServer1.cancel();
      await subB1.cancel();

      // B writes -> expect server and A receive
      final serverSawB1 = Completer<void>();
      final aSawB1 = Completer<void>();
      final subServer2 = server.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = server.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'b1') && !serverSawB1.isCompleted) {
            serverSawB1.complete();
          }
        }
      });
      final subA1 = clientA.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = clientA.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'b1') && !aSawB1.isCompleted) {
            aSawB1.complete();
          }
        }
      });

      await clientB.put('msgs', 'b1', {'from': 'B'});
      await Future.wait([
        serverSawB1.future.timeout(const Duration(seconds: 3)),
        aSawB1.future.timeout(const Duration(seconds: 3)),
      ]);
      await subServer2.cancel();
      await subA1.cancel();

      // Verify convergence
      final serverRows = server.getChangeset()['msgs'] ?? [];
      final clientARows = clientA.getChangeset()['msgs'] ?? [];
      final clientBRows = clientB.getChangeset()['msgs'] ?? [];
      expect(serverRows.length, 2);
      expect(clientARows.length, 2);
      expect(clientBRows.length, 2);
      final keys = serverRows.map((e) => e['key']).toSet();
      expect(keys, containsAll(['a1', 'b1']));
    });

    test('two clients concurrent same-key updates converge', () async {
      final pairA = _LoopbackPair();
      final pairB = _LoopbackPair();

      final server = MapCrdt(['docs']);
      final clientA = MapCrdt(['docs']);
      final clientB = MapCrdt(['docs']);

      final connected = Completer<void>();
      var connections = 0;

      CrdtSync.server(
        server,
        pairA.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );
      CrdtSync.server(
        server,
        pairB.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );
      CrdtSync.client(
        clientA,
        pairA.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );
      CrdtSync.client(
        clientB,
        pairB.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );

      await connected.future.timeout(const Duration(seconds: 3));

      final converged = Completer<void>();

      void check() {
        final s = server.getChangeset()['docs'] ?? [];
        final a = clientA.getChangeset()['docs'] ?? [];
        final b = clientB.getChangeset()['docs'] ?? [];
        final sDoc = s.where((r) => r['key'] == 'doc1').toList();
        final aDoc = a.where((r) => r['key'] == 'doc1').toList();
        final bDoc = b.where((r) => r['key'] == 'doc1').toList();
        if (sDoc.length == 1 && aDoc.length == 1 && bDoc.length == 1) {
          if (!converged.isCompleted) converged.complete();
        }
      }

      final subs = <StreamSubscription<({Hlc hlc, Iterable<String> tables})>>[
        server.onTablesChanged.listen((_) => check()),
        clientA.onTablesChanged.listen((_) => check()),
        clientB.onTablesChanged.listen((_) => check()),
      ];

      await Future.wait([
        clientA.put('docs', 'doc1', {
          'title': 'Document 1',
          'content': 'Updated by A',
          'version': 1,
          'modified_by': 'A',
        }),
        clientB.put('docs', 'doc1', {
          'title': 'Document 1',
          'content': 'Updated by B',
          'version': 1,
          'modified_by': 'B',
        }),
      ]);

      await converged.future.timeout(const Duration(seconds: 4));
      for (final s in subs) {
        await s.cancel();
      }

      final sList = server.getChangeset()['docs'] ?? [];
      final aList = clientA.getChangeset()['docs'] ?? [];
      final bList = clientB.getChangeset()['docs'] ?? [];
      final sDoc = sList.where((r) => r['key'] == 'doc1').first;
      final aDoc = aList.where((r) => r['key'] == 'doc1').first;
      final bDoc = bList.where((r) => r['key'] == 'doc1').first;

      expect(sDoc['hlc'], aDoc['hlc']);
      expect(sDoc['hlc'], bDoc['hlc']);
      expect(sDoc['value'], aDoc['value']);
      expect(sDoc['value'], bDoc['value']);
    });

    test('offline catch-up across clients and replay offline writes', () async {
      final pairA1 = _LoopbackPair();
      final pairB = _LoopbackPair();

      final server = MapCrdt(['msgs']);
      final clientA = MapCrdt(['msgs']);
      final clientB = MapCrdt(['msgs']);

      final connected1 = Completer<void>();
      var connections = 0;

      CrdtSync.server(
        server,
        pairA1.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 3 && !connected1.isCompleted) {
            connected1.complete();
          }
        },
      );
      CrdtSync.server(
        server,
        pairB.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 3 && !connected1.isCompleted) {
            connected1.complete();
          }
        },
      );
      CrdtSync.client(
        clientA,
        pairA1.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 3 && !connected1.isCompleted) {
            connected1.complete();
          }
        },
      );
      CrdtSync.client(clientB, pairB.b);

      await connected1.future.timeout(const Duration(seconds: 3));

      // Disconnect A (simulate offline)
      await pairA1.a.close();

      // B writes while A is offline
      final serverSawBOffline = Completer<void>();
      final subServerB = server.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = server.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'b_offline1') &&
              !serverSawBOffline.isCompleted) {
            serverSawBOffline.complete();
          }
        }
      });
      await clientB.put('msgs', 'b_offline1', {'from': 'B_offline'});
      await serverSawBOffline.future.timeout(const Duration(seconds: 3));
      await subServerB.cancel();

      // A writes offline (no connection)
      await clientA.put('msgs', 'a_offline1', {'from': 'A_offline'});

      // Reconnect A using a new pair
      final pairA2 = _LoopbackPair();
      final reconnected = Completer<void>();
      var reconnections = 0;
      CrdtSync.server(
        server,
        pairA2.a,
        onConnect: (_, __) {
          reconnections++;
          if (reconnections == 2 && !reconnected.isCompleted) {
            reconnected.complete();
          }
        },
      );
      CrdtSync.client(
        clientA,
        pairA2.b,
        onConnect: (_, __) {
          reconnections++;
          if (reconnections == 2 && !reconnected.isCompleted) {
            reconnected.complete();
          }
        },
      );
      await reconnected.future.timeout(const Duration(seconds: 3));

      // Verify A catches up B's write and B receives A's offline write
      final aSawB = Completer<void>();
      final bSawA = Completer<void>();
      final serverSawAOffline = Completer<void>();

      final subA = clientA.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = clientA.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'b_offline1') && !aSawB.isCompleted) {
            aSawB.complete();
          }
        }
      });
      final subB = clientB.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = clientB.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'a_offline1') && !bSawA.isCompleted) {
            bSawA.complete();
          }
        }
      });
      final subServerA = server.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = server.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'a_offline1') &&
              !serverSawAOffline.isCompleted) {
            serverSawAOffline.complete();
          }
        }
      });

      await Future.wait([
        aSawB.future.timeout(const Duration(seconds: 4)),
        bSawA.future.timeout(const Duration(seconds: 4)),
        serverSawAOffline.future.timeout(const Duration(seconds: 4)),
      ]);

      await subA.cancel();
      await subB.cancel();
      await subServerA.cancel();

      final keysServer =
          (server.getChangeset()['msgs'] ?? []).map((e) => e['key']).toSet();
      expect(keysServer, containsAll(['b_offline1', 'a_offline1']));

      final keysA =
          (clientA.getChangeset()['msgs'] ?? []).map((e) => e['key']).toSet();
      final keysB =
          (clientB.getChangeset()['msgs'] ?? []).map((e) => e['key']).toSet();
      expect(keysA, containsAll(['b_offline1', 'a_offline1']));
      expect(keysB, containsAll(['b_offline1', 'a_offline1']));
    });

    test('server pre-seeded data is delivered on initial sync', () async {
      final pair = _LoopbackPair();

      final server = MapCrdt(['seed']);
      final client = MapCrdt(['seed']);

      // Pre-seed server before any connection
      await server.put('seed', 's1', {'x': 1});

      final connected = Completer<void>();
      var connections = 0;

      // Subscribe before starting sync to avoid missing the initial event
      final dataArrived = Completer<void>();
      final sub = client.onTablesChanged.listen((event) {
        if (event.tables.contains('seed')) {
          final rows = client.getChangeset()['seed'] ?? [];
          if (rows.any((r) => r['key'] == 's1') && !dataArrived.isCompleted) {
            dataArrived.complete();
          }
        }
      });

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

      await connected.future.timeout(const Duration(seconds: 3));
      await dataArrived.future.timeout(const Duration(seconds: 3));
      await sub.cancel();

      final rows = client.getChangeset()['seed'] ?? [];
      expect(rows.length, 1);
      expect(rows.first['key'], 's1');
      expect((rows.first['value']! as Map)['x'], 1);
    });

    test('no echo back to origin (server excludes origin node)', () async {
      final pairA = _LoopbackPair();
      final pairB = _LoopbackPair();

      final server = MapCrdt(['msgs']);
      final clientA = MapCrdt(['msgs']);
      final clientB = MapCrdt(['msgs']);

      final connected = Completer<void>();
      var connections = 0;

      CrdtSync.server(
        server,
        pairA.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );
      CrdtSync.server(
        server,
        pairB.a,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
      );

      final aReceivedCounts = <Map<String, int>>[];
      final bReceivedCounts = <Map<String, int>>[];
      late CrdtSync aSync;
      late CrdtSync bSync;

      aSync = CrdtSync.client(
        clientA,
        pairA.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
        onChangesetReceived: (_, counts) => aReceivedCounts.add(counts),
      );
      bSync = CrdtSync.client(
        clientB,
        pairB.b,
        onConnect: (_, __) {
          connections++;
          if (connections == 4 && !connected.isCompleted) connected.complete();
        },
        onChangesetReceived: (_, counts) => bReceivedCounts.add(counts),
      );

      await connected.future.timeout(const Duration(seconds: 3));

      // Clear any initial sync events
      aReceivedCounts.clear();
      bReceivedCounts.clear();

      // Perform write from A and ensure only B receives it back via server
      final bSawFromA = Completer<void>();
      final subB = clientB.onTablesChanged.listen((event) {
        if (event.tables.contains('msgs')) {
          final rows = clientB.getChangeset()['msgs'] ?? [];
          if (rows.any((r) => r['key'] == 'fromA') && !bSawFromA.isCompleted) {
            bSawFromA.complete();
          }
        }
      });

      await clientA.put('msgs', 'fromA', {'origin': 'A'});
      await bSawFromA.future.timeout(const Duration(seconds: 3));
      await subB.cancel();

      // Give a brief moment for any (unexpected) echo to arrive
      await Future<void>.delayed(const Duration(milliseconds: 100));

      int sumCounts(List<Map<String, int>> list, String table) =>
          list.map((m) => m[table] ?? 0).fold(0, (sum, v) => sum + v);

      final aMsgs = sumCounts(aReceivedCounts, 'msgs');
      final bMsgs = sumCounts(bReceivedCounts, 'msgs');

      expect(aMsgs, 0, reason: 'Origin client should not receive its own data');
      expect(bMsgs, greaterThanOrEqualTo(1));

      // Cleanup (close the syncs explicitly)
      await aSync.close();
      await bSync.close();
    });
  });
}
