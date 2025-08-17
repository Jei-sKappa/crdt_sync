/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod_client/serverpod_client.dart' as _i1;
import 'dart:async' as _i2;
import 'protocol.dart' as _i3;

/// Streaming endpoint that bridges Serverpod streaming with crdt_sync.
/// {@category Endpoint}
class EndpointSync extends _i1.EndpointRef {
  EndpointSync(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'sync';

  /// A streaming method exposed by Serverpod that we use to transport the
  /// CRDT sync frames as plain UTF-8 JSON strings.
  ///
  /// The server returns the outgoing stream to the client, while receiving
  /// client frames on [fromClient].
  _i2.Stream<String> crdtStream(_i2.Stream<String> fromClient) =>
      caller.callStreamingServerEndpoint<_i2.Stream<String>, String>(
        'sync',
        'crdtStream',
        {},
        {'fromClient': fromClient},
      );
}

class Client extends _i1.ServerpodClientShared {
  Client(
    String host, {
    dynamic securityContext,
    _i1.AuthenticationKeyManager? authenticationKeyManager,
    Duration? streamingConnectionTimeout,
    Duration? connectionTimeout,
    Function(
      _i1.MethodCallContext,
      Object,
      StackTrace,
    )? onFailedCall,
    Function(_i1.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
  }) : super(
          host,
          _i3.Protocol(),
          securityContext: securityContext,
          authenticationKeyManager: authenticationKeyManager,
          streamingConnectionTimeout: streamingConnectionTimeout,
          connectionTimeout: connectionTimeout,
          onFailedCall: onFailedCall,
          onSucceededCall: onSucceededCall,
          disconnectStreamsOnLostInternetConnection:
              disconnectStreamsOnLostInternetConnection,
        ) {
    sync = EndpointSync(this);
  }

  late final EndpointSync sync;

  @override
  Map<String, _i1.EndpointRef> get endpointRefLookup => {'sync': sync};

  @override
  Map<String, _i1.ModuleEndpointCaller> get moduleLookup => {};
}
