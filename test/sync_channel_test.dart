import 'dart:async';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'package:crdt_sync/crdt_sync.dart';

import 'dart:io';

void main() {
  group('DuplexStreamChannel', () {
    test('passes data in both directions and closes', () async {
      final aCtrl = StreamController<String>();
      final bCtrl = StreamController<String>();

      final a =
          DuplexStreamChannel(incoming: aCtrl.stream, outgoing: bCtrl.sink);
      final b =
          DuplexStreamChannel(incoming: bCtrl.stream, outgoing: aCtrl.sink);

      final aReceived = <String>[];
      final bReceived = <String>[];

      final aSub = a.stream.listen(aReceived.add);
      final bSub = b.stream.listen(bReceived.add);

      a.sink.add('hello');
      b.sink.add('world');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(aReceived, ['world']);
      expect(bReceived, ['hello']);

      await a.close();
      await b.close();
      await aSub.cancel();
      await bSub.cancel();
    });
  });

  group('WebSocketSyncChannel', () {
    test('works with a real WebSocket', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverDone = Completer<void>();

      // Echo server
      () async {
        final request = await server.first;
        final socket = await WebSocketTransformer.upgrade(request);
        final channel = IOWebSocketChannel(socket);
        channel.stream.listen((event) {
          channel.sink.add(event);
        }, onDone: () async {
          await server.close(force: true);
          serverDone.complete();
        });
      }();

      final uri = Uri.parse('ws://localhost:${server.port}');
      final client = IOWebSocketChannel.connect(uri);
      final channel = WebSocketSyncChannel(client);
      await channel.ready;

      final received = Completer<String>();
      channel.stream.listen((event) => received.complete(event));
      channel.sink.add('ping');
      expect(await received.future, 'ping');
      // Not all runtimes surface close code/reason reliably; ensure close completes
      await channel.close(4001, 'test');
      await serverDone.future;
    });
  });
}
