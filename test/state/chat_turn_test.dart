import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/state/auth.dart';
import 'package:explore/state/chat_turn.dart';
import 'package:explore/state/conversation.dart';
import 'package:explore/state/delta_throttle.dart';
import 'package:explore/state/entitlement.dart';
import 'package:explore/state/turn_transport.dart';

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

  void emit(TurnEvent event) => _current.add(event);

  /// Premature close: the stream ends without a terminal event (broken stream).
  Future<void> closeStream() => _current.close();

  /// Transient drop: the stream raises an error (→ reconnect).
  void dropStream(Object error) => _current.addError(error);
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

ProviderContainer _container(_FakeTransport transport) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _StubAuth(_stubUser)),
      turnTransportProvider.overrideWithValue(transport),
      deltaThrottleFactoryProvider.overrideWithValue(
        () => const ImmediateThrottle(),
      ),
      chatAvailableProvider.overrideWith((ref) => ref.watch(_gateProvider)),
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
    expect(done.usage.totalTokens, 15);

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

  test('entitlement expiry mid-turn ends the turn in error', () async {
    final transport = _FakeTransport();
    final container = _container(transport);

    container.read(chatTurnProvider.notifier).send('hi');
    transport.emit(const DeltaEvent('mid', 'e1'));
    await _pump();
    expect(container.read(chatTurnProvider), isA<TurnStreaming>());

    // Access lapses while streaming.
    container.read(_gateProvider.notifier).update(false);
    await _pump();

    final errored = container.read(chatTurnProvider);
    expect(errored, isA<TurnError>());
    expect(transport.cancels, 1); // best-effort server stop
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
}
