import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'conversation.dart';
import 'delta_throttle.dart';
import 'entitlement.dart';
import 'turn_transport.dart';

/// The reactive core of the chat feature: the [ChatTurn] sealed state machine
/// and the notifier that drives it from an injected [TurnTransport].
///
/// ```
/// idle → connecting → streaming ⇄ reconnecting
///                        │  │
///                        │  ├→ cancelled   (client stop → server stop; still billed)
///                        │  ├→ error       (terminal-with-retry; carries the cursor)
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
class TurnDone extends ChatTurn {
  final String text;
  final TurnUsage usage;

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
  bool _cancelling = false;

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
        if (available == false) _expire();
      })
      ..onDispose(() {
        _closeSub();
        _throttle.cancel();
      });

    return const TurnIdle();
  }

  /// Send a user message, opening a new turn. No-op if a turn is already active
  /// (one turn at a time) or the message is blank.
  void send(String text) {
    if (_isActive) return;
    // UX gate; the backend is the authoritative entitlement check. Defense in
    // depth against opening a turn the server will refuse anyway.
    if (ref.read(chatAvailableProvider) != true) {
      state = const TurnError(
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
    state = const TurnConnecting();
    _subscribe(
      _transport.start(
        TurnRequest(text: message, parentMessageId: userMessage.id),
      ),
    );
  }

  /// Stop the turn. Maps to a server-side stop, not merely closing the client
  /// stream (or we keep paying). Non-refunding: a trailing usage event still
  /// settles billing on the resulting [TurnCancelled].
  Future<void> cancel() async {
    if (!_isActive) return;
    _cancelling = true;
    _throttle.cancel();
    // Reflect the stop immediately; the subscription stays open to receive the
    // server's trailing usage/done for the stopped turn.
    state = TurnCancelled(text: _buffer.toString(), usage: _usage);
    await _transport.cancel();
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
        _fail(message);
        return;
      case ToolStartEvent():
      case ToolEndEvent():
      case CitationEvent():
      case UnknownEvent():
        // v1 has no tool/citation UI, and an unrecognized event is ignored for
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
    if (_cancelling || _isTerminal(state)) return;
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
    _subscribe(_transport.resume(_cursor ?? ''));
  }

  /// The stream closed before a terminal event → the generation broke. Usage
  /// precedes done, so it typically never arrived — the turn is unbilled from
  /// the client's view and the ledger tolerates the gap.
  void _onStreamDone() {
    if (_cancelling || _isTerminal(state)) return;
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
    _closeSub();
    _throttle.cancel();
    if (_cancelling) {
      state = TurnCancelled(text: _buffer.toString(), usage: _usage);
    } else {
      state = TurnDone(
        text: _buffer.toString(),
        usage: _usage ?? const TurnUsage.zero(),
      );
    }
    if (_buffer.isNotEmpty) {
      ref
          .read(conversationProvider.notifier)
          .appendAssistant(_buffer.toString());
    }
  }

  void _fail(String message) {
    _closeSub();
    _throttle.cancel();
    state = TurnError(message: message, cursor: _cursor, usage: _usage);
  }

  /// Access lapsed mid-turn. Best-effort server stop so a lapsed turn does not
  /// keep generating on our budget; the server enforces entitlement
  /// authoritatively regardless.
  void _expire() {
    if (!_isActive) return;
    _closeSub();
    _throttle.cancel();
    unawaited(_transport.cancel());
    state = TurnError(
      message: 'Access expired during the turn.',
      cursor: _cursor,
      usage: _usage,
    );
  }

  void _resetTurn() {
    _closeSub();
    _throttle.cancel();
    _buffer.clear();
    _cursor = null;
    _usage = null;
    _reconnects = 0;
    _cancelling = false;
  }

  void _closeSub() {
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  bool get _isActive => switch (state) {
    TurnConnecting() || TurnStreaming() || TurnReconnecting() => true,
    TurnIdle() || TurnDone() || TurnCancelled() || TurnError() => false,
  };

  bool _isTerminal(ChatTurn turn) => switch (turn) {
    TurnDone() || TurnCancelled() || TurnError() => true,
    TurnIdle() ||
    TurnConnecting() ||
    TurnStreaming() ||
    TurnReconnecting() => false,
  };
}
