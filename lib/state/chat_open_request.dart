import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot "open the chat" signal fired from outside the chart wheel — the
/// Conversations picker's Resume (adityas/ai/86), which lives in the app-bar
/// account menu and cannot reach `_ChartWheelState`'s `LayoutMode` directly.
///
/// The value is a monotonically increasing counter: every [request] bumps it,
/// and `_ChartWheelState` `ref.listen`s for the change to switch into
/// conversation mode. A counter (not a bool) so two Resumes in a row each fire,
/// and so there is no "stuck open" flag to reset. keepAlive — app-lifetime, and
/// the chart wheel may be unmounted when the request is made (a chart-less
/// Resume just populates the conversation providers; the mode switch applies
/// when a chart is next open).
final chatOpenRequestProvider = NotifierProvider<ChatOpenRequest, int>(
  ChatOpenRequest.new,
);

class ChatOpenRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}
