import 'package:flutter/foundation.dart';

import 'ephemeris_service_native.dart'
    if (dart.library.js_interop) 'ephemeris_service_web.dart'
    as impl;

abstract class EphemerisService {
  Future<R> chart<A, R>(ComputeCallback<A, R> fn, A args, {String? debugName});
  Future<void> dispose();
}

Future<EphemerisService> createEphemerisService(String? ephePath) =>
    impl.createEphemerisService(ephePath);
