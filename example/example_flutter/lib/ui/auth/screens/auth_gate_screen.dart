import 'dart:async';

import 'package:crdt/crdt.dart';
import 'package:crdt_sync/crdt_sync.dart' hide ConnectionState;
import 'package:example_client/example_client.dart';
import 'package:flutter/material.dart';
import 'package:serverpod_flutter/serverpod_flutter.dart';
import 'package:example_flutter/core/utils/supabase_auth_key_manager.dart';
import 'package:example_flutter/domain/domain.dart';
import 'package:example_flutter/ui/auth/auth.dart';
import 'package:example_flutter/ui/todo/todo.dart';
import 'package:provider/provider.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  bool hasStartedSync = false;

  Future<void> _startSync(BuildContext context) async {
    if (hasStartedSync) return;

    final client = Client(
      'http://$localhost:8080/',
      authenticationKeyManager: SupabaseAuthKeyManager(),
    )..connectivityMonitor = FlutterConnectivityMonitor();

    final crdt = context.read<Crdt>();

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
    hasStartedSync = true;
  }

  @override
  Widget build(BuildContext context) {
    final authRepository = context.read<AuthRepository>();

    return StreamBuilder<bool>(
      stream: authRepository.isAuthenticated,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Colors.yellow.shade700,
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Error: ${snapshot.error}',
              ),
            ),
          );
        }

        if (snapshot.data == true) {
          _startSync(context);
          return const TodoScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
