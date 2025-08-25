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
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      done BOOLEAN NOT NULL DEFAULT FALSE
    )
  ''');
  _crdt = crdt;

  // crdt.onTablesChanged.listen((event) async {
  //   final buff = StringBuffer("__TABLES CHANGED__\n");

  //   final dataset = await crdt.getChangeset();
  //   for (final tableEntry in dataset.entries) {
  //     buff.write("Table: ${tableEntry.key}\n");
  //     for (final record in tableEntry.value) {
  //       buff.write("  - ");
  //       for (final fieldEntry in record.entries) {
  //         buff.write("${fieldEntry.key}: ${fieldEntry.value} | ");
  //       }
  //       buff.write("\n");
  //     }
  //   }

  //   print(buff.toString());
  // });

  return crdt;
}
