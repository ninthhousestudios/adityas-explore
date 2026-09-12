import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/api/chart_service.dart';
import 'package:explore/state/auth.dart';
import 'package:explore/state/chat_turn.dart';
import 'package:explore/state/clock.dart';
import 'package:explore/state/consent.dart';
import 'package:explore/state/conversation.dart';
import 'package:explore/state/delta_throttle.dart';
import 'package:explore/state/entitlement.dart';
import 'package:explore/state/overlay.dart';
import 'package:explore/state/turn_transport.dart';
import 'package:explore/state/usage.dart';
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

  /// Whether [cancel] reports the server-side stop as in effect. Set false to
  /// drive a stop the server did not acknowledge (adityas/ai/141).
  bool cancelSucceeds = true;

  /// When set, [cancel] blocks on this until the test completes it — lets a test
  /// race stream events against an unresolved cancel POST (adityas/ai/146).
  Completer<void>? cancelGate;

  StreamController<TurnEvent> get _current => _controllers.last;

  @override
  String? conversationId;

  @override
  Stream<TurnEvent> start(TurnRequest request) {
    starts++;
    lastRequest = request;
    // The real transport mints a session-new conversation lazily on the first
    // turn (SseTurnTransport._ensureConversation) and reuses it thereafter.
    // Mirror that so [ChatTurnNotifier._reflectConversationMint] sees an id
    // (adityas/ai/198 finding B). An adopted/resumed id (set via
    // [adoptConversation]) is not clobbered.
    conversationId ??= 'minted-$starts';
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
  Future<bool> cancel() async {
    cancels++;
    final gate = cancelGate;
    if (gate != null) await gate.future;
    return cancelSucceeds;
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
  Future<bool> cancel() async => true;

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

/// A scripted [UsageClient]: hands back a settable `used_pct` so a test can drive
/// the near-ceiling / at-ceiling self-heal without the real network. Counts calls
/// so a test can assert the turn refetched usage on settle.
class _FakeUsage implements UsageClient {
  int pct;
  int fetches = 0;
  bool fail = false;
  _FakeUsage([this.pct = 0]);

  @override
  Future<int> fetchUsagePct() async {
    fetches++;
    if (fail) throw Exception('usage endpoint down');
    return pct;
  }
}

/// A scripted [ConsentClient]: hands back a settable `needsConsent` and flips it
/// false on record, so a test can drive the re-consent gate and its self-heal
/// without the network. Counts calls so a test can assert the seam refetched.
class _FakeConsent implements ConsentClient {
  bool needsConsent;
  int fetches = 0;
  int records = 0;
  _FakeConsent({this.needsConsent = false});

  @override
  Future<ChatConsent> fetchConsent() async {
    fetches++;
    return ChatConsent(
      currentVersion: 'chat-terms-v1',
      acceptedVersion: needsConsent ? 'chat-terms-v0' : 'chat-terms-v1',
      needsConsent: needsConsent,
    );
  }

  @override
  Future<void> recordConsent(String version) async {
    records++;
    needsConsent = false;
  }
}

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
  UsageClient? usageClient,
  ConsentClient? consentClient,
  Future<bool> Function()? archiveCheck,
}) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _StubAuth(_stubUser)),
      turnTransportProvider.overrideWithValue(transport),
      deltaThrottleFactoryProvider.overrideWithValue(
        () => const ImmediateThrottle(),
      ),
      chatAvailableProvider.overrideWith((ref) => ref.watch(_gateProvider)),
      // The ceiling recheck reads the usage seam directly; keep it off the
      // network with a scripted client (plenty of headroom by default).
      usageClientProvider.overrideWithValue(usageClient ?? _FakeUsage()),
      // The turn notifier's build() listens consentRequiredProvider, which builds
      // consentProvider eagerly — keep that off the network with a scripted client
      // (consent current by default, so the latch stays clear).
      consentClientProvider.overrideWithValue(consentClient ?? _FakeConsent()),
      // No time-based deadline by default: the turn schedules no expiry timer,
      // so tests that flip the boolean gate stay unaffected. A time-expiry test
      // supplies an explicit deadline + advanceable clock.
      accessDeadlineProvider.overrideWithValue(deadline),
      // Treat entitlement as resolved so a gate-off, no-deadline reading is a
      // confirmed [ChatAccess.none] (not [ChatAccess.pending]) — and the real
      // entitlement fetch stays out of the graph (adityas/ai/194).
      entitlementSettledProvider.overrideWithValue(true),
      if (clock != null) clockProvider.overrideWithValue(clock),
      if (archiveCheck != null)
        hasConversationsProvider.overrideWith(
          (ref) async => (userId: _stubUser.id, has: await archiveCheck()),
        ),
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

  /// Wire a container whose archive check counts each run, kept warm as the
  /// always-mounted AccountButton keeps it in-app so an invalidate re-runs it.
  ({
    ProviderContainer container,
    _FakeTransport transport,
    int Function() checks,
  })
  archiveCounting() {
    var archiveChecks = 0;
    final transport = _FakeTransport();
    final container = _container(
      transport,
      // The archive reads empty (a stale pre-mint cache); count each check.
      archiveCheck: () async {
        archiveChecks++;
        return false;
      },
    )..listen(hasConversationsProvider, (_, _) {});
    return (
      container: container,
      transport: transport,
      checks: () => archiveChecks,
    );
  }

  test('a completed first turn refreshes the archive signal so a stale '
      'pre-mint `false` cannot survive to a later lapse (adityas/42)', () async {
    final (:container, :transport, :checks) = archiveCounting();
    await _pump();
    expect(checks(), 1); // initial check

    // One full turn to completion mints the conversation server-side.
    container.read(chatTurnProvider.notifier).send('hello');
    transport
      ..emit(const DeltaEvent('hi', 'e1'))
      ..emit(const DoneEvent('e2'));
    await _pump();

    // Accepting the turn refreshed the archive signal: the stale `false` is
    // re-fetched, so a later New Chat (clearing the transcript) + a 403 reads the
    // fresh archive and lands on renew, not the never-entitled buy stub.
    expect(checks(), 2);
  });

  test('a cancelled first turn still refreshes the archive signal — the '
      'conversation was minted even though it never completed (adityas/ai/198 '
      'finding B)', () async {
    final (:container, :transport, :checks) = archiveCounting();
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();
    expect(checks(), 2); // accepted turn already reflected the mint

    // Cancel, then the server finalizes the stop (error → usage → done).
    await notifier.cancel();
    transport
      ..emit(const ErrorEvent('generation was cancelled', 'e2'))
      ..emit(const UsageEvent(TurnUsage(inputTokens: 1, outputTokens: 1), 'e3'))
      ..emit(const DoneEvent('e4'));
    await _pump();

    // Guarded per conversation: the trailing events don't re-check.
    expect(checks(), 2);
  });

  test('a first turn that completes with no deltas still refreshes the archive '
      'signal (adityas/ai/198 finding B)', () async {
    final (:container, :transport, :checks) = archiveCounting();
    container.read(chatTurnProvider.notifier).send('hi');
    // done arrives with no preceding delta — an empty conversation, but minted.
    transport.emit(const DoneEvent('e1'));
    await _pump();

    expect(container.read(chatTurnProvider), isA<TurnDone>());
    expect(checks(), 2);
  });

  test(
    'a stream error that terminates a first turn still refreshes the archive '
    'signal — the conversation was minted before the turn failed '
    '(adityas/ai/198 finding B)',
    () async {
      final (:container, :transport, :checks) = archiveCounting();
      container.read(chatTurnProvider.notifier).send('hi');
      // A 403 on the turn route: minted conversation, then a terminal gate. No
      // event ever arrived, so the mint is reflected from _onStreamError.
      transport.dropStream(
        const TurnTransportException('access lapsed', statusCode: 403),
      );
      await _pump();

      expect(container.read(chatTurnProvider), isA<TurnAccessLapsed>());
      expect(checks(), 2);
    },
  );

  test('a multi-turn conversation refreshes the archive signal once, not per '
      'turn (adityas/ai/198 finding B)', () async {
    final (:container, :transport, :checks) = archiveCounting();
    final notifier = container.read(chatTurnProvider.notifier)..send('one');
    transport
      ..emit(const DeltaEvent('a', 'e1'))
      ..emit(const DoneEvent('e2'));
    await _pump();
    expect(checks(), 2);

    // A second turn appends to the same (already-reflected) conversation.
    notifier.send('two');
    transport
      ..emit(const DeltaEvent('b', 'e3'))
      ..emit(const DoneEvent('e4'));
    await _pump();
    expect(checks(), 2);
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

  test('cancel: the full terminal sequence error → usage → done keeps the '
      'stream open and settles the trailing usage (adityas/ai/140)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');

    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();

    await notifier.cancel();
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());

    // The backend delivers the stop as error → usage → done (the LEADING error
    // is "generation was cancelled"). The notifier must treat that error as an
    // intermediate marker, NOT tear the subscription down on it, so the trailing
    // usage still settles onto the cancelled turn.
    transport.emit(const ErrorEvent('generation was cancelled', 'e2'));
    await _pump();
    // Still cancelled after the error — it does not un-cancel into TurnError.
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());

    transport
      ..emit(const UsageEvent(TurnUsage(inputTokens: 3, outputTokens: 4), 'e3'))
      ..emit(const DoneEvent('e4'));
    await _pump();

    final cancelled = container.read(chatTurnProvider);
    expect(cancelled, isA<TurnCancelled>());
    // The usage that arrived AFTER the error is what would be dropped if the
    // error tore the stream down early.
    expect((cancelled as TurnCancelled).usage?.totalTokens, 7);
    expect(cancelled.text, 'partial');
  });

  test('a stop the server does not acknowledge reverts to the live stream '
      'rather than asserting cancelled (adityas/ai/141)', () async {
    final transport = _FakeTransport()..cancelSucceeds = false;
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');

    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();

    await notifier.cancel();
    // The stop did not take: the SSE stream is still open and delivering, so the
    // turn must NOT freeze on a false "cancelled" — it reverts to streaming.
    final reverted = container.read(chatTurnProvider);
    expect(reverted, isA<TurnStreaming>());
    expect((reverted as TurnStreaming).text, 'partial');
    expect(transport.cancels, 1);
    // The optimistically-committed partial was un-committed — only the user
    // message remains, so the eventual done appends the full reply exactly once.
    expect(container.read(conversationProvider).messages.map((m) => m.role), [
      MessageRole.user,
    ]);

    // The reply keeps streaming and completes normally.
    transport
      ..emit(const DeltaEvent(' answer', 'e2'))
      ..emit(const UsageEvent(TurnUsage(inputTokens: 1, outputTokens: 2), 'e3'))
      ..emit(const DoneEvent('e4'));
    await _pump();

    final done = container.read(chatTurnProvider);
    expect(done, isA<TurnDone>());
    expect((done as TurnDone).text, 'partial answer');
    final convo = container.read(conversationProvider);
    expect(convo.messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(convo.messages.last.text, 'partial answer'); // one reply, in full
  });

  test('after a stop that did not take, Stop can be retried and then settles '
      '(adityas/ai/141)', () async {
    final transport = _FakeTransport()..cancelSucceeds = false;
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();

    await notifier.cancel(); // refused → reverts to streaming
    expect(container.read(chatTurnProvider), isA<TurnStreaming>());
    expect(transport.cancels, 1);

    // The retried Stop is acknowledged this time — the turn cancels for real.
    transport.cancelSucceeds = true;
    await notifier.cancel();
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());
    expect(transport.cancels, 2);
    // The partial committed once on the acknowledged stop, not duplicated.
    final convo = container.read(conversationProvider);
    expect(convo.messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(convo.messages.last.text, 'partial');
  });

  test('a failed cancel racing a trailing done commits the full reply, not a '
      'truncated cancelled (adityas/ai/146)', () async {
    final gate = Completer<void>();
    final transport = _FakeTransport()
      ..cancelSucceeds = false
      ..cancelGate = gate;
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');

    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();

    // Stop pressed; the cancel POST is in flight (unresolved).
    final cancelling = notifier.cancel();
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());

    // Before the POST resolves, the generation the stop did NOT reach runs to
    // completion: more text, trailing usage, then done.
    transport
      ..emit(const DeltaEvent(' answer', 'e2'))
      ..emit(const UsageEvent(TurnUsage(inputTokens: 1, outputTokens: 2), 'e3'))
      ..emit(const DoneEvent('e4'));
    await _pump();

    // Now the failed cancel resolves. With the stream already completed, it must
    // reconcile as a normal done — not freeze a truncated "cancelled".
    gate.complete();
    await cancelling;
    await _pump();

    final done = container.read(chatTurnProvider);
    expect(done, isA<TurnDone>());
    expect((done as TurnDone).text, 'partial answer');
    final convo = container.read(conversationProvider);
    expect(convo.messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(convo.messages.last.text, 'partial answer'); // full reply, once
  });

  test('New Chat during the settling window re-issues the stop rather than '
      'orphaning the generation (adityas/ai/146)', () async {
    final gate = Completer<void>();
    final transport = _FakeTransport()..cancelGate = gate;
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();

    final cancelling = notifier.cancel(); // POST in flight → settling window
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());
    expect(transport.cancels, 1);

    // New Chat while still settling must re-issue the stop, not abandon a turn
    // whose original cancel could still fail and keep generating.
    notifier.startNewConversation();
    gate.complete();
    await cancelling;
    await _pump();

    expect(container.read(chatTurnProvider), isA<TurnIdle>());
    expect(transport.cancels, 2); // re-stopped on rotation
    expect(transport.resets, 1);
  });

  test('a Stop pressed while still connecting is latched (in effect), not '
      'treated as a failed cancel (adityas/ai/141 + ai/140)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    expect(container.read(chatTurnProvider), isA<TurnConnecting>());

    // The fake reports connecting-time cancel as in effect (latched), so the
    // notifier keeps the cancelled state and the stream settles it — it must not
    // revert to a phantom stream that never opened.
    await notifier.cancel();
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());

    transport
      ..emit(const UsageEvent(TurnUsage(inputTokens: 0, outputTokens: 0), 'e1'))
      ..emit(const DoneEvent('e2'));
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());
  });

  test('the post-Stop settling window is observable via isSettling and refuses '
      'a send until it clears (adityas/ai/142)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();

    expect(notifier.isSettling, isFalse);
    await notifier.cancel();
    // Cancelled, but still settling: the subscription is open for trailing usage.
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());
    expect(notifier.isSettling, isTrue);

    // A send during the settling window is REFUSED (returns false) and opens no
    // turn — the composer keeps the typed text rather than discarding it.
    expect(notifier.send('while settling'), isFalse);
    expect(transport.starts, 1);

    // The server settles the stopped turn; the latch clears with a notification.
    transport
      ..emit(const UsageEvent(TurnUsage(inputTokens: 1, outputTokens: 1), 'e2'))
      ..emit(const DoneEvent('e3'));
    await _pump();
    expect(notifier.isSettling, isFalse);

    // A send is now accepted (returns true) and opens a fresh turn.
    expect(notifier.send('now'), isTrue);
    expect(transport.starts, 2);
  });

  test('isSettling clears (with a notification) even when the stopped stream '
      'just breaks (adityas/ai/142)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    var notifications = 0;
    container.listen(chatTurnProvider, (_, _) => notifications++);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();
    await notifier.cancel();
    expect(notifier.isSettling, isTrue);

    final before = notifications;
    // The stopped turn's stream breaks with no trailing usage/done.
    await transport.closeStream();
    await _pump();

    expect(notifier.isSettling, isFalse);
    // The clear fired a state notification so a composer watching the provider
    // re-reads isSettling and drops the Stop affordance.
    expect(notifications, greaterThan(before));
  });

  test('send reports acceptance so refused text can be preserved '
      '(adityas/ai/142)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier);

    expect(notifier.send('   '), isFalse); // blank refused
    expect(notifier.send('hello'), isTrue); // accepted → opens a turn
    transport.emit(const DeltaEvent('x', 'e1'));
    await _pump();
    expect(notifier.send('second'), isFalse); // a second turn is refused
    expect(transport.starts, 1);
  });

  test('a cancelled turn commits its partial reply to the conversation, once '
      '(adityas/ai/126)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');

    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();
    await notifier.cancel();

    expect(container.read(chatTurnProvider), isA<TurnCancelled>());
    // The partial the user was reading is preserved as an assistant message
    // immediately on stop — not deferred to a trailing done that may not come.
    final convo = container.read(conversationProvider);
    expect(convo.messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(convo.messages.last.text, 'partial');

    // The server's trailing usage/done settles billing but must NOT append a
    // duplicate assistant message.
    transport
      ..emit(const UsageEvent(TurnUsage(inputTokens: 1, outputTokens: 1), 'e2'))
      ..emit(const DoneEvent('e3'));
    await _pump();
    expect(container.read(conversationProvider).messages, hasLength(2));
  });

  test('a cancelled partial survives a broken stream that never delivers done '
      '(adityas/ai/126)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');

    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();
    await notifier.cancel();

    // The stopped turn's stream breaks before any trailing done arrives.
    await transport.closeStream();
    await _pump();

    final convo = container.read(conversationProvider);
    expect(convo.messages.last.text, 'partial'); // not lost
    expect(convo.messages, hasLength(2));
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

  test('a mid-stream lapse persists the partial reply to the conversation '
      '(adityas/ai/123 finding 1)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.emit(const DeltaEvent('partial answer', 'e1'));
    await _pump();

    // Access lapses while the reply is still streaming.
    container.read(_gateProvider.notifier).update(false);
    await _pump();

    expect(container.read(chatTurnProvider), isA<TurnAccessLapsed>());
    // The partial the user was watching is committed as an assistant message
    // (like a completed turn) rather than dropped when the renew prompt
    // replaces the streaming bubble.
    final convo = container.read(conversationProvider);
    expect(convo.messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(convo.messages.last.text, 'partial answer');
  });

  test('after a 403 the resend is hard-refused even while the gate still reads '
      'available (adityas/ai/123 finding 2)', () async {
    final transport = _FakeTransport();
    // The stale window right after a 403: the gate still reads available and a
    // future deadline is cached, before the entitlement refetch resolves.
    final container = _container(transport, deadline: DateTime.utc(2999));

    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    transport.dropStream(
      const TurnTransportException('no access', statusCode: 403),
    );
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnAccessLapsed>());

    // chatAccess would still derive `available` here — only the authoritative
    // latch refuses the resend, so no second turn opens and no duplicate user
    // message / duplicate 403 is produced.
    expect(container.read(chatAvailableProvider), isTrue);
    notifier.send('again');
    expect(container.read(chatTurnProvider), isA<TurnAccessLapsed>());
    expect(transport.starts, 1);
  });

  test('a fired expiry timer re-arms when the deadline is still ahead '
      '(mid-turn renewal, adityas/ai/123 finding 4)', () {
    fakeAsync((async) {
      final transport = _FakeTransport();
      final clock = _FakeClock(DateTime.utc(2026, 1, 1, 12));
      final deadline = clock.now().add(const Duration(minutes: 5));
      final container = _container(transport, deadline: deadline, clock: clock);

      container.read(chatTurnProvider.notifier).send('hi');
      transport.emit(const DeltaEvent('mid', 'e1'));

      // The timer fires, but the injected clock has NOT crossed the deadline
      // (a mid-turn renewal effectively pushed the boundary ahead). The
      // re-check must re-arm, not lapse.
      async
        ..flushMicrotasks()
        ..elapse(const Duration(minutes: 5, seconds: 1));

      expect(container.read(chatTurnProvider), isA<TurnStreaming>());
      expect(transport.cancels, 0);
    });
  });

  test(
    'a 402 on the opening POST hits the ceiling — no retry (ai/100)',
    () async {
      final transport = _FakeTransport();
      final container = _container(transport);

      container.read(chatTurnProvider.notifier).send('hi');
      expect(container.read(chatTurnProvider), isA<TurnConnecting>());

      // The window budget is spent: the POST is refused with 402, surfaced as a
      // status-carrying stream error (as the real async* wire propagates it).
      transport.dropStream(
        const TurnTransportException('limit reached', statusCode: 402),
      );
      await _pump();

      expect(container.read(chatTurnProvider), isA<TurnCeiling>());
      expect(transport.resumes, 0); // a gate is terminal, never retried
      expect(transport.cancels, 1); // best-effort server stop
    },
  );

  test(
    'after a 402 the resend is hard-refused into the at-ceiling notice',
    () async {
      final transport = _FakeTransport();
      // Access stays live (a valid window); only the usage budget is exhausted, so
      // the near-ceiling client reads 100 and never self-heals the latch here.
      final container = _container(transport, usageClient: _FakeUsage(100));

      final notifier = container.read(chatTurnProvider.notifier)..send('hi');
      transport.dropStream(
        const TurnTransportException('limit reached', statusCode: 402),
      );
      await _pump();
      expect(container.read(chatTurnProvider), isA<TurnCeiling>());

      // The gate reads available (access is fine), yet the ceiling latch refuses
      // the resend — no second turn opens, no duplicate user message.
      expect(container.read(chatAvailableProvider), isTrue);
      notifier.send('again');
      expect(container.read(chatTurnProvider), isA<TurnCeiling>());
      expect(transport.starts, 1);
    },
  );

  test('a fresh usage read showing headroom self-heals the ceiling latch — no '
      'manual invalidate, panel stays mounted (adityas/ai/129 finding 1)', () async {
    final transport = _FakeTransport();
    final usage = _FakeUsage(100);
    final container = _container(transport, usageClient: usage);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.dropStream(
      const TurnTransportException('limit reached', statusCode: 402),
    );
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnCeiling>());

    // The window resets server-side (usage now reports headroom). Nothing polls
    // and NOTHING manually invalidates the provider — the ceilinged send itself
    // re-reads the seam directly, proves headroom, releases the latch, and drops
    // the surface back to idle. (The prior implementation could only recover via
    // a manual `container.invalidate(usageProvider)`, which production never
    // does; that is exactly the stuck-lockout this covers.)
    usage.pct = 0;
    container
        .read(chatTurnProvider.notifier)
        .send('again'); // refused; rechecks
    expect(container.read(chatTurnProvider), isA<TurnCeiling>());
    expect(transport.starts, 1); // that send opened no turn
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnIdle>()); // latch healed
    expect(usage.fetches, greaterThan(0));

    // With the latch released, a send now opens a fresh turn.
    container.read(chatTurnProvider.notifier).send('once more');
    expect(container.read(chatTurnProvider), isA<TurnConnecting>());
    expect(transport.starts, 2);
  });

  test('the ceiling latch holds on a stale near-band value and on a failed usage '
      'read (adityas/ai/129 finding 2)', () async {
    final transport = _FakeTransport();
    // The last successful usage read is 90 — still inside the near-ceiling band
    // [80,100), NOT proof the window reset.
    final usage = _FakeUsage(90);
    final container = _container(transport, usageClient: usage);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.dropStream(
      const TurnTransportException('limit reached', statusCode: 402),
    );
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnCeiling>());

    // A resend re-reads headroom directly. 90 is still near-ceiling, so the
    // latch must NOT clear — clearing it would let the turn re-hit the 402.
    container.read(chatTurnProvider.notifier).send('again');
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnCeiling>());
    expect(transport.starts, 1);

    // The usage endpoint then fails outright: a failed read is not proof of a
    // reset either, so the latch still holds.
    usage.fail = true;
    container.read(chatTurnProvider.notifier).send('still again');
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnCeiling>());
    expect(transport.starts, 1);
  });

  test(
    'a pre-accept 402 leaves conversation history unchanged — no ghost user '
    'message, and blocked resends do not accumulate (adityas/ai/129 finding 3)',
    () async {
      final transport = _FakeTransport();
      final container = _container(transport, usageClient: _FakeUsage(100));

      container.read(chatTurnProvider.notifier).send('hi');
      // The optimistic user message shows while the POST is in flight…
      expect(container.read(conversationProvider).messages, hasLength(1));

      // …but the POST is refused pre-accept with 402 (no turn spawned), so it is
      // rolled back: no ghost message, no advanced parent chain.
      transport.dropStream(
        const TurnTransportException('limit reached', statusCode: 402),
      );
      await _pump();
      expect(container.read(chatTurnProvider), isA<TurnCeiling>());
      expect(container.read(conversationProvider).messages, isEmpty);

      // A ceiling-blocked resend is refused before any append, so history stays
      // empty rather than accumulating dead user messages.
      container.read(chatTurnProvider.notifier).send('again');
      await _pump();
      expect(container.read(conversationProvider).messages, isEmpty);
    },
  );

  test(
    'a 428 on the opening POST requires re-consent — no retry (ai/98)',
    () async {
      final transport = _FakeTransport();
      final container = _container(
        transport,
        consentClient: _FakeConsent(needsConsent: true),
      );

      container.read(chatTurnProvider.notifier).send('hi');
      expect(container.read(chatTurnProvider), isA<TurnConnecting>());

      // Consent went stale: the write route rejects with 428, surfaced as a
      // status-carrying stream error (as the real async* wire propagates it).
      transport.dropStream(
        const TurnTransportException('consent required', statusCode: 428),
      );
      await _pump();

      expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());
      expect(transport.resumes, 0); // a gate is terminal, never retried
      expect(transport.cancels, 1); // best-effort server stop
    },
  );

  test(
    'after a 428 the resend is hard-refused into the re-consent gate',
    () async {
      final transport = _FakeTransport();
      final container = _container(
        transport,
        consentClient: _FakeConsent(needsConsent: true),
      );

      final notifier = container.read(chatTurnProvider.notifier)..send('hi');
      transport.dropStream(
        const TurnTransportException('consent required', statusCode: 428),
      );
      await _pump();
      expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());

      // Access is fine (a valid window) yet the consent latch refuses the resend —
      // no second turn opens, no duplicate user message.
      expect(container.read(chatAvailableProvider), isTrue);
      notifier.send('again');
      expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());
      expect(transport.starts, 1);
    },
  );

  test('a pre-accept 428 leaves conversation history unchanged — no ghost user '
      'message (adityas/ai/98)', () async {
    final transport = _FakeTransport();
    final container = _container(
      transport,
      consentClient: _FakeConsent(needsConsent: true),
    );

    container.read(chatTurnProvider.notifier).send('hi');
    // The optimistic user message shows while the POST is in flight…
    expect(container.read(conversationProvider).messages, hasLength(1));

    // …but the POST is refused pre-accept with 428 (no turn spawned), so it is
    // rolled back: no ghost message, no advanced parent chain.
    transport.dropStream(
      const TurnTransportException('consent required', statusCode: 428),
    );
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());
    expect(container.read(conversationProvider).messages, isEmpty);
  });

  test('recording consent self-heals the latch — the next send opens a turn '
      '(adityas/ai/98)', () async {
    final transport = _FakeTransport();
    final consent = _FakeConsent(needsConsent: true);
    // Emulate the mounted panel, which continuously watches the consent seam —
    // that persistent listener is what keeps the (autoDispose) provider mounted so
    // an invalidate's refetch resolves rather than stalling half-loaded.
    final container = _container(transport, consentClient: consent)
      ..listen(consentRequiredProvider, (_, _) {});

    container.read(chatTurnProvider.notifier).send('hi');
    transport.dropStream(
      const TurnTransportException('consent required', statusCode: 428),
    );
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());

    // The user agrees: the record flips needs_consent false and the seam refetch
    // clears the latch, dropping the surface back to idle.
    await container.read(consentProvider.notifier).accept();
    await _pump();
    expect(consent.records, 1);
    expect(container.read(consentRequiredProvider), isFalse);
    expect(container.read(chatTurnProvider), isA<TurnIdle>());

    // With the latch released, a send now opens a fresh turn.
    container.read(chatTurnProvider.notifier).send('again');
    expect(container.read(chatTurnProvider), isA<TurnConnecting>());
    expect(transport.starts, 2);
  });

  test(
    'a proactive GET needs_consent=true latches the gate and refuses a send — '
    'the ChatPill bypass, before any 428 (adityas/ai/135)',
    () async {
      final transport = _FakeTransport();
      // No 428 in this test: the ONLY consent signal is the proactive
      // GET /v1/ai/consent reporting a stale version.
      final container = _container(
        transport,
        consentClient: _FakeConsent(needsConsent: true),
      );

      // Build the notifier and let the proactive read resolve. Its consent
      // listener latches the requirement and surfaces the gate from idle.
      final notifier = container.read(chatTurnProvider.notifier);
      await _pump();
      expect(container.read(consentRequiredProvider), isTrue);
      expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());

      // The ChatPill now reads the gate proactively and shows a look-alike (not
      // a live composer) when consent-gated, so it no longer sends into this
      // state. But send() stays the defense-in-depth backstop for the window
      // where the proactive GET is still loading (fail-open) and a 428 lands:
      // without the latch this opened a doomed turn; now it must refuse without
      // touching the transport.
      notifier.send('hi');
      expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());
      expect(transport.starts, 0); // no doomed write left the client
    },
  );

  test('a 428 arriving during cancellation surfaces re-consent instead of being '
      'swallowed by the stop latch (adityas/ai/135)', () async {
    final transport = _FakeTransport();
    // Consent is currently fine (no proactive gate). The ONLY consent signal is
    // the 428 that races the cancellation — so a pass proves it was not eaten by
    // the `_cancelling` early-return that used to precede the status check.
    final container = _container(transport);

    final notifier = container.read(chatTurnProvider.notifier)..send('hi');
    expect(container.read(chatTurnProvider), isA<TurnConnecting>());

    // Stop the turn while the opening POST is still in flight.
    await notifier.cancel();
    expect(container.read(chatTurnProvider), isA<TurnCancelled>());

    // That in-flight write then returns 428 (consent went stale mid-request).
    transport.dropStream(
      const TurnTransportException('consent required', statusCode: 428),
    );
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());

    // The latch holds: the next send is refused, not a second doomed write.
    notifier.send('again');
    expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());
    expect(transport.starts, 1);
  });

  test('a gate racing a cancel does not double-commit the partial reply '
      '(adityas/ai/136)', () async {
    final transport = _FakeTransport();
    final container = _container(transport);
    final notifier = container.read(chatTurnProvider.notifier)..send('hi');

    // A partial streamed, then the user stopped the turn — cancel commits that
    // partial once.
    transport.emit(const DeltaEvent('partial', 'e1'));
    await _pump();
    await notifier.cancel();
    expect(container.read(conversationProvider).messages, hasLength(2));

    // The write route then rejects with 428 (the future-armed path: a gate
    // status reaching the notifier after deltas + a cancel — the CNS-4 reorder
    // now routes it to the consent gate instead of swallowing it). The partial
    // must NOT be appended a second time.
    transport.dropStream(
      const TurnTransportException('consent required', statusCode: 428),
    );
    await _pump();

    expect(container.read(chatTurnProvider), isA<TurnConsentRequired>());
    final convo = container.read(conversationProvider);
    expect(convo.messages, hasLength(2)); // user + one assistant 'partial'
    expect(convo.messages.last.text, 'partial');
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

  test('send is refused (never-entitled) with a generic error', () {
    final transport = _FakeTransport();
    // No deadline → chatAccess is `none` (never entitled / signed out).
    final container = _container(transport);
    container.read(_gateProvider.notifier).update(false);

    container.read(chatTurnProvider.notifier).send('hi');

    expect(container.read(chatTurnProvider), isA<TurnError>());
    expect(transport.starts, 0); // no turn opened
  });

  test('send while lapsed refuses into the renew prompt', () {
    final transport = _FakeTransport();
    // A non-null (past) deadline while unavailable → chatAccess is `lapsed`.
    final container = _container(transport, deadline: DateTime.utc(2000));
    container.read(_gateProvider.notifier).update(false);

    container.read(chatTurnProvider.notifier).send('hi');

    // The renew prompt, not a generic error — same surface as a mid-session 403.
    expect(container.read(chatTurnProvider), isA<TurnAccessLapsed>());
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

    container.read(chatTurnProvider.notifier).resumeConversation(
      'server-1',
      const [
        (role: MessageRole.user, text: 'earlier question', createdAt: null),
        (role: MessageRole.assistant, text: 'earlier answer', createdAt: null),
      ],
    );

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
