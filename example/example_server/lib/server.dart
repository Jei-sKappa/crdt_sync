import 'package:example_server/src/crdt_store.dart';
import 'package:serverpod/serverpod.dart';

import 'src/generated/protocol.dart';
import 'src/generated/endpoints.dart';

/// The starting point of the Serverpod server.
void run(List<String> args) async {
  mapCrdt.onTablesChanged.listen(
    (event) {
      print('SERVER:');
      final all = mapCrdt.getChangeset();
      for (final entry in all.entries) {
        print('  ${entry.key}:');
        for (final record in entry.value) {
          print('    ${record['key']}: ${record['value']}');
        }
      }
    },
  );

  // Initialize Serverpod and connect it with your generated code.
  final pod = Serverpod(args, Protocol(), Endpoints());

  // Start the server.
  await pod.start();
}
