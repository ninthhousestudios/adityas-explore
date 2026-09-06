import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/chat_access.dart';
import '../format/date_labels.dart';
import '../ui/being_slug.dart';
import 'active_chart.dart';
import 'clock.dart';
import 'conversation.dart';
import 'delta_throttle.dart';
import 'entitlement.dart';
import 'overlay.dart';
import 'turn_transport.dart';
import 'usage.dart';

/// The reactive core of the chat feature: the [ChatTurn] sealed state machine
/// and the notifier that drives it from an injected [TurnTransport].
///
/// ```
/// idle → connecting → streaming ⇄ reconnecting
///                        │  │
///                        │  ├→ cancelled      (client stop → server stop; still billed)
///                        │  ├→ error          (terminal-with-retry; carries the cursor)
///                        │  ├→ access-lapsed   (window closed: clock or 403; renew prompt, no retry)
///                        │  ├→ ceiling         (usage spent: 402; at-ceiling notice, no retry)
///                        │  └→ done
/// ```
///
/// See docs/chat-state-architecture.md § `ChatTurn` sealed state machine and
/// § The v3 pause trap.

/// One state of an in-flight (or finished) generation. Sealed → the UI matches
/// it exhaustively.
sealed class ChatTurn {
  const ChatTurn();
}

/// No turn in flight.
class TurnIdle extends ChatTurn {
  const TurnIdle();
}

/// The turn is being opened (POST accepted, stream not yet delivering).
class TurnConnecting extends ChatTurn {
  const TurnConnecting();
}

/// Tokens are arriving. [text] is the accumulated delta buffer; [cursor] is the
/// `Last-Event-ID` resume point.
class TurnStreaming extends ChatTurn {
  final String text;
  final String? cursor;

  const TurnStreaming({required this.text, required this.cursor});
}

/// The stream dropped; re-attaching from [cursor]. [text] so far is preserved
/// across the gap — the resume replays only what came after.
class TurnReconnecting extends ChatTurn {
  final String text;
  final String? cursor;
  final int attempt;

  const TurnReconnecting({
    required this.text,
    required this.cursor,
    required this.attempt,
  });
}

/// The turn completed cleanly. [usage] settles billing (usage-at-end).
///
/// [usage] is `null` when the generation reached [DoneEvent] but no
/// [UsageEvent] ever arrived — a billing *gap* the ledger must reconcile,
/// deliberately distinct from an explicit [TurnUsage.zero] (a server-reported
/// zero-cost turn). Never collapse the gap into zero: a dropped/reordered usage
/// event would then be indistinguishable from a legitimately free turn.
class TurnDone extends ChatTurn {
  final String text;
  final TurnUsage? usage;

  const TurnDone({required this.text, required this.usage});
}

/// The user stopped the turn. [text] is the partial output; [usage] is still
/// billed (non-refunding) and may be `null` until the server's trailing usage
/// event lands — or forever, if the stream broke first.
class TurnCancelled extends ChatTurn {
  final String text;
  final TurnUsage? usage;

  const TurnCancelled({required this.text, required this.usage});
}

/// The turn ended in error. [cursor] is carried for a retry; [usage] is `null`
/// on a broken stream (the usage event never arrived).
class TurnError extends ChatTurn {
  final String message;
  final String? cursor;
  final TurnUsage? usage;

  const TurnError({
    required this.message,
    required this.cursor,
    required this.usage,
  });
}

/// Access lapsed — the entitlement window closed on this turn (adityas/ai/99).
///
/// Terminal and distinct from [TurnError]: the UI surfaces a calm *renew* prompt,
/// not a retryable error, because retrying would only re-lapse until the window
/// is renewed. Reached two ways, both converging here:
///   - the injected [Clock] crossed `access_until` mid-turn ([_expire]); or
///   - a `/v1/ai` write route returned **403** (the server's authoritative gate),
///     surfaced by the transport as a status-carrying `TurnTransportException`.
/// [text] is whatever streamed before the lapse (usually empty — a 403 fires on
/// the opening POST, before any delta); [usage] is any billing that settled.
///
/// No [cursor]: a lapsed turn is not resumable from the client (the server will
/// refuse it), so nothing carries a retry point. Distinct from **402** (ceiling,
/// ai/100) and **428** (consent, ai/98), which get their own states.
class TurnAccessLapsed extends ChatTurn {
  final String text;
  final TurnUsage? usage;

