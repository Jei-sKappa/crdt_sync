import 'package:drift_crdt/drift_crdt.dart';
import 'package:example_flutter/bootstrap.dart';
import 'package:example_flutter/data/data.dart';
import 'package:example_flutter/stub/database/database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const author = kIsWeb ? 'alice-web' : 'bob-native';

  // Initialize the SQLite database
  final sqliteDatabase = AppDatabase(await createInMemoryQueryExecutor());

  // Initialize the CRDT
  final crdt = DriftCrdt(sqliteDatabase);
  await crdt.init(author);

  // Initialize the todo repository
  // final todoRepository = SqliteCrdtTodoRepository(crdt);
  final todoRepository = UnsafeSqliteCrdtTodoRepository(crdt);

  bootstrap(todoRepository);
}
