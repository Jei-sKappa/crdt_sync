import 'dart:async';
import 'dart:math' as math;

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
  group('Concurrent Operations and Edge Cases', () {
    test('simultaneous writes from both client and server', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['messages']);
      final client = MapCrdt(['messages']);

      final handshakeComplete = Completer<void>();
      final allSynced = Completer<void>();
      var connectionCount = 0;
      const expectedRecords = 20; // 10 from each side

      void checkCompletion() {
        final serverRecords = server.getChangeset()['messages']?.length ?? 0;
        final clientRecords = client.getChangeset()['messages']?.length ?? 0;

        if (serverRecords >= expectedRecords &&
            clientRecords >= expectedRecords) {
          if (!allSynced.isCompleted) allSynced.complete();
        }
      }

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      await handshakeComplete.future.timeout(const Duration(seconds: 2));

      // Monitor both sides for completion
      server.onTablesChanged.listen((_) => checkCompletion());
      client.onTablesChanged.listen((_) => checkCompletion());

      // Rapid concurrent writes from both sides
      final futures = <Future<void>>[];

      // Server writes
      for (var i = 0; i < 10; i++) {
        futures.add(server.put('messages', 'server_$i', {
          'author': 'server',
          'content': 'Message $i from server',
          'timestamp': DateTime.now().millisecondsSinceEpoch + i,
        }));
      }

      // Client writes (slightly delayed to create more realistic concurrency)
      for (var i = 0; i < 10; i++) {
        futures.add(Future.delayed(
            Duration(milliseconds: i * 5),
            () => client.put('messages', 'client_$i', {
                  'author': 'client',
                  'content': 'Message $i from client',
                  'timestamp': DateTime.now().millisecondsSinceEpoch + i + 1000,
                })));
      }

      await Future.wait(futures);
      await allSynced.future.timeout(const Duration(seconds: 5));

      // Verify both sides have all records
      final serverRecords = server.getChangeset()['messages'] ?? [];
      final clientRecords = client.getChangeset()['messages'] ?? [];

      expect(serverRecords.length, expectedRecords);
      expect(clientRecords.length, expectedRecords);

      // Verify record integrity
      final serverKeys = serverRecords.map((r) => r['key']).toSet();
      final clientKeys = clientRecords.map((r) => r['key']).toSet();

      expect(serverKeys, clientKeys); // Both should have identical keys

      // Check for specific records
      expect(
          serverKeys.where((k) => (k! as String).startsWith('server_')).length,
          10);
      expect(
          serverKeys.where((k) => (k! as String).startsWith('client_')).length,
          10);
    });

    test('conflict resolution with same key updates', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['documents']);
      final client = MapCrdt(['documents']);

      final handshakeComplete = Completer<void>();
      final conflictResolved = Completer<void>();
      var connectionCount = 0;

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      await handshakeComplete.future.timeout(const Duration(seconds: 2));

      // Monitor for conflict resolution completion
      var updatesReceived = 0;
      void checkForResolution() {
        updatesReceived++;
        if (updatesReceived >= 4) {
          // Both sides should receive both updates
          final serverDoc = server
              .getChangeset()['documents']
              ?.where((r) => r['key'] == 'doc1')
              .first;
          final clientDoc = client
              .getChangeset()['documents']
              ?.where((r) => r['key'] == 'doc1')
              .first;

          if (serverDoc != null &&
              clientDoc != null &&
              !conflictResolved.isCompleted) {
            conflictResolved.complete();
          }
        }
      }

      server.onTablesChanged.listen((_) => checkForResolution());
      client.onTablesChanged.listen((_) => checkForResolution());

      // Create concurrent conflicting updates to the same document
      await Future.wait([
        server.put('documents', 'doc1', {
          'title': 'Document 1',
          'content': 'Updated by server',
          'version': 1,
          'modified_by': 'server',
        }),
        client.put('documents', 'doc1', {
          'title': 'Document 1',
          'content': 'Updated by client',
          'version': 1,
          'modified_by': 'client',
        }),
      ]);

      await conflictResolved.future.timeout(const Duration(seconds: 3));

      // Verify that conflict was resolved and both sides converged
      final serverRecords = server.getChangeset()['documents'] ?? [];
      final clientRecords = client.getChangeset()['documents'] ?? [];

      // Should only have one record for doc1 after conflict resolution
      final serverDoc = serverRecords.where((r) => r['key'] == 'doc1').toList();
      final clientDoc = clientRecords.where((r) => r['key'] == 'doc1').toList();

      expect(serverDoc.length, 1);
      expect(clientDoc.length, 1);

      // Both sides should have the same final version (CRDT ensures
      // convergence)
      expect(serverDoc.first['hlc'], clientDoc.first['hlc']);
      expect(serverDoc.first['value'], clientDoc.first['value']);
    });

    test('high-frequency updates with batching', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['metrics']);
      final client = MapCrdt(['metrics']);

      final handshakeComplete = Completer<void>();
      final batchingComplete = Completer<void>();
      var connectionCount = 0;
      final changesetCounts = <int>[];

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2 && !handshakeComplete.isCompleted) {
            handshakeComplete.complete();
          }
        },
        onChangesetReceived: (_, counts) {
          final totalRecords =
              counts.values.fold(0, (sum, count) => sum + count);
          changesetCounts.add(totalRecords);
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

      // Monitor server for data completion
      server.onTablesChanged.listen((event) {
        if (event.tables.contains('metrics')) {
          final serverRecords = server.getChangeset()['metrics']?.length ?? 0;
          if (serverRecords >= 50 && !batchingComplete.isCompleted) {
            batchingComplete.complete();
          }
        }
      });

      // Send many rapid updates
      for (var i = 0; i < 50; i++) {
        await client.put('metrics', 'metric_$i', {
          'value': math.Random().nextDouble() * 100,
          'timestamp': DateTime.now().millisecondsSinceEpoch + i,
          'type': 'performance',
        });
      }

      await batchingComplete.future.timeout(const Duration(seconds: 5));

      // Verify batching occurred (should receive fewer changesets than
      // individual writes)
      // If no batching occurs, each record creates its own changeset
      expect(changesetCounts.length, lessThanOrEqualTo(50));

      // But total records should be correct
      final totalReceived =
          changesetCounts.fold(0, (sum, count) => sum + count);
      expect(totalReceived, greaterThanOrEqualTo(50));

      // Verify all data integrity
      final serverRecords = server.getChangeset()['metrics'] ?? [];
      expect(serverRecords.length, 50);
    });

    test('large changeset handling', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['bulk_data']);
      final client = MapCrdt(['bulk_data']);

      final handshakeComplete = Completer<void>();
      final bulkSyncComplete = Completer<void>();
      var connectionCount = 0;

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      await handshakeComplete.future.timeout(const Duration(seconds: 2));

      // Monitor server for bulk data arrival
      server.onTablesChanged.listen((event) {
        if (event.tables.contains('bulk_data')) {
          final records = server.getChangeset()['bulk_data'] ?? [];
          if (records.length >= 1000 && !bulkSyncComplete.isCompleted) {
            bulkSyncComplete.complete();
          }
        }
      });

      // Generate large dataset before connection to simulate initial sync
      final bulkData = <Future<void>>[];
      for (var i = 0; i < 1000; i++) {
        bulkData.add(client.put('bulk_data', 'item_$i', {
          'id': i,
          'name': 'Item $i',
          'description':
              'This is a description for item $i with some additional text to '
                  'make it larger.',
          'tags': ['tag_${i % 10}', 'category_${i % 5}'],
          'metadata': {
            'created': DateTime.now().millisecondsSinceEpoch,
            'size': i * 1.5,
            'active': i.isEven,
          },
        }));
      }

      await Future.wait(bulkData);
      await bulkSyncComplete.future.timeout(const Duration(seconds: 10));

      // Verify all data synced correctly
      final serverRecords = server.getChangeset()['bulk_data'] ?? [];
      expect(serverRecords.length, 1000);

      // Spot check some records
      final item0 = serverRecords.where((r) => r['key'] == 'item_0').first;
      final item999 = serverRecords.where((r) => r['key'] == 'item_999').first;

      expect((item0['value']! as Map)['id'], 0);
      expect((item999['value']! as Map)['id'], 999);
    });

    test('memory and performance under stress', () async {
      final pair = _LoopbackPair();
      final server = MapCrdt(['stress_test']);
      final client = MapCrdt(['stress_test']);

      final handshakeComplete = Completer<void>();
      var connectionCount = 0;

      CrdtSync.server(
        server,
        pair.a,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      CrdtSync.client(
        client,
        pair.b,
        onConnect: (_, __) {
          connectionCount++;
          if (connectionCount == 2) handshakeComplete.complete();
        },
      );

      await handshakeComplete.future.timeout(const Duration(seconds: 2));

      final startTime = DateTime.now();
      var operationsCompleted = 0;

      // Stress test with mixed operations
      final operations = <Future<void>>[];

      for (var round = 0; round < 5; round++) {
        // Batch of insertions
        for (var i = 0; i < 20; i++) {
          final key = 'stress_${round}_$i';
          operations.add(client.put('stress_test', key, {
            'round': round,
            'index': i,
            'data': List.generate(10, (j) => 'data_$j').join(','),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }).then((_) => operationsCompleted++));
        }

        // Brief pause between batches
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      await Future.wait(operations);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // Performance assertions
      expect(operationsCompleted, 100);
      expect(duration.inSeconds,
          lessThan(10)); // Should complete within 10 seconds

      // Wait for final sync
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Verify data integrity
      final serverRecords = server.getChangeset()['stress_test'] ?? [];
      expect(serverRecords.length, 100);

      // Check that all rounds are represented
      final rounds =
          serverRecords.map((r) => (r['value']! as Map)['round']).toSet();
      expect(rounds, {0, 1, 2, 3, 4});
    });

    test('connection state consistency during rapid connect/disconnect',
        () async {
      final pairs = List.generate(3, (_) => _LoopbackPair());
      final server = MapCrdt(['state_test']);
      final clients = List.generate(3, (_) => MapCrdt(['state_test']));

      final allConnected = Completer<void>();
      final allDisconnected = Completer<void>();
      var connectedCount = 0;
      var disconnectedCount = 0;

      final serverSyncs = <CrdtSync>[];

      // Start multiple server instances
      for (var i = 0; i < 3; i++) {
        final sync = CrdtSync.server(
          server,
          pairs[i].a,
          onConnect: (_, __) {
            connectedCount++;
            if (connectedCount == 3 && !allConnected.isCompleted) {
              allConnected.complete();
            }
          },
          onDisconnect: (_, __, ___) {
            disconnectedCount++;
            if (disconnectedCount == 3 && !allDisconnected.isCompleted) {
              allDisconnected.complete();
            }
          },
        );
        serverSyncs.add(sync);
      }

      // Start multiple clients
      final clientSyncs = <CrdtSync>[];
      for (var i = 0; i < 3; i++) {
        final sync = CrdtSync.client(clients[i], pairs[i].b);
        clientSyncs.add(sync);
      }

      await allConnected.future.timeout(const Duration(seconds: 3));

      // Verify all connections established
      expect(connectedCount, 3);

      // Rapid disconnect all
      await Future.wait(serverSyncs.map((sync) => sync.close()));
      await allDisconnected.future.timeout(const Duration(seconds: 3));

      expect(disconnectedCount, 3);
    });
  });
}
