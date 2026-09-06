import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/state/auth.dart';
import 'package:explore/state/chat_turn.dart';
import 'package:explore/state/clock.dart';
import 'package:explore/state/conversation.dart';
import 'package:explore/state/delta_throttle.dart';
import 'package:explore/state/entitlement.dart';
import 'package:explore/state/overlay.dart';
import 'package:explore/state/turn_transport.dart';
import 'package:explore/ui/popup_state.dart';

/// A [TurnTransport] driven by the test: each `start`/`resume` hands back a
/// controller the test emits scripted events on, at the moment it chooses.
class _FakeTransport implements TurnTransport {
  final List<StreamController<TurnEvent>> _controllers = [];
  int starts = 0;
  int resumes = 0;
  int cancels = 0;
  String? lastResumeCursor;
  TurnRequest? lastRequest;

  StreamController<TurnEvent> get _current => _controllers.last;

  @override
  String? conversationId;

  @override
  Stream<TurnEvent> start(TurnRequest request) {
    starts++;
    lastRequest = request;
    final controller = StreamController<TurnEvent>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<TurnEvent> resume(String cursor) {
    resumes++;
    lastResumeCursor = cursor;
    final controller = StreamController<TurnEvent>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  int adopts = 0;
  int resets = 0;
  String? lastAdoptedId;

  @override
  void adoptConversation(String id) {
    adopts++;
    lastAdoptedId = id;
    conversationId = id;
  }

  @override
  void resetConversation() {
    resets++;
    conversationId = null;
  }

  void emit(TurnEvent event) => _current.add(event);

  /// Premature close: the stream ends without a terminal event (broken stream).
  Future<void> closeStream() => _current.close();

  /// Transient drop: the stream raises an error (→ reconnect).
  void dropStream(Object error) => _current.addError(error);
}

/// A transport whose [start] (and, after the first drop, [resume]) throws
/// synchronously — stream creation itself fails.
class _ThrowingTransport implements TurnTransport {
  @override
  String? get conversationId => null;

  @override
  Stream<TurnEvent> start(TurnRequest request) => throw StateError('no wire');

  @override
  Stream<TurnEvent> resume(String cursor) => throw StateError('no wire');

  @override
  Future<void> cancel() async {}

  @override
  void adoptConversation(String id) {}

  @override
  void resetConversation() {}
}

/// An advanceable [Clock] for deterministic expiry timing.
class _FakeClock implements Clock {
  DateTime _now;
  _FakeClock(this._now);

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

/// A controllable stand-in for [chatAvailableProvider], so a turn test can flip
/// entitlement mid-stream without wiring the whole auth/entitlement/clock graph
/// (that derivation is covered by entitlement_test.dart).
class _Gate extends Notifier<bool> {
  @override
  bool build() => true;

  void update(bool value) => state = value;
}

final _gateProvider = NotifierProvider<_Gate, bool>(_Gate.new);

const _stubUser = User(
  id: 'test-user',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

/// authProvider touches `Supabase.instance` (uninitialized headless), so the
/// conversation's auth dependency is stubbed with a fixed user.
class _StubAuth extends AuthNotifier {
  final User? _user;
  _StubAuth(this._user);

  @override
  User? build() => _user;
}

ProviderContainer _container(
  TurnTransport transport, {
  DateTime? deadline,
  Clock? clock,
}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _StubAuth(_stubUser)),
      turnTransportProvider.overrideWithValue(transport),
      deltaThrottleFactoryProvider.overrideWithValue(
        () => const ImmediateThrottle(),
      ),
      chatAvailableProvider.overrideWith((ref) => ref.watch(_gateProvider)),
      // No time-based deadline by default: the turn schedules no expiry timer,
      // so tests that flip the boolean gate stay unaffected. A time-expiry test
      // supplies an explicit deadline + advanceable clock.
      accessDeadlineProvider.overrideWithValue(deadline),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Drain queued microtasks/stream events so async deliveries settle.
Future<void> _pump([int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('happy path: connecting → streaming → done, usage billed', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hello');
    expect(container.read(chatTurnProvider), isA<TurnConnecting>());
    expect(transport.starts, 1);
    expect(transport.lastRequest?.text, 'hello');

    transport
      ..emit(const DeltaEvent('Hel', 'e1'))
      ..emit(const DeltaEvent('lo', 'e2'));
    await _pump();

    final streaming = container.read(chatTurnProvider);
    expect(streaming, isA<TurnStreaming>());
    expect((streaming as TurnStreaming).text, 'Hello');
    expect(streaming.cursor, 'e2');

    transport
      ..emit(
        const UsageEvent(TurnUsage(inputTokens: 10, outputTokens: 5), 'e3'),
      )
      ..emit(const DoneEvent('e4'));
    await _pump();

    final done = container.read(chatTurnProvider);
    expect(done, isA<TurnDone>());
    expect((done as TurnDone).text, 'Hello');
    expect(done.usage?.totalTokens, 15);

    // The completed reply is committed to the conversation (user then assistant).
    final convo = container.read(conversationProvider);
    expect(convo.messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(convo.messages.last.text, 'Hello');
    // Tree: the assistant reply threads beneath the user message.
    expect(convo.messages.last.parentId, convo.messages.first.id);
  });

  test('cancel: server-side stop, still billed (non-refunding)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');

    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();

    await notifier.cancel();
    expect(transport.cancels, 1);
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());

    // The server finalizes the stopped turn: a trailing usage event, then done.
    transport
      ..emit(const UsageEvent(TurnUsage(inputTokens: 3, outputTokens: 4), 'e2'))
      ..emit(const DoneEvent('e3'));
    await _pump();

    final cancelled = container.read(chatTurnProvider);
    expect(cancelled, isA<TurnCancelled>());
    expect((cancelled as TurnCancelled).usage?.totalTokens, 7);
    expect(cancelled.text, 'partial');
  });

  test('broken stream: closes before done → error, no usage', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.emit(const DeltaEvent('half', 'e1'));
    await _pump();
    await transport.closeStream(); // premature onDone, no usage/done
    await _pump();

    final errored = container.read(chatTurnProvider);
    expect(errored, isA<TurnError>());
    expect((errored as TurnError).usage, isNull);
    expect(errored.cursor, 'e1'); // carried for a retry
  });

  test('reconnect: transient drop resumes from the cursor', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.emit(const DeltaEvent('one ', 'e1'));
    await _pump();

    transport.dropStream(Exception('connection reset'));
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnReconnecting>());
    expect(transport.resumes, 1);
    expect(transport.lastResumeCursor, 'e1');

    // The resumed stream yields the rest; the buffer is preserved across the gap.
    transport
      ..emit(const DeltaEvent('two', 'e2'))
      ..emit(const UsageEvent(TurnUsage(inputTokens: 2, outputTokens: 2), 'e3'))
      ..emit(const DoneEvent('e4'));
    await _pump();

    final done = container.read(chatTurnProvider);
    expect(done, isA<TurnDone>());
    expect((done as TurnDone).text, 'one two');
  });

  test(
    'tool/citation/unknown events are ignored; cursor still advances',
    () async {
      final transport = _FakeTransport();
      final container = _container(transport);

      container.read(chatTurnProvider.notifier).send('hi');
      transport
        ..emit(const DeltaEvent('a', 'e1'))
        ..emit(const UnknownEvent('reasoning', 'e2'))
        ..emit(const ToolStartEvent('get_being', 'e3'))
        ..emit(const CitationEvent('being:ugrasena', 'e4'))
        ..emit(const DeltaEvent('b', 'e5'));
      await _pump();

      final streaming = container.read(chatTurnProvider);
      expect(streaming, isA<TurnStreaming>());
      // Ignored events add no text…
      expect((streaming as TurnStreaming).text, 'ab');
      // …but the cursor advanced past them.
      expect(streaming.cursor, 'e5');
    },
  );

  test('a show_being tool call opens the being overlay', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('who is my sun?');
    transport
      ..emit(const DeltaEvent('Looking… ', 'e1'))
      ..emit(
        const ToolStartEvent(
          'show_being',
          'e2',
          args: {'slug': 'varuna-rishi'},
        ),
      )
      ..emit(const DeltaEvent('here.', 'e3'));
    await _pump();

    final overlay = container.read(overlayControllerProvider);
    expect(overlay.top, isA<BeingFromName>());
    final being = (overlay.top! as BeingFromName).being;
    expect(being.sign, 4); // varuna
    expect(being.type, 'rishi');
    // The tool event drives the popup but is inert to the text buffer.
    expect(
      (container.read(chatTurnProvider) as TurnStreaming).text,
      'Looking… here.',
    );
  });

  test('knowledge tools never navigate; only show_being does', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('search the corpus');
    transport
      // A knowledge read of a being does NOT open the card — the model must
      // intentionally call show_being for that.
      ..emit(
        const ToolStartEvent('get_being', 'e1', args: {'slug': 'varuna-rishi'}),
      )
      ..emit(const ToolStartEvent('search', 'e2', args: {'query': 'love'}))
      // An unresolvable show_being slug degrades to a no-op.
      ..emit(
        const ToolStartEvent('show_being', 'e3', args: {'slug': 'nope-xyz'}),
      )
      ..emit(const DeltaEvent('done', 'e4'));
    await _pump();

    expect(container.read(overlayControllerProvider).isEmpty, isTrue);
  });

  test(
    'entitlement expiry mid-turn lapses the turn to a renew prompt',
    () async {
      final transport = _FakeTransport();
      final container = _container(transport);

      container.read(chatTurnProvider.notifier).send('hi');
      transport.emit(const DeltaEvent('mid', 'e1'));
      await _pump();
      expect(container.read(chatTurnProvider), isA<TurnStreaming>());

      // Access lapses while streaming (the derived gate flips false).
      container.read(_gateProvider.notifier).update(false);
      await _pump();

      final lapsed = container.read(chatTurnProvider);
      expect(lapsed, isA<TurnAccessLapsed>());
      expect((lapsed as TurnAccessLapsed).text, 'mid'); // partial preserved
      expect(transport.cancels, 1); // best-effort server stop
    },
  );

  test('a 403 on the opening POST lapses the turn — no retry', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hi');
    expect(container.read(chatTurnProvider), isA<TurnConnecting>());

    // The durable write route rejects with 403: the entitlement window closed.
    // Surfaces as a stream error carrying the status (as the real async* wire
    // propagates a thrown TurnTransportException to the subscription).
    transport.dropStream(
      const TurnTransportException('no access', statusCode: 403),
    );
    await _pump();

    final lapsed = container.read(chatTurnProvider);
    expect(lapsed, isA<TurnAccessLapsed>());
    expect(transport.resumes, 0); // a gate is terminal, never retried
    expect(transport.cancels, 1); // best-effort server stop
  });

  test('a non-gate status is transient → reconnects', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.emit(const DeltaEvent('one', 'e1'));
    await _pump();

    // A 500 (or any non-403/402/428) is treated as a transient drop, not a
    // deliberate gate — it still spends the reconnect budget.
    transport.dropStream(
      const TurnTransportException('server error', statusCode: 500),
    );
    await _pump();

    expect(container.read(chatTurnProvider), isA<TurnReconnecting>());
    expect(transport.resumes, 1);
  });

  test('send is refused when chat is unavailable', () {
    final transport = _FakeTransport();
    final container = _container(transport);
    container.read(_gateProvider.notifier).update(false);

    container.read(chatTurnProvider.notifier).send('hi');

    expect(container.read(chatTurnProvider), isA<TurnError>());
    expect(transport.starts, 0); // no turn opened
  });

  test('a second send is ignored while a turn is active', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('first');

    transport.emit(const DeltaEvent('x', 'e1'));
    await _pump();
    notifier.send('second');

    expect(transport.starts, 1); // the second send did not open a turn
    expect(transport.lastRequest?.text, 'first');
  });

  test(
    'send after cancel, before trailing usage, does not lose the billing',
    () async {
      final transport = _FakeTransport();
      final container = _container(transport);
      final notifier = container.read(chatTurnProvider.notifier)..send('hi');

      transport.emit(const DeltaEvent('partial', 'e1'));
      await _pump();
      await notifier.cancel();
      expect(container.read(chatTurnProvider), isA<TurnCancelled>());

      // The user immediately tries to send again while the stopped turn is still
      // settling (no trailing usage yet). It must be refused — a fresh turn here
      // would tear down the subscription and drop the (billable) usage.
      notifier.send('again');
      expect(transport.starts, 1); // no new turn opened
      expect(transport.resumes, 0);

      // The server's trailing usage still lands on the cancelled turn.
      transport.emit(
        const UsageEvent(TurnUsage(inputTokens: 3, outputTokens: 4), 'e2'),
      );
      await _pump();
      final settling = container.read(chatTurnProvider);
      expect((settling as TurnCancelled).usage?.totalTokens, 7);

      // Once the stopped turn settles (done), a new send is allowed again.
      transport.emit(const DoneEvent('e3'));
      await _pump();
      notifier.send('now ok');
      await _pump();
      expect(transport.starts, 2);
      expect(transport.lastRequest?.text, 'now ok');
    },
  );

  test('done without a usage event surfaces a billing gap, not zero', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.emit(const DeltaEvent('answer', 'e1'));
    await _pump();
    // Clean done, but the usage event was dropped/never sent.
    transport.emit(const DoneEvent('e2'));
    await _pump();

    final done = container.read(chatTurnProvider);
    expect(done, isA<TurnDone>());
    // A gap (null) — NOT TurnUsage.zero(), which would read as a free turn.
    expect((done as TurnDone).usage, isNull);
    expect(done.text, 'answer');
  });

  test('synchronous transport.start() throw ends the turn in error', () {
    final container = _container(_ThrowingTransport());

    // Must not let the exception escape send() and strand the turn in a live
    // TurnConnecting with no subscription — it ends terminally in TurnError.
    container.read(chatTurnProvider.notifier).send('hi');

    final errored = container.read(chatTurnProvider);
    expect(errored, isA<TurnError>());
    expect((errored as TurnError).message, contains('Failed to start'));

    // Terminal, not stranded-active: a follow-up send is accepted (opens a new
    // turn, which then also fails through the same throwing transport).
    container.read(chatTurnProvider.notifier).send('again');
    expect(container.read(chatTurnProvider), isA<TurnError>());
  });

  test('crossing access_until mid-turn fires expiry via the injected clock', () {
    fakeAsync((async) {
      final transport = _FakeTransport();
      final clock = _FakeClock(DateTime.utc(2026, 1, 1, 12, 0, 0));
      final deadline = clock.now().add(const Duration(minutes: 5));
      final container = _container(transport, deadline: deadline, clock: clock);

      container.read(chatTurnProvider.notifier).send('hi');
      transport.emit(const DeltaEvent('mid', 'e1'));
      async.flushMicrotasks();
      expect(container.read(chatTurnProvider), isA<TurnStreaming>());

      // Wall time crosses access_until with no other provider change — only the
      // scheduled timer can end the turn.
      clock.advance(const Duration(minutes: 5, seconds: 1));
      async.elapse(const Duration(minutes: 5, seconds: 1));

      final lapsed = container.read(chatTurnProvider);
      expect(lapsed, isA<TurnAccessLapsed>());
      expect(transport.cancels, 1); // best-effort server stop
    });
  });

  test('send composes a {chart · date} conversation title', () {
    final transport = _FakeTransport();
    final container = _container(
      transport,
      clock: _FakeClock(DateTime(2026, 9, 2)),
    );

    container.read(chatTurnProvider.notifier).send('hello');

    // No chart open in the headless container → the chart-less "Chat" label.
    expect(transport.lastRequest?.conversationTitle, 'Chat · Sep 2');
  });

  test(
    'startNewConversation stops an active turn and clears to idle',
    () async {
      final transport = _FakeTransport();
      final container = _container(transport);
      final notifier = container.read(chatTurnProvider.notifier)..send('hello');

      transport.emit(const DeltaEvent('partial', 'e1'));
      await _pump();
      expect(container.read(chatTurnProvider), isA<TurnStreaming>());

      notifier.startNewConversation();

      expect(container.read(chatTurnProvider), isA<TurnIdle>());
      expect(transport.cancels, 1); // in-flight turn stopped server-side
      expect(transport.resets, 1); // next turn mints a fresh conversation
      expect(container.read(conversationProvider).messages, isEmpty);
    },
  );

  test('startNewConversation with no active turn resets without a stop', () {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).startNewConversation();

    expect(transport.cancels, 0);
    expect(transport.resets, 1);
    expect(container.read(chatTurnProvider), isA<TurnIdle>());
  });

  test('resumeConversation adopts the server id and loads the transcript', () {
    final transport = _FakeTransport();
    final container = _container(transport);

    container
        .read(chatTurnProvider.notifier)
        .resumeConversation('server-1', const [
          (role: MessageRole.user, text: 'earlier question'),
          (role: MessageRole.assistant, text: 'earlier answer'),
        ]);

    expect(transport.adopts, 1);
    expect(transport.lastAdoptedId, 'server-1');
    expect(container.read(chatTurnProvider), isA<TurnIdle>());
    final convo = container.read(conversationProvider);
    expect(convo.id, 'server-1');
    expect(convo.messages, hasLength(2));
    expect(convo.messages.first.text, 'earlier question');
  });

  test('startNewConversation clears the active id the delete-active check reads '
      '(adityas/ai/91)', () {
    final transport = _FakeTransport();
    final container = _container(transport);

    // Adopt a thread → the transport now reports it as the active id, which is
    // exactly what the picker's delete-active comparison reads.
    final notifier = container.read(chatTurnProvider.notifier)
      ..resumeConversation('server-7', const []);
    expect(transport.conversationId, 'server-7');

    // Deleting that active thread routes through startNewConversation, which
    // must reset the transport (id → null) and clear the panel.
    notifier.startNewConversation();
    expect(transport.conversationId, isNull);
    expect(container.read(conversationProvider).messages, isEmpty);
    expect(container.read(chatTurnProvider), isA<TurnIdle>());
  });
}
