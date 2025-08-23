import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:example_client/example_client.dart';
import 'package:example_flutter/bootstrap.dart';
import 'package:example_flutter/data/data.dart';
import 'package:example_flutter/stub/database/database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:serverpod_flutter/serverpod_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const author = kIsWeb ? 'alice-web' : 'bob-native';

  // Initialize the SQLite database
  final sqliteDatabase = AppDatabase(await createInMemoryQueryExecutor());

  // Initialize the CRDT
  final crdt = DriftCrdt(sqliteDatabase);
  await crdt.init(author);

  // Initialize the sync client
  final client = Client('http://$localhost:8080/')
    ..connectivityMonitor = FlutterConnectivityMonitor();

  final syncClient = CrdtSyncClient(
    crdt,
    () async {
      late DuplexStreamChannel channel;
      final toServer = StreamController<String>(
        onCancel: () {
          channel.close();
        },
      );
      final rawFromServer = client.sync.crdtStream(toServer.stream);
      final fromServer = rawFromServer.asBroadcastStream();
      // Monitor completion/errors to propagate closure
      fromServer.listen(
        (_) {},
        onDone: () => channel.close(),
        onError: (_) => channel.close(),
      );
      channel = DuplexStreamChannel(
        incoming: fromServer,
        outgoing: toServer.sink,
      );
      return channel;
    },
    verbose: true,
  );

  syncClient.connect();

  // Initialize the todo repository
  // final todoRepository = SqliteCrdtTodoRepository(crdt);
  final todoRepository = UnsafeSqliteCrdtTodoRepository(crdt);

  bootstrap(todoRepository);
}