  const TurnAccessLapsed({required this.text, required this.usage});
}

/// Usage ceiling reached — the window budget is spent (adityas/ai/100).
///
/// Terminal and distinct from both [TurnError] and [TurnAccessLapsed]: a **402
/// Payment Required** from the opening `POST .../turns` is a pre-accept gate —
/// the window's usage is exhausted, so no turn is spawned and nothing streams.
/// The UI surfaces a calm at-ceiling notice; new turns are refused until the
/// window resets/renews, so there is no retry [cursor] (a retry only re-hits the
/// 402), exactly as a lapse carries none.
///
/// Never a dollar or token figure (the no-meter invariant): the notice is a plain
/// "you've reached your usage limit for this period." [text]/[usage] carry
/// whatever settled before the gate — normally empty, since 402 fires on the POST
/// before any delta. Distinct from **403** (access lapsed, ai/99) and **428**
/// (consent, ai/98).
class TurnCeiling extends ChatTurn {
  final String text;
  final TurnUsage? usage;

  const TurnCeiling({required this.text, required this.usage});
}

/// The chat turn.
///
/// **keepAlive `NotifierProvider` owning an imperative subscription — NOT a
/// `StreamProvider`.** A `StreamProvider` would have Riverpod 3 *pause* its
/// subscription the moment the chat panel unmounts on a mode switch, stalling
/// generation mid-answer (docs/chat-state-architecture.md § The v3 pause trap).
/// keepAlive + a hand-owned `StreamSubscription` keeps filling the buffer with
/// zero widget listeners; the server-side durable log + `Last-Event-ID` cursor
/// is the correctness backstop.
final chatTurnProvider = NotifierProvider<ChatTurnNotifier, ChatTurn>(
  ChatTurnNotifier.new,
);

class ChatTurnNotifier extends Notifier<ChatTurn> {
  static const int _maxReconnects = 3;

  late TurnTransport _transport;
  late DeltaThrottle _throttle;

  // The delta buffer and cursor live HERE, in the notifier — not the widget —
  // so they survive the panel unmounting (§ ChatTurn sealed state machine).
  final StringBuffer _buffer = StringBuffer();
  String? _cursor;
  TurnUsage? _usage;

  StreamSubscription<TurnEvent>? _sub;
  int _reconnects = 0;

  // A cancelled turn keeps its subscription open to receive the server's
  // trailing usage/done (non-refunding settlement). `_cancelling` is the latch
  // for that window: set on [cancel], cleared only once the stopped turn
  // settles. While it is set the turn is still busy — [send] must refuse — or a
  // fresh turn would tear down the subscription and lose the trailing usage.
  bool _cancelling = false;

  // Authoritative access-lapse latch. Set when a `/v1/ai` write route returns
  // 403, or the clock crosses `access_until` on a non-allowlisted account
  // ([_lapse]). While set, [send] hard-refuses new turns into the renew prompt —
  // it does NOT re-derive availability from [chatAccessProvider], whose value can
  // still read `available` off a stale cached entitlement during the post-403
  // refetch window. Cleared only when the [chatAvailableProvider] listen sees
  // access flip back to true (a fresh fetch proving renewed access).
  // (adityas/ai/123 finding 2.)
  bool _lapsed = false;

