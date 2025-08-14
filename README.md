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

Alternatively, you can use `upgrade()` to adopt an `HttpRequest`, or `CrdtSync.server()` to manage a `WebSocket` directly making it easy to integrate with [Shelf](https://pub.dev/packages/shelf) and other server frameworks.

See [tudo_server](https://github.com/cachapa/tudo_server) for a real world example.

### Client

Instantiate a `CrdtSyncClient` and order it to start connecting:

```dart
final client = CrdtSyncClient(crdt, Uri.parse('ws://localhost:8080'));
client.connect();
```

Once `connect()` is called, the client will continuously attempt to establish or resume a connection until it succeeds, or until `disconnect()` is called.

See the included [example](https://github.com/cachapa/crdt_sync/blob/master/example/example.dart) for a more complete solution, or [tudo](https://github.com/cachapa/tudo) for a real-world application.

### Using with Serverpod streaming methods

Serverpod uses streaming endpoint methods instead of exposing raw WebSockets. `crdt_sync` supports this via a transport abstraction:

- Use `DuplexStreamChannel` to adapt a pair of `Stream<String>`/`StreamSink<String>` to the sync layer.
- Use `CrdtSync.clientWithChannel` and `CrdtSync.serverWithChannel` to start synchronization over the adapted channel.

Client-side (inside your Serverpod client app):

```dart
// Acquire a Serverpod streaming method pair
final inController = StreamController<String>();
final outStream = client.example.echoStream(inController.stream);

// Wrap as a SyncChannel
final channel = DuplexStreamChannel(
  incoming: outStream,
  outgoing: inController.sink,
);

// Start sync over the channel
CrdtSync.clientWithChannel(
  crdt,
  channel,
  handshakeDataBuilder: () => {'some': 'metadata'},
);
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
    CrdtSync.serverWithChannel(
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
