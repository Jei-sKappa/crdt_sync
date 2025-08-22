import 'dart:async';
import 'dart:io';

import 'package:example_client/example_client.dart';
import 'package:flutter/material.dart';
import 'package:serverpod_flutter/serverpod_flutter.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

/// Sets up a global client object that can be used to talk to the server from
/// anywhere in our app. The client is generated from your server code
/// and is set up to connect to a Serverpod running on a local server on
/// the default port. You will need to modify this to connect to staging or
/// production servers.
/// In a larger app, you may want to use the dependency injection of your choice
/// instead of using a global client object. This is just a simple example.
late final Client client;

late String serverUrl;

// Sync client that reconnects automatically using Serverpod streaming method
CrdtSyncClient? syncClient;

Future<void> main() async {
  const serverUrlFromEnv = String.fromEnvironment('SERVER_URL');
  final serverUrl =
      serverUrlFromEnv.isEmpty ? 'http://$localhost:8080/' : serverUrlFromEnv;

  client = Client(serverUrl)
    ..connectivityMonitor = FlutterConnectivityMonitor();

  final crdt = await SqliteCrdt.openInMemory();
  await crdt.init(Platform.isMacOS ? 'alice-macos' : 'bob-ios');
  await crdt.execute('''
    CREATE TABLE IF NOT EXISTS chat (
      id TEXT NOT NULL PRIMARY KEY,
      message TEXT NOT NULL
    )
  ''');

  // Build a duplex channel from the Serverpod streaming endpoint
  syncClient = CrdtSyncClient(
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
    // verbose: true,
  );

  syncClient!.connect();

  runApp(MyApp(crdt: crdt));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.crdt});

  final SqliteCrdt crdt;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serverpod Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(title: 'Serverpod Example', crdt: crdt),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, required this.crdt});

  final SqliteCrdt crdt;

  final String title;

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  final _textEditingController = TextEditingController();

  void _sendMessage() async {
    final text = _textEditingController.text.trim();
    if (text.isEmpty) return;
    _textEditingController.clear();
    await widget.crdt.execute(
      'INSERT INTO chat (id, message) VALUES (?, ?)',
      [
        DateTime.now().microsecondsSinceEpoch.toString(),
        text,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder(
                stream: widget.crdt.onTablesChanged,
                builder: (context, _) {
                  return FutureBuilder(
                    future: widget.crdt.getChangeset(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final records = List.of(
                          snapshot.data!['chat'] ?? <Map<String, Object?>>[])
                        ..sort((a, b) =>
                            (a['id'] as String).compareTo(b['id'] as String));
                      return ListView.builder(
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final rec = records[index];
                          final value = rec['message'] as String? ?? '';
                          return ListTile(
                            title: Text(value),
                            dense: true,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textEditingController,
                    decoration:
                        const InputDecoration(hintText: 'Type a message…'),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
