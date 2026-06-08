import 'package:arrow_swe/arrow_swe.dart';
import 'swe.dart';

SweFacade? workerFacade;

bool workerAborted = false;

class SweAborted implements Exception {
  const SweAborted();
  @override
  String toString() => 'SweAborted';
}

void checkSweAborted() {
  if (workerAborted) throw const SweAborted();
}

R runWithSwe<R>(String? ephePath, R Function(SweFacade facade) body) {
  final facade = workerFacade;
  if (facade != null) return body(facade);
  final swe = openSwissEph(ephePath);
  try {
    return body(SweFacade(swe, ephePath: ephePath));
  } finally {
    swe.close();
  }
}
