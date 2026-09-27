export 'lan_transport_stub.dart'
    if (dart.library.io) 'lan_transport_io.dart'
    if (dart.library.html) 'lan_transport_web.dart';