  // At-ceiling latch. Set when a `POST .../turns` returns 402 (the window budget
  // is spent, adityas/ai/100). While set, [send] hard-refuses new turns into the
  // at-ceiling notice rather than opening one the server will 402 again (which
  // would also append a duplicate user message). Separate axis from [_lapsed]:
  // access can be live (a valid window) while its usage budget is exhausted.
  // Released by [_recheckCeiling] — a direct, freshly-fetched headroom read below
  // [usageNearCeilingThreshold] is the only proof the window reset/renewed
  // (adityas/ai/129 findings 1 & 2). A ceilinged turn never settles, so nothing
  // else ever refetches usage; the release cannot lean on the cached provider.
  bool _ceilinged = false;

  // The id of the optimistic user message appended by the current [send], held
  // until the turn is accepted (first event) so a pre-accept 402 can roll it back
  // (adityas/ai/129 finding 3). Null once any event proves acceptance, or between
  // turns.
  String? _pendingUserId;

  // Fires at `access_until` to end an in-flight turn the instant entitlement
  // lapses. Driven by the injected [Clock] (delay) + a real [Timer]; the
  // [chatAvailableProvider] listen only reacts to provider *changes*, which
  // never fire on the wall-clock boundary by themselves.
  Timer? _expiryTimer;

  // Set once the notifier is disposed, so the fire-and-forget [_recheckCeiling]
  // future does not touch a torn-down `ref` if it resolves after dispose.
  bool _disposed = false;

  @override
  ChatTurn build() {
    // read, not watch: a rebuild would drop an in-flight turn, and these
    // providers are stable for the app's lifetime. The turn stays put across
    // every mode switch precisely because nothing here triggers a rebuild.
    _transport = ref.read(turnTransportProvider);
    _throttle = ref.read(deltaThrottleFactoryProvider)();

    // Expiry / sign-out mid-turn is a real application state: observe it
    // WITHOUT rebuilding (which would reset the turn). listen, not watch.
    ref
      ..listen(chatAvailableProvider, (_, available) {
        if (available == false) {
          _expire();
        } else {
          // A fresh entitlement fetch proved access is live again — release the
          // lapse latch so sends resume (adityas/ai/123 finding 2).
          _lapsed = false;
        }
      })
      ..onDispose(() {
        _disposed = true;
        _closeSub();
        _throttle.cancel();
        _cancelExpiryTimer();
      });

    return const TurnIdle();
  }

