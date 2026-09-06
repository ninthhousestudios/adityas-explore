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

  /// The deterministic label to stamp on the conversation *if this turn mints
  /// it* (`{chart-name snapshot} · {date}`, adityas/ai/64). Ignored once a
  /// conversation already exists — a title is a creation-time snapshot, not a
  /// per-turn field. Null → mint untitled (an old-client-compatible create).
  final String? conversationTitle;

  const TurnRequest({
    required this.text,
    this.parentMessageId,
    this.chart,
    this.conversationTitle,
  });
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

/// A tool call began. Carries the tool [tool] name and its decoded [args] (the
/// wire `args` object, JSON-shaped — the schema is the tool's own, so this is
/// not a vendor event format the closed vocabulary rule forbids). This is the
/// event the `show_being` seam rides: a `show_being` call names a being via
/// `args['slug']`, which the notifier resolves to a [BeingRef] and opens.
/// [args] is null when the frame carried none.
class ToolStartEvent extends TurnEvent {
  final String tool;
  final Map<String, Object?>? args;

  const ToolStartEvent(this.tool, super.eventId, {this.args});
}

/// A tool call finished. No state-layer effect in v1 (the being is opened on
/// [ToolStartEvent], which is the event the wire attaches the args to).
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

/// Raised when the transport rejects a request (a non-2xx REST response, or a
/// pre-flight failure like a missing token). Part of the transport *contract* —
/// it lives here, not in the concrete wire, so the notifier can catch it without
/// importing lib/ai (the `state-no-sse-wire` guard). Surfaces as a stream error
/// the notifier turns into a terminal state.
///
/// [statusCode] carries the REST status when the rejection was an HTTP response
/// (null for a pre-flight failure), so the notifier can branch a deliberate
/// server *gate* apart from a transient transport drop: **403** = access lapsed
/// (adityas/ai/99 → renew prompt, no retry), **402** = usage ceiling (ai/100),
/// **428** = consent stale (ai/98). Any other status, or null, is a generic
/// terminal error handled after the reconnect budget.
class TurnTransportException implements Exception {
  final String message;
  final int? statusCode;
  const TurnTransportException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// The seam the chat turn drives itself through.
///
/// Production will implement this over `fetch`+`ReadableStream` (web) /
/// `dart:io` (desktop) with `Last-Event-ID` resume and a server-side stop — the
/// sibling transport task. Tests supply a scripted fake. Neither the notifier
/// nor its tests know which.
abstract interface class TurnTransport {
  /// The server conversation subsequent turns append to: the adopted id after
  /// [adoptConversation], the id minted once [start] has created one, or null
  /// before any turn exists. The picker reads this to tell whether a deleted
  /// conversation is the active one — even when it was minted this session and
  /// so never landed in [Conversation.id] (adityas/ai/86).
  String? get conversationId;

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

  /// Append subsequent turns to an existing server conversation [id] (Resume,
  /// adityas/ai/86). Replaces the cached conversation and clears the turn
  /// cursor, so the next [start] posts to the resumed thread rather than
  /// minting a fresh one.
  void adoptConversation(String id);

  /// Forget the cached conversation so the next [start] mints a fresh one (New
  /// Chat, and the user-change reset in main.dart). Does not touch the server.
  void resetConversation();
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
