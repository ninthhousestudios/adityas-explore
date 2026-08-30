import 'package:charts_dart/charts_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The turn transport seam and the internal event vocabulary the chat state
/// machine consumes.
///
/// This is the boundary between the reactive state layer (adityas/explore/44)
/// and the real SSE wire, which is a **sibling task** — deliberately NOT built
/// here. [chatTurnProvider]'s notifier drives itself entirely from the
/// [TurnEvent]s a [TurnTransport] yields, so it is exercised headless by a
/// scripted fake. See docs/chat-state-architecture.md § Testability seam.

/// Billing outcome of a generation: usage arrives at the end of a stream, or
/// never (a broken stream). The client-side ledger tolerates the gap; a
/// cancelled turn is still billed (non-refunding). See ../ai tier-1 notes
/// § Budget mechanics.
class TurnUsage {
  final int inputTokens;
  final int outputTokens;

  const TurnUsage({required this.inputTokens, required this.outputTokens});

  /// A clean completion that reported no usage (a zero-cost turn).
  const TurnUsage.zero() : inputTokens = 0, outputTokens = 0;

  int get totalTokens => inputTokens + outputTokens;
}

/// What the client hands the transport to start a turn: the user's message, its
/// place in the conversation tree (`parent_message_id`), and the currently-open
/// [chart]. Kept minimal — the backend owns conversation/turn identity.
///
/// [chart], when non-null, is the open chart's birth data. The transport rides
/// it along as the backend's `ChartInput` (adityas/ai/63/65) so the harness can
/// compute `chart_facts` and the model can speak about the person's own
/// activated beings. Null → a chart-less turn.
class TurnRequest {
  final String text;
  final String? parentMessageId;
  final ChartData? chart;

  const TurnRequest({required this.text, this.parentMessageId, this.chart});
}

/// One normalized event from a generation stream.
///
/// The transport adapts a vendor's SSE into this closed vocabulary — **never**
/// adopt a vendor's JSON as the internal format (../ai tier-1 notes § Models
/// and providers). Every event carries the SSE `id:` as [eventId] so a
/// reconnect can replay from the last one via `Last-Event-ID`.
///
/// Sealed: a future *recognized* event type is a new subtype, and the exhaustive
/// `switch` in the notifier then fails to compile until it is handled. A wire
/// event this build does **not** recognize is a different thing — the SSE parse
/// task maps it to [UnknownEvent], which the notifier ignores (explore is a
/// shipped binary; old versions must survive new server events).
sealed class TurnEvent {
  /// The SSE `id:` — the `Last-Event-ID` cursor a resume replays from.
  final String eventId;

  const TurnEvent(this.eventId);
}

/// A chunk of generated text.
class DeltaEvent extends TurnEvent {
  final String text;

  const DeltaEvent(this.text, super.eventId);
}

/// A tool call began (e.g. `show_being`). No state-layer effect in v1.
class ToolStartEvent extends TurnEvent {
  final String tool;

  const ToolStartEvent(this.tool, super.eventId);
}

/// A tool call finished. No state-layer effect in v1.
class ToolEndEvent extends TurnEvent {
  final String tool;

  const ToolEndEvent(this.tool, super.eventId);
}

/// A grounding citation (`source_id`). No state-layer effect in v1.
class CitationEvent extends TurnEvent {
  final String sourceId;

  const CitationEvent(this.sourceId, super.eventId);
}

/// The turn's billing settlement, delivered once near the end.
class UsageEvent extends TurnEvent {
  final TurnUsage usage;

  const UsageEvent(this.usage, super.eventId);
}

/// Clean terminal signal: the generation completed.
class DoneEvent extends TurnEvent {
  const DoneEvent(super.eventId);
}

/// A server-sent error event — terminal, but retryable from [eventId].
class ErrorEvent extends TurnEvent {
  final String message;

  const ErrorEvent(this.message, super.eventId);
}

/// A wire event type this build does not recognize. Ignored by the state layer;
/// its [eventId] still advances the cursor so a resume skips past it.
class UnknownEvent extends TurnEvent {
  final String type;

  const UnknownEvent(this.type, super.eventId);
}

/// The seam the chat turn drives itself through.
///
/// Production will implement this over `fetch`+`ReadableStream` (web) /
/// `dart:io` (desktop) with `Last-Event-ID` resume and a server-side stop — the
/// sibling transport task. Tests supply a scripted fake. Neither the notifier
/// nor its tests know which.
abstract interface class TurnTransport {
  /// Start a fresh turn; yields its [TurnEvent] stream.
  Stream<TurnEvent> start(TurnRequest request);

  /// Re-attach to the in-flight turn, replaying events after [cursor]
  /// (`Last-Event-ID`). The accumulated text is preserved client-side; this
  /// yields only what came after the drop.
  Stream<TurnEvent> resume(String cursor);

  /// Server-side stop of the in-flight generation. Non-refunding: the server
  /// still finalizes a usage event for tokens already produced. Closing the
  /// client stream alone is not enough — you keep paying (../ai tier-1 notes
  /// § Client notes).
  Future<void> cancel();
}

/// The transport [chatTurnProvider] consumes.
///
/// The default throws: the real SSE wire (`SseTurnTransport`, lib/ai) is injected
/// as a Riverpod override at the composition root (main.dart), and the chat panel
/// watches [chatTurnProvider] and sends through it. This provider must be
/// overridden before use — a live override in the app, a fake in tests. Keeping
/// the wire out of the default is what lets lib/state stay off the lib/ai wire
/// (the state-no-sse-wire guard).
final turnTransportProvider = Provider<TurnTransport>((ref) {
  throw UnimplementedError(
    'No real TurnTransport yet — the SSE wire is a sibling task. '
    'Override turnTransportProvider (with a fake in tests) before use.',
  );
});
