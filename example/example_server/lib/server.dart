import 'dart:io';

import 'package:serverpod/serverpod.dart';

import 'src/generated/protocol.dart';
import 'src/generated/endpoints.dart';
import 'src/supabase_auth.dart';

/// The starting point of the Serverpod server.
void run(List<String> args) async {
  // Read Supabase config from environment
  final supabaseUrl = Platform.environment['SUPABASE_URL'];
  final supabaseAnonKey = Platform.environment['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    stderr.writeln(
      'ERROR: SUPABASE_URL or SUPABASE_ANON_KEY not set.',
    );
    exit(1);
  }

  final validator = SupabaseAuthValidator(
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
  );

  // Initialize Serverpod and connect it with your generated code.
  final pod = Serverpod(
    args,
    Protocol(),
    Endpoints(),
    authenticationHandler: validator.validate,
  );

  // Start the server.
  await pod.start();
}
