/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/serverpod.dart' as _i1;
import '../sync_endpoint.dart' as _i2;

class Endpoints extends _i1.EndpointDispatch {
  @override
  void initializeEndpoints(_i1.Server server) {
    var endpoints = <String, _i1.Endpoint>{
      'sync': _i2.SyncEndpoint()
        ..initialize(
          server,
          'sync',
          null,
        )
    };
    connectors['sync'] = _i1.EndpointConnector(
      name: 'sync',
      endpoint: endpoints['sync']!,
      methodConnectors: {
        'crdtStream': _i1.MethodStreamConnector(
          name: 'crdtStream',
          params: {},
          streamParams: {
            'fromClient': _i1.StreamParameterDescription<String>(
              name: 'fromClient',
              nullable: false,
            )
          },
          returnType: _i1.MethodStreamReturnType.streamType,
          call: (
            _i1.Session session,
            Map<String, dynamic> params,
            Map<String, Stream> streamParams,
          ) =>
              (endpoints['sync'] as _i2.SyncEndpoint).crdtStream(
            session,
            streamParams['fromClient']!.cast<String>(),
          ),
        )
      },
    );
  }
}
