import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An injectable wall-clock.
///
/// Time-dependent state (entitlement expiry today; chat-turn backoff/timeout
/// later) reads *now* through this seam instead of calling [DateTime.now]
/// directly, so tests can drive a deterministic, advanceable clock. See the
/// § Testability seam of docs/chat-state-architecture.md.
abstract interface class Clock {
  DateTime now();
}

/// The production clock: the real UTC wall time.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// The clock every time-dependent provider reads. Override in tests with a
/// fake advanceable clock to make expiry deterministic.
final clockProvider = Provider<Clock>((ref) => const SystemClock());
