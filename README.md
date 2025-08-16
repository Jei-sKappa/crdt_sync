# crdt_sync

A Dart-native turnkey solution for painless network synchronization.

`crdt_sync` takes care of the network plumbing between your app and backend to build products that are:

* Offline-first: Apps primarily work with a local store independent of network connectivity.
* Real-time: When online, the local store immediately and continuously synchronizes with the backend.
* Efficient: Synchronization relies on delta changesets to optimize the amount of data sent over the wire.
* Portable: All communication happens over a single standard WebSocket making it compatible with most network configurations.

This library is compatible with the `crdt` package and all of its implementations. It uses a standard communication protocol which abstracts the underlying storage method. This results in the dubious ability to synchronize SQL nodes with No-SQL ones. I don't judge.

See [crdt](https://github.com/cachapa/crdt) for more details and a list of existing implementations.

## Usage

You'll most likely want to use a persistent `crdt` store, however the following sample code uses an ephemeral `MapCrdt` for the sake of simplicity:

```dart
final crdt = MapCrdt(['chat']);
```

### Server

Start listening for connections:

```dart
listen(crdt, 8080);
```

Alternatively, you can use `upgrade()` to adopt an `HttpRequest`, or `CrdtSync.websocketServer()` to manage a `WebSocket` directly making it easy to integrate with [Shelf](https://pub.dev/packages/shelf) and other server frameworks.

See [tudo_server](https://github.com/cachapa/tudo_server) for a real world example.

### Client

For WebSocket connections, instantiate a `CrdtSyncClient.websocket` and order it to start connecting:

```dart
final client = CrdtSyncClient.websocket(crdt, Uri.parse('ws://localhost:8080'));
client.connect();
```

For custom transports, provide a channel factory:

```dart
final client = CrdtSyncClient(
  crdt,
  () async {
    // Your custom channel creation logic here
  },
);
client.connect();
```

The client uses exponential backoff for reconnection (defaults to 2-10 seconds). For testing or faster reconnection, you can customize the delays:

```dart
final client = CrdtSyncClient.websocket(
  crdt,
  Uri.parse('ws://localhost:8080'),
  minReconnectDelay: 1, // Start with 1 second
  maxReconnectDelay: 5, // Cap at 5 seconds
);
```

Once `connect()` is called, the client will continuously attempt to establish or resume a connection until it succeeds, or until `disconnect()` is called.

See the included [example](https://github.com/cachapa/crdt_sync/blob/master/example/example.dart) for a more complete solution, or [tudo](https://github.com/cachapa/tudo) for a real-world application.

### Using with Serverpod streaming methods

Serverpod uses streaming endpoint methods instead of exposing raw WebSockets. `crdt_sync` supports this via a transport abstraction:

- Use `DuplexStreamChannel` to adapt a pair of `Stream<String>`/`StreamSink<String>` to the sync layer.
- Use `CrdtSync.client` and `CrdtSync.server` to start synchronization over the adapted channel.
- For WebSocket connections, use `CrdtSync.websocketClient` and `CrdtSync.websocketServer` convenience methods.

Client-side (inside your Serverpod client app):

```dart
// Option 1: One-time sync
final inController = StreamController<String>();
final outStream = client.example.echoStream(inController.stream);
final channel = DuplexStreamChannel(
  incoming: outStream,
  outgoing: inController.sink,
);
CrdtSync.client(
  crdt,
  channel,
  handshakeDataBuilder: () => {'some': 'metadata'},
);

// Option 2: Auto-reconnect sync client
final syncClient = CrdtSyncClient(
  crdt,
  () async {
    final inController = StreamController<String>();
    final outStream = client.example.echoStream(inController.stream);
    return DuplexStreamChannel(
      incoming: outStream,
      outgoing: inController.sink,
    );
  },
);
syncClient.connect();
```

Server-side (inside a Serverpod endpoint):

```dart
class SyncEndpoint extends Endpoint {
  Stream<String> crdtStream(Session session, Stream<String> fromClient) async* {
    final toClient = StreamController<String>();

    // Start CRDT sync over the duplex stream
    final channel = DuplexStreamChannel(
      incoming: fromClient,
      outgoing: toClient.sink,
    );
    CrdtSync.server(
      crdt,
      channel,
      handshakeDataBuilder: (peerId, peerData) => {'server': 'info'},
    );

    // Yield server->client messages
    yield* toClient.stream;
  }
}
```

Note: The wire format is the same JSON strings used by WebSockets, so no additional serialization is necessary.

## Features and bugs

Please file feature requests and bugs in the [issue tracker](https://github.com/cachapa/crdt_sync/issues).