  /// Send a user message, opening a new turn. No-op if a turn is already active
  /// (one turn at a time), if a cancelled turn is still settling, or if the
  /// message is blank.
  void send(String text) {
    // `_cancelling`: a cancelled turn awaiting its trailing usage/done still
    // owns the transport subscription. Opening a new turn now would reset it and
    // drop the stopped turn's (billable) usage.
    if (_isActive || _cancelling) return;
    // A prior authoritative lapse (a 403 on a write route, or the clock crossing
    // `access_until`) hard-stops new turns until a fresh entitlement fetch proves
    // renewed access. The derived [chatAccessProvider] below can still read
    // `available` off a stale cached entitlement in the refetch window right
    // after a 403; this latch does not, so it is the reliable gate there. It also
    // refuses the immediate resend that would otherwise append a second user
    // message and re-hit the same 403 (adityas/ai/123 finding 2).
    if (_lapsed) {
      state = const TurnAccessLapsed(text: '', usage: null);
      return;
    }
    // The window budget is spent (a prior 402); refuse into the at-ceiling notice
    // — a doomed resend would re-hit the 402 and append a duplicate user message
    // (adityas/ai/100). Do NOT release off the cached [usageProvider] value here:
    // it is retained stale through loading/error, and the 402 came from the turn
    // route (not the usage endpoint), so that cache can read a pre-ceiling <100
    // and clear the latch into another 402 (adityas/ai/129 finding 2). Instead
    // kick a direct, freshly-fetched headroom re-read ([_recheckCeiling]) that
    // self-heals the latch once the window truly reset — the only reset signal,
    // since a ceilinged turn never settles to trigger the settle-time refetch
    // (adityas/ai/129 finding 1).
    if (_ceilinged) {
      state = const TurnCeiling(text: '', usage: null);
      unawaited(_recheckCeiling());
      return;
    }
    // UX gate; the backend is the authoritative entitlement check. Defense in
    // depth against opening a turn the server will refuse anyway. A *lapsed*
    // window refuses into the renew prompt ([TurnAccessLapsed], adityas/ai/120) —
    // the same surface a mid-session 403 lands on — so a former subscriber who
    // opens their read-only history and types gets "renew", not a generic error.
    // Never-entitled/signed-out stays the generic refusal (its buy/sign-in
    // surface is the coming-soon gate, adityas/ai/85).
    final access = ref.read(chatAccessProvider);
    if (access != ChatAccess.available) {
      state = access == ChatAccess.lapsed
          ? const TurnAccessLapsed(text: '', usage: null)
          : const TurnError(
              message: 'Chat is not available.',
              cursor: null,
              usage: null,
            );
      return;
    }
    final message = text.trim();
    if (message.isEmpty) return;

    final userMessage = ref
        .read(conversationProvider.notifier)
        .appendUser(message);
    _resetTurn();
    // Track the optimistic append so a pre-accept 402 can roll it back — the
    // server never spawned that turn, so its user message must not linger as a
    // ghost that diverges the local chain (adityas/ai/129 finding 3). Cleared the
    // moment any event proves the turn was accepted (see [_onEvent]).
    _pendingUserId = userMessage.id;
    state = const TurnConnecting();
    // Stream creation can throw synchronously (e.g. no transport wired, bad
    // request). Catch it here so the turn ends in a terminal error rather than
    // stranding an active state with no subscription (which would silently
    // swallow every later send).
    final chart = ref.read(activeChartProvider);
    final Stream<TurnEvent> events;
    try {
      events = _transport.start(
        TurnRequest(
          text: message,
          parentMessageId: userMessage.id,
          // The open chart at send time (adityas/ai/65) — grounds the answer in
          // this person's chart_facts. Null when no chart is open ⇒ chart-less.
          chart: chart,
          // The deterministic picker label, used only if THIS turn mints the
          // conversation: `{chart · date}` snapshotted at creation (ai/64).
          conversationTitle: _composeTitle(chart?.name),
        ),
      );
    } catch (error) {
      _fail('Failed to start the turn: $error');
      return;
    }
    _subscribe(events);
    _scheduleExpiry();
  }

  /// Stop the turn. Maps to a server-side stop, not merely closing the client
  /// stream (or we keep paying). Non-refunding: a trailing usage event still
  /// settles billing on the resulting [TurnCancelled].
  Future<void> cancel() async {
    if (!_isActive) return;
    _cancelling = true;
    _throttle.cancel();
    _cancelExpiryTimer();
    // Reflect the stop immediately; the subscription stays open to receive the
    // server's trailing usage/done for the stopped turn.
    state = TurnCancelled(text: _buffer.toString(), usage: _usage);
    // Commit whatever streamed before the stop as an incomplete assistant
    // message — the partial the user was reading (option (a), adityas/ai/126).
    // Done here, the single entry point to a cancelled turn, it lands exactly
    // once regardless of how the stopped stream later settles (trailing
    // usage/done, a clean close, or a broken stream that never delivers done).
    // _finish therefore appends only on its TurnDone (non-cancelling) path.
    if (_buffer.isNotEmpty) {
      ref
          .read(conversationProvider.notifier)
          .appendAssistant(_buffer.toString());
    }
    await _transport.cancel();
  }

  /// Rotate to a fresh conversation without changing the chart (New Chat, and
  /// the reset after deleting the active conversation — adityas/ai/86). A turn
  /// in flight is stopped server-side first (non-refunding, still billed) so a
  /// lingering generation never lands in the new thread. Synchronous: called
  /// from a button handler, never build/dispose.
  void startNewConversation() {
    _stopActiveForRotation();
    _transport.resetConversation();
    ref.read(conversationProvider.notifier).reset();
    state = const TurnIdle();
  }

