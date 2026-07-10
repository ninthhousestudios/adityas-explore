import 'package:arrow_swe/arrow_swe.dart';

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
  final cached = workerFacade;
  if (cached != null) return body(cached);
  final facade = SweFacade.create(ephePath: ephePath);
  try {
    return body(facade);
  } finally {
    facade.dispose();
  }
}
