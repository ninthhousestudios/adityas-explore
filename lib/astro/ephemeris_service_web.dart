import 'package:flutter/foundation.dart';

import 'ephemeris_service.dart';

Future<EphemerisService> createEphemerisService(String? ephePath) async =>
    WebEphemerisService();

class WebEphemerisService implements EphemerisService {
  @override
  Future<R> chart<A, R>(
    ComputeCallback<A, R> fn,
    A args, {
    String? debugName,
  }) async {
    return await fn(args);
  }

  @override
  Future<void> dispose() async {}
}