  /// Resume a past conversation (adityas/ai/86): adopt its server [id] so the
  /// next turn appends to it, load its transcript into the buffer, and settle to
  /// idle — nothing is sent until the user types. Does not touch the chart.
  void resumeConversation(
    String id,
    List<({MessageRole role, String text, DateTime? createdAt})> messages, {
    DateTime? compactedThrough,
  }) {
    _stopActiveForRotation();
    _transport.adoptConversation(id);
    ref
        .read(conversationProvider.notifier)
        .loadTranscript(id, messages, compactedThrough: compactedThrough);
    state = const TurnIdle();
  }

  /// Tear down any in-flight turn before switching conversations: a best-effort
  /// server-side stop (so we stop paying for a generation we're abandoning) plus
  /// a local reset of the buffer/subscription/timers. The server's durable log
  /// still settles that turn's billing; the client just stops listening.
  void _stopActiveForRotation() {
    if (_isActive) unawaited(_transport.cancel());
    _resetTurn();
  }

  /// The deterministic conversation label minted at creation: `{chart · date}`
  /// (adityas/ai/64). [chartName] is the open chart's name at send time, or null
  /// for a chart-less chat. The date is today's (creation time), via the
  /// injected clock so tests are deterministic.
  String _composeTitle(String? chartName) {
    final date = shortMonthDay(ref.read(clockProvider).now());
    final name = (chartName == null || chartName.trim().isEmpty)
        ? 'Chat'
        : chartName.trim();
    return '$name · $date';
  }

  void _subscribe(Stream<TurnEvent> events) {
    _sub = events.listen(
      _onEvent,
      onError: _onStreamError,
      onDone: _onStreamDone,
      cancelOnError: true,
    );
  }

  void _onEvent(TurnEvent event) {
    // Any event proves the server accepted the turn — the optimistic user append
    // is real, so drop the pre-accept rollback tracking (adityas/ai/129).
    _pendingUserId = null;
    _cursor = event.eventId; // advance on every event, even ignored ones
    switch (event) {
      case DeltaEvent(:final text):
        _buffer.write(text);
      case UsageEvent(:final usage):
        _usage = usage;
        if (_cancelling) {
          // Trailing usage for a stopped turn: settle it on the cancelled state.
          state = TurnCancelled(text: _buffer.toString(), usage: usage);
          return;
        }
      case DoneEvent():
        _finish();
        return;
      case ErrorEvent(:final message):
        // A server error on a turn the user already stopped settles the cancel
        // (keep TurnCancelled + whatever usage arrived); it does not un-cancel
        // into TurnError.
        if (_cancelling) {
          _settleCancelled();
        } else {
          _fail(message);
        }
        return;
      case ToolStartEvent(:final tool, :final args):
        // The `show_being` seam: the model *intentionally* calls the show_being
        // UI tool (distinct from the get_being knowledge read) to open a being's
        // detail card — resolve its slug to a BeingRef and open the popup with no
        // BuildContext (docs/chat-state-architecture.md § Overlay ripple). Only
        // show_being navigates; the knowledge tools (get_being/search/
        // structural_rules/fetch_source) never do. An unresolvable slug degrades
        // to a no-op.
        if (tool == 'show_being') {
          final slug = args?['slug'];
          if (slug is String) {
            final being = resolveBeingSlug(slug);
            if (being != null) {
              // Prefer the chart-placed planet card (Position/Soul Stance/planet
              // glyph) when a displayed planet in the open chart activates this
              // being, so a chat-opened card matches one opened by tapping the
              // glyph (adityas/ai/84). Otherwise open the placement-free being
              // card.
              final overlay = ref.read(overlayControllerProvider.notifier);
              final chart = ref.read(chartControllerProvider).chart;
              final placed = chart == null
                  ? null
                  : planetActivatingBeing(chart, being.sign, being.type);
              if (placed != null) {
                overlay.showPlanetBeing(placed);
              } else {
                overlay.showBeing(being);
              }
            }
          }
        }
      case ToolEndEvent():
        // No state-layer effect: the being opened on tool_start. The cursor was
        // already advanced, so a resume skips past it.
        break;
      case CitationEvent():
      case UnknownEvent():
        // v1 has no citation UI, and an unrecognized event is ignored for
        // forward compatibility (explore is a shipped binary). The cursor was
        // already advanced, so a resume skips past them.
        break;
    }
    _publishStreaming();
  }

