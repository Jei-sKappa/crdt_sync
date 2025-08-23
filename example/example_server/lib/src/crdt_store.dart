import 'package:sqlite_crdt/sqlite_crdt.dart';

// Shared in-memory CRDT store for the example server.
SqliteCrdt? _crdt;

Future<SqliteCrdt> createCrdt() async {
  if (_crdt != null) return _crdt!;

  final crdt = await SqliteCrdt.openInMemory();
  await crdt.init("server");
  // Create a table for the todos
  await crdt.execute('''
    CREATE TABLE IF NOT EXISTS todos (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      done BOOLEAN NOT NULL DEFAULT FALSE
    )
  ''');
  _crdt = crdt;
  return crdt;
}
