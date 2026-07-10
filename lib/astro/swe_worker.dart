import 'dart:isolate';

import 'package:arrow_swe/arrow_swe.dart';

import 'swe_compute.dart';

void sweWorkerEntry(List<Object?> args) {
  final mainPort = args[0] as SendPort;
  final ephePath = args[1] as String?;

  workerFacade = SweFacade.create(ephePath: ephePath);

  final port = ReceivePort();
  mainPort.send(port.sendPort);

  port.listen((message) async {
    final msg = message as List;
    final fn = msg[0] as Function;
    final fnArgs = msg[1];
    final replyPort = msg[2] as SendPort;
    try {
      final result = await fn(fnArgs);
      replyPort.send(['ok', result]);
    } catch (e) {
      replyPort.send(['error', e.toString()]);
    }
  });
}