  /// A stream error is a transient transport drop → reconnect from the cursor.
  /// `cancelOnError` already tore this subscription down; resume on a fresh one.
  void _onStreamError(Object error, StackTrace stackTrace) {
    _sub = null;
    if (_cancelling) {
      // The stopped turn's stream broke before (or after) settling — the
      // settlement window is over. Release the latch so a new turn can open.
      _cancelling = false;
      return;
    }
    if (_isTerminal(state)) return;
    // A deliberate server gate is terminal, NOT a transient drop — do not spend
    // the reconnect budget retrying it (a retry only re-hits the same gate).
    // 403 = access lapsed → the renew prompt (adityas/ai/99). 402 = usage ceiling
    // → the at-ceiling notice (ai/100). 428 (consent, ai/98) branches here too
    // when it lands; until then it falls through to the generic error below.
    if (error is TurnTransportException) {
      if (error.statusCode == 403) {
        _lapse();
        return;
      }
      if (error.statusCode == 402) {
        _ceiling();
        return;
      }
    }
    if (_reconnects >= _maxReconnects) {
      _fail('Stream failed after $_maxReconnects reconnect attempts: $error');
      return;
    }
    _reconnects++;
    _throttle.cancel();
    state = TurnReconnecting(
      text: _buffer.toString(),
      cursor: _cursor,
      attempt: _reconnects,
    );
    // As with start(), resume() can throw synchronously; fail terminally rather
    // than strand the turn in TurnReconnecting with no subscription.
    final Stream<TurnEvent> events;
    try {
      events = _transport.resume(_cursor ?? '');
    } catch (resumeError) {
      _fail('Reconnect failed: $resumeError');
      return;
    }
    _subscribe(events);
  }

  /// The stream closed before a terminal event → the generation broke. Usage
  /// precedes done, so it typically never arrived — the turn is unbilled from
  /// the client's view and the ledger tolerates the gap.
  void _onStreamDone() {
    if (_cancelling) {
      // The stopped turn's stream closed — settlement is over (usage arrived on
      // it, or never). Release the latch; the TurnCancelled state stands.
      _cancelling = false;
      _closeSub();
      return;
    }
    if (_isTerminal(state)) return;
    _fail('Stream closed before completing.');
  }

  void _publishStreaming() {
    _throttle.schedule(() {
      // A publish queued before a terminal transition must not resurrect the
      // stream.
      if (_isTerminal(state) || _cancelling) return;
      _reconnects = 0; // a delivered event means the stream is healthy again
      state = TurnStreaming(text: _buffer.toString(), cursor: _cursor);
    });
  }

  void _finish() {
    if (_cancelling) {
      // A cancelled turn already committed its partial in [cancel]; settling on
      // a trailing done must not append it a second time (adityas/ai/126).
      _settleCancelled();
      return;
    }
    _closeSub();
    _throttle.cancel();
    _cancelExpiryTimer();
    // `_usage` stays null when done arrived without a usage event: a billing
    // gap, NOT a zero-cost turn. TurnDone.usage is nullable precisely so the
    // ledger can tell the two apart (see TurnDone).
    state = TurnDone(text: _buffer.toString(), usage: _usage);
    if (_buffer.isNotEmpty) {
      ref
          .read(conversationProvider.notifier)
          .appendAssistant(_buffer.toString());
    }
    // A settled turn is the only time the window spend moves — refetch the
    // headroom so the near-ceiling notice reflects it without a wall-clock poll
    // (adityas/ai/100). autoDispose means this no-ops when nothing watches usage.
    ref.invalidate(usageProvider);
  }

