import 'package:sqlite_crdt/sqlite_crdt.dart';

// Shared in-memory CRDT store for the example server.
SqliteCrdt? _crdt;

Future<SqliteCrdt> createCrdt() async {
  if (_crdt != null) return _crdt!;

  final crdt = await SqliteCrdt.openInMemory();
  await crdt.init("server_node_id");
  // Create a table for the chat messages
  await crdt.execute('''
    CREATE TABLE IF NOT EXISTS chat (
      id TEXT NOT NULL PRIMARY KEY,
      message TEXT NOT NULL
    )
  ''');
  _crdt = crdt;
  return crdt;
}
