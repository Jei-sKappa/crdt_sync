import 'dart:async';

import 'package:example_client/example_client.dart';
import 'package:flutter/material.dart';
import 'package:serverpod_flutter/serverpod_flutter.dart';
import 'package:crdt/map_crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';

/// Sets up a global client object that can be used to talk to the server from
/// anywhere in our app. The client is generated from your server code
/// and is set up to connect to a Serverpod running on a local server on
/// the default port. You will need to modify this to connect to staging or
/// production servers.
/// In a larger app, you may want to use the dependency injection of your choice
/// instead of using a global client object. This is just a simple example.
late final Client client;

late String serverUrl;

// Global CRDT for demo, with a single 'chat' table
final mapCrdt = MapCrdt(['chat']);

// Sync client that reconnects automatically using Serverpod streaming method
CrdtSyncClient? syncClient;

void main() {
  // When you are running the app on a physical device, you need to set the
  // server URL to the IP address of your computer. You can find the IP
  // address by running `ipconfig` on Windows or `ifconfig` on Mac/Linux.
  // You can set the variable when running or building your app like this:
  // E.g. `flutter run --dart-define=SERVER_URL=https://api.example.com/`
  const serverUrlFromEnv = String.fromEnvironment('SERVER_URL');
  final serverUrl =
      serverUrlFromEnv.isEmpty ? 'http://$localhost:8080/' : serverUrlFromEnv;

  client = Client(serverUrl)
    ..connectivityMonitor = FlutterConnectivityMonitor();

  // Build a duplex channel from the Serverpod streaming endpoint
  syncClient = CrdtSyncClient(
    mapCrdt,
    () async {
      // Create duplex streams
      final toServer = StreamController<String>();
      final fromServer = client.sync.crdtStream(toServer.stream);
      return DuplexStreamChannel(
        incoming: fromServer,
        outgoing: toServer.sink,
      );
    },
    // verbose: true,
  );

  syncClient!.connect();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serverpod Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(title: 'Serverpod Example'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

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
    await mapCrdt.put('chat', DateTime.now().microsecondsSinceEpoch.toString(),
        {'text': text});
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
                stream: mapCrdt.onTablesChanged,
                builder: (context, snapshot) {
                  final records = List.of(mapCrdt.getChangeset()['chat'] ?? [])
                    ..sort((a, b) =>
                        (a['key'] as String).compareTo(b['key'] as String));
                  return ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final rec = records[index];
                      final value = rec['value'] as Map? ?? {};
                      return ListTile(
                        title: Text(value['text']?.toString() ?? ''),
                        dense: true,
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
