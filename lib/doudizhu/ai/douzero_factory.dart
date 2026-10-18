import 'douzero_stub.dart'
    if (dart.library.io) 'douzero_io.dart'
    if (dart.library.js_interop) 'douzero_web.dart'
    as platform;
import 'douzero_runtime.dart';

DouZeroRuntime createDouZeroRuntime() => platform.createDouZeroRuntime();
