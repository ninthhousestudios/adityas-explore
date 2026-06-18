import 'dart:async';
import 'dart:developer' as dev;
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'ephemeris_service.dart';
import 'swe_worker.dart' as worker;

Future<EphemerisService> createEphemerisService(String? ephePath) =>
    IsolateEphemerisService.spawn(ephePath);

class IsolateEphemerisService implements EphemerisService {
  IsolateEphemerisService._(this._port);

  final SendPort _port;

  static Future<IsolateEphemerisService> spawn(String? ephePath) async {
    final bootstrapPort = ReceivePort();
    await Isolate.spawn(worker.sweWorkerEntry, [
      bootstrapPort.sendPort,
      ephePath,
    ]);
    final reply = await bootstrapPort.first.timeout(
      const Duration(seconds: 10),
    );
    final port = reply as SendPort;
    dev.log('swe: worker isolate ready', name: 'IO');
    return IsolateEphemerisService._(port);
  }

  @override
  Future<R> chart<A, R>(
    ComputeCallback<A, R> fn,
    A args, {
    String? debugName,
  }) async {
    final replyPort = ReceivePort();
    _port.send([fn, args, replyPort.sendPort]);
    final response = await replyPort.first as List;
    if (response[0] == 'error') {
      throw StateError('Worker chart failed: ${response[1]}');
    }
    return response[1] as R;
  }

  @override
  Future<void> dispose() async {}
}
