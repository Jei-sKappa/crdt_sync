import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:synchronized/synchronized.dart';

final _crdts = <String, SqlCrdt>{};

final _lock = Lock();

Future<SqlCrdt> getCrdtFor(String tenantId) async {
  return await _lock.synchronized(() async {
    final crdt = _crdts[tenantId];
    if (crdt != null) {
      return crdt;
    }

    final newCrdt = await _createCrdt(tenantId);
    _crdts[tenantId] = newCrdt;
    return newCrdt;
  });
}

Future<SqliteCrdt> _createCrdt(String tenantId) async {
  final crdt = await SqliteCrdt.openInMemory();
  await crdt.init('server_$tenantId');
  // Create a table for the todos
  await crdt.execute('''
    CREATE TABLE IF NOT EXISTS todos (
      id TEXT NOT NULL PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      done BOOLEAN NOT NULL DEFAULT FALSE
    )
  ''');

  crdt.onTablesChanged.listen((event) async {
    final buff = StringBuffer(
      "__TABLES CHANGED FOR ${tenantId}__ | ${_crdts.length}\n",
    );

    final dataset = await crdt.getChangeset();
    for (final tableEntry in dataset.entries) {
      buff.write("Table: ${tableEntry.key}\n");
      for (final record in tableEntry.value) {
        buff.write("  - ");
        for (final fieldEntry in record.entries) {
          buff.write("${fieldEntry.key}: ${fieldEntry.value} | ");
        }
        buff.write("\n");
      }
    }

    // ignore: avoid_print
    print(buff.toString());
  });

  return crdt;
}