  /// Close out a turn the user stopped: keep [TurnCancelled] with whatever usage
  /// settled, and release the `_cancelling` latch so a new turn may open.
  void _settleCancelled() {
    _cancelling = false;
    _closeSub();
    _throttle.cancel();
    _cancelExpiryTimer();
    state = TurnCancelled(text: _buffer.toString(), usage: _usage);
    // A cancelled turn is still billed (non-refunding), so its spend moved too —
    // refresh the headroom for the near-ceiling notice (adityas/ai/100).
    ref.invalidate(usageProvider);
  }

  void _fail(String message) {
    _closeSub();
    _throttle.cancel();
    _cancelExpiryTimer();
    state = TurnError(message: message, cursor: _cursor, usage: _usage);
  }

  /// The injected [Clock] crossed `access_until` mid-turn — the entitlement
  /// window closed. Converges on [_lapse] (the renew prompt), same as a server
  /// 403; guarded so a fired timer on an already-settled turn is a no-op.
  void _expire() {
    if (!_isActive) return;
    // The timer is armed at a cached `access_until`, but the clock crossing it
    // does not always mean access ended. Two cases must NOT lapse a valid turn
    // (adityas/ai/123 finding 4):
    //   - an allowlisted account stays available independently of the entitlement
    //     window ([chatEnabledProvider]); the entitlement clock is not its gate.
    //   - a mid-turn renewal may have pushed the deadline into the future.
    // Re-read the authoritative seams directly — not the cached
    // [chatAvailableProvider], which recomputes only on dependency change and so
    // still reads its pre-boundary value at the instant the timer fires.
    if (ref.read(chatEnabledProvider)) {
      _cancelExpiryTimer();
      return;
    }
    final deadline = ref.read(accessDeadlineProvider);
    if (deadline != null && deadline.isAfter(ref.read(clockProvider).now())) {
      _scheduleExpiry(); // renewal extended the window — re-arm at the new deadline
      return;
    }
    _lapse();
  }

  /// Terminal access-lapse → the renew prompt ([TurnAccessLapsed], adityas/ai/99).
  /// Reached by the clock ([_expire]) or a `/v1/ai` write route's 403. Best-effort
  /// server stop so a lapsed turn does not keep generating on our budget (the
  /// server enforces entitlement regardless), then invalidate the cached
  /// entitlement so the derived [chatAvailableProvider] re-fetches the
  /// authoritative `access_until` and further sends are refused (or self-heal if
  /// the window was renewed).
  void _lapse() {
    _closeSub();
    _throttle.cancel();
    _cancelExpiryTimer();
    unawaited(_transport.cancel());
    // Persist whatever streamed before the lapse as an incomplete assistant
    // message, exactly as [_finish] commits a completed reply — otherwise the
    // partial answer the user was watching vanishes the instant the renew prompt
    // replaces the streaming bubble, and is lost on the next transition
    // (adityas/ai/123 finding 1).
    if (_buffer.isNotEmpty) {
      ref
          .read(conversationProvider.notifier)
          .appendAssistant(_buffer.toString());
    }
    // Latch the lapse so [send] hard-refuses further turns until a fresh fetch
    // proves renewed access (adityas/ai/123 finding 2). Invalidate drives that
    // refetch; the [chatAvailableProvider] listen clears the latch on renewal.
    _lapsed = true;
    ref.invalidate(entitlementProvider);
    state = TurnAccessLapsed(text: _buffer.toString(), usage: _usage);
  }

