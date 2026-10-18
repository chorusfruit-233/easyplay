import 'rapfi_stub.dart'
    if (dart.library.js_interop) 'rapfi_web.dart'
    if (dart.library.io) 'rapfi_io.dart'
    as platform;
import 'rapfi_transport.dart';

RapfiTransport createRapfiTransport() => platform.createRapfiTransport();
