import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coalesces per-token delta publishes to a frame budget.
///
/// The jank source in a streaming chat is publishing state (and re-rendering)
/// once per token, not the rebuild itself (../ai tier-1 notes § Client notes).
/// The chat turn appends every delta to its buffer but publishes a new
/// `TurnStreaming` only through this seam, so the streaming-text widget repaints
/// at most once per budget window.
///
/// Injected so headless tests publish synchronously ([ImmediateThrottle]) — no
/// timers, no waiting on a frame.
abstract interface class DeltaThrottle {
  /// Request a publish. It may run now or coalesce with later requests into a
  /// single deferred call; only the most recent [publish] survives a window.
  void schedule(void Function() publish);

  /// Drop any pending publish — called on a terminal transition (so a queued
  /// streaming publish cannot resurrect a finished turn) and on teardown.
  void cancel();
}

/// A factory so each notifier owns its own throttle instance (a throttle holds
/// per-turn timer state), disposed with the notifier.
typedef DeltaThrottleFactory = DeltaThrottle Function();

/// Production throttle: one publish per [budget] (one 60fps frame by default).
class FrameThrottle implements DeltaThrottle {
  final Duration budget;

  Timer? _timer;
  void Function()? _pending;

  FrameThrottle([this.budget = const Duration(milliseconds: 16)]);

  @override
  void schedule(void Function() publish) {
    _pending = publish;
    _timer ??= Timer(budget, _fire);
  }

  void _fire() {
    _timer = null;
    final publish = _pending;
    _pending = null;
    publish?.call();
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}

/// Test throttle: publishes synchronously, making delta → state deterministic.
class ImmediateThrottle implements DeltaThrottle {
  const ImmediateThrottle();

  @override
  void schedule(void Function() publish) => publish();

  @override
  void cancel() {}
}

/// The throttle factory the chat turn reads. Override in tests with
/// `() => const ImmediateThrottle()`.
final deltaThrottleFactoryProvider = Provider<DeltaThrottleFactory>(
  (ref) => FrameThrottle.new,
);
