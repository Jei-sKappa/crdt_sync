import 'dart:async';

import 'package:drift_crdt/drift_crdt.dart';
import 'package:example_flutter/bootstrap.dart';
import 'package:example_flutter/data/data.dart';
import 'package:example_flutter/stub/database/database.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure Supabase via dart-define
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Initialize the SQLite database
  final sqliteDatabase = AppDatabase(await createInMemoryQueryExecutor());

  // Initialize the CRDT
  final crdt = DriftCrdt(sqliteDatabase);
  await crdt.init();

  // Initialize the repositories
  // final todoRepository = SqliteCrdtTodoRepository(crdt);
  final todoRepository = UnsafeSqliteCrdtTodoRepository(crdt);
  final authRepository =
      SupabaseAuthRepository(client: Supabase.instance.client);

  bootstrap(
    crdt: crdt,
    authRepository: authRepository,
    todoRepository: todoRepository,
  );
}
