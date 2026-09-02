import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A "open the chat" signal fired from outside the chart wheel — the
/// Conversations picker's Resume (adityas/ai/86), which lives in the app-bar
/// account menu and cannot reach `_ChartWheelState`'s `LayoutMode` directly.
///
/// The state is a monotonically increasing *request* counter; [request] bumps
/// it. `_ChartWheelState` acts on a pending request two ways, both routed
/// through [consumePending] so it opens exactly once:
///   - live, while mounted, via `ref.listen`;
///   - on mount, via a post-frame check — because the wheel is only in the tree
///     when a chart is loaded, a chart-less Resume from the birth form bumps the
///     counter with no listener attached, and `ref.listen` does NOT replay the
///     current value on attach. The watermark carries that pending request
///     across the mount.
///
/// keepAlive (app-lifetime): the [_consumed] watermark must survive the chart
/// wheel unmounting/remounting on a chart load, or a resume would re-open on
/// every later remount after the user has gone back to explore.
final chatOpenRequestProvider = NotifierProvider<ChatOpenRequest, int>(
  ChatOpenRequest.new,
);

class ChatOpenRequest extends Notifier<int> {
  /// The highest request the wheel has already acted on. Distinct from [state]
  /// (the request counter) so "is there a pending open?" is `state > _consumed`.
  int _consumed = 0;

  @override
  int build() => 0;

  /// Ask the chart wheel to switch into conversation mode.
  void request() => state++;

  /// Whether a request is outstanding, marking it consumed if so. Returns false
  /// once the current request has been acted on, so a remount does not re-open
  /// conversation mode the user has since dismissed.
  bool consumePending() {
    if (state <= _consumed) return false;
    _consumed = state;
    return true;
  }
}