  /// Terminal at-ceiling → the usage-limit notice ([TurnCeiling], adityas/ai/100).
  /// Reached when `POST .../turns` returns 402: the window budget is spent. A 402
  /// is a pre-accept gate (no turn spawned), so the buffer is normally empty; the
  /// same commit-partial guard as [_lapse] still runs for symmetry. Best-effort
  /// server stop for the same reason. Latch the ceiling so [send] refuses further
  /// turns, and refetch usage so the derived near notice reflects the exhausted
  /// window (and the latch self-heals once a fetch shows the window reset).
  void _ceiling() {
    _closeSub();
    _throttle.cancel();
    _cancelExpiryTimer();
    unawaited(_transport.cancel());
    // A 402 is a pre-accept gate: no turn was spawned, so the optimistic user
    // message appended in [send] has no server counterpart. Roll it back so local
    // history does not diverge from the server — a ghost message and an advanced
    // parentId that a later turn would thread beneath (adityas/ai/129 finding 3).
    // _pendingUserId is non-null only pre-accept, so this never removes a message
    // from an accepted turn (and _buffer is empty in that case).
    final pending = _pendingUserId;
    if (pending != null) {
      ref.read(conversationProvider.notifier).removeMessage(pending);
      _pendingUserId = null;
    }
    // Symmetric with [_lapse]: commit any partial (normally empty for a 402, which
    // fires before any delta).
    if (_buffer.isNotEmpty) {
      ref
          .read(conversationProvider.notifier)
          .appendAssistant(_buffer.toString());
    }
    _ceilinged = true;
    ref.invalidate(usageProvider);
    state = TurnCeiling(text: _buffer.toString(), usage: _usage);
  }

  /// Re-read the window headroom directly from the usage seam after a ceilinged
  /// [send], so the latch can self-heal once the window resets/renews — without a
  /// wall-clock poll and without trusting the possibly-stale cached
  /// [usageProvider] value (adityas/ai/129 findings 1 & 2). A settled read below
  /// [usageNearCeilingThreshold] is the only proof the window truly reset (a value
  /// still in the near-ceiling band, or a failed read, is not): release the latch,
  /// refresh the near notice to match, and drop back to idle so the surface
  /// unlocks. On failure the latch holds — an unproven window stays spent.
  Future<void> _recheckCeiling() async {
    final int pct;
    try {
      pct = await ref.read(usageClientProvider).fetchUsagePct();
    } catch (_) {
      return;
    }
    // The seam resolved after a dispose (panel torn down mid-recheck): the torn-
    // down ref must not be touched, and there is no surface left to unlock.
    if (_disposed) return;
    if (pct >= usageNearCeilingThreshold) return;
    _ceilinged = false;
    ref.invalidate(usageProvider);
    if (state is TurnCeiling) state = const TurnIdle();
  }

  /// Arm the mid-turn expiry timer at the current `access_until`. The delay is
  /// measured with the injected [Clock] so tests are deterministic; the [Timer]
  /// fires [_expire] at the boundary. No deadline (signed out / no entitlement)
  /// → no timer. An already-past deadline expires the turn at once.
  void _scheduleExpiry() {
    _cancelExpiryTimer();
    final deadline = ref.read(accessDeadlineProvider);
    if (deadline == null) return;
    final delay = deadline.difference(ref.read(clockProvider).now());
    if (delay <= Duration.zero) {
      _expire();
      return;
    }
    _expiryTimer = Timer(delay, _expire);
  }

  void _cancelExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void _resetTurn() {
    _closeSub();
    _throttle.cancel();
    _cancelExpiryTimer();
    _buffer.clear();
    _cursor = null;
    _usage = null;
    _reconnects = 0;
    _cancelling = false;
    _pendingUserId = null;
  }

  void _closeSub() {
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  bool get _isActive => switch (state) {
    TurnConnecting() || TurnStreaming() || TurnReconnecting() => true,
    TurnIdle() ||
    TurnDone() ||
    TurnCancelled() ||
    TurnError() ||
    TurnAccessLapsed() ||
    TurnCeiling() => false,
  };

  bool _isTerminal(ChatTurn turn) => switch (turn) {
    TurnDone() ||
    TurnCancelled() ||
    TurnError() ||
    TurnAccessLapsed() ||
    TurnCeiling() => true,
    TurnIdle() ||
    TurnConnecting() ||
    TurnStreaming() ||
    TurnReconnecting() => false,
  };
}
