export 'database_stub.dart'
    if (dart.library.ffi) 'native_database.dart'
    if (dart.library.js_interop) 'web_database.dart';
