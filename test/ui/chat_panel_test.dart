import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/api/chart_service.dart';
import 'package:explore/state/auth.dart';
import 'package:explore/state/chat_turn.dart';
import 'package:explore/state/consent.dart';
import 'package:explore/state/conversation.dart';
import 'package:explore/state/delta_throttle.dart';
import 'package:explore/state/entitlement.dart';
import 'package:explore/state/turn_transport.dart';
import 'package:explore/state/usage.dart';
import 'package:explore/ui/chat_panel.dart';

/// Panel-level tests for the two in-flight behaviours the state-machine tests
/// can only see headless: the polite live-region announcement cadence + final
/// flush (adityas/ai/143), and the composer's affordance/clear behaviour across
/// the post-Stop settling window (adityas/ai/142).

/// A [TurnTransport] the test drives event-by-event (mirrors chat_turn_test).
class _FakeTransport implements TurnTransport {
  final List<StreamController<TurnEvent>> _controllers = [];
  int starts = 0;
  bool cancelSucceeds = true;

  StreamController<TurnEvent> get _current => _controllers.last;

  @override
  String? conversationId;

  @override
  Stream<TurnEvent> start(TurnRequest request) {
    starts++;
    final controller = StreamController<TurnEvent>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<TurnEvent> resume(String cursor) {
    final controller = StreamController<TurnEvent>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<bool> cancel() async => cancelSucceeds;

  @override
  void adoptConversation(String id) => conversationId = id;

  @override
  void resetConversation() => conversationId = null;

  void emit(TurnEvent event) => _current.add(event);
}

class _FakeUsage implements UsageClient {
  @override
  Future<int> fetchUsagePct() async => 0;
}

class _FakeConsent implements ConsentClient {
  @override
  Future<ChatConsent> fetchConsent() async => const ChatConsent(
    currentVersion: 'v1',
    acceptedVersion: 'v1',
    needsConsent: false,
  );

  @override
  Future<void> recordConsent() async {}
}

const _stubUser = User(
  id: 'test-user',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

class _StubAuth extends AuthNotifier {
  @override
  User? build() => _stubUser;
}

ProviderContainer _container(_FakeTransport transport) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_StubAuth.new),
      turnTransportProvider.overrideWithValue(transport),
      deltaThrottleFactoryProvider.overrideWithValue(
        () => const ImmediateThrottle(),
      ),
      // A live window: the wired surface (history + composer) renders.
      chatAvailableProvider.overrideWith((ref) => true),
      usageClientProvider.overrideWithValue(_FakeUsage()),
      consentClientProvider.overrideWithValue(_FakeConsent()),
      accessDeadlineProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: ChatPanel(
            color: Colors.white,
            backdropColor: Colors.black,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );
}

/// The current label on the panel's single persistent live region.
String _liveLabel(WidgetTester tester) =>
    tester.widget<StreamingLiveRegion>(find.byType(StreamingLiveRegion)).label;

void main() {
  testWidgets('a burst of deltas immediately followed by done announces the '
      'final answer, not a stale "Thinking…" (adityas/ai/143)', (tester) async {
    final transport = _FakeTransport();
    final container = _container(transport);
    await _pumpPanel(tester, container);

    container.read(chatTurnProvider.notifier).send('hi');
    await tester.pump(); // TurnConnecting → "Thinking…" scheduled (paced)

    // A burst of deltas arrives within one cadence window, then done fires at
    // once — before the paced timer would have ticked.
    transport
      ..emit(const DeltaEvent('Hello', 'e1'))
      ..emit(const DeltaEvent(' world', 'e2'));
    await tester.pump();
    // Paced: the cadence tick has not elapsed, so nothing has been announced yet.
    expect(_liveLabel(tester), '');

    transport
      ..emit(const UsageEvent(TurnUsage(inputTokens: 1, outputTokens: 1), 'e3'))
      ..emit(const DoneEvent('e4'));
    await tester.pump(); // deliver the stream events
    await tester.pump(); // apply the flush setState

    // done flushes the final text immediately (no waiting on the cadence, no
    // truncation to "Thinking…").
    expect(_liveLabel(tester), 'Hello world');
    // Exactly one live region — the persistent panel-level one.
    expect(find.byType(StreamingLiveRegion), findsOneWidget);
    // The reply lives in history as a normal (non-live) message, in full.
    expect(
      container.read(conversationProvider).messages.last.text,
      'Hello world',
    );
  });

  testWidgets('streaming announcements are paced on a human-scale cadence, not '
      'per visual repaint (adityas/ai/143)', (tester) async {
    final transport = _FakeTransport();
    final container = _container(transport);
    await _pumpPanel(tester, container);

    container.read(chatTurnProvider.notifier).send('hi');
    await tester.pump();

    // Several repaints' worth of deltas within one window announce nothing yet.
    transport.emit(const DeltaEvent('a', 'e1'));
    await tester.pump();
    transport.emit(const DeltaEvent('b', 'e2'));
    await tester.pump();
    transport.emit(const DeltaEvent('c', 'e3'));
    await tester.pump();
    expect(_liveLabel(tester), '');

    // Once the cadence elapses, the region announces the LATEST text once.
    await tester.pump(kLiveRegionCadence);
    expect(_liveLabel(tester), 'abc');

    // Settle the turn so no cadence timer is left pending at teardown.
    transport.emit(const DoneEvent('e4'));
    await tester.pump();
    expect(_liveLabel(tester), 'abc');
  });

  testWidgets('a cancelled turn flushes its partial to the live region '
      '(adityas/ai/143 + ai/140)', (tester) async {
    final transport = _FakeTransport();
    final container = _container(transport);
    await _pumpPanel(tester, container);

    container.read(chatTurnProvider.notifier).send('hi');
    await tester.pump();
    transport.emit(const DeltaEvent('partial reply', 'e1'));
    await tester.pump();
    // Paced — not yet announced.
    expect(_liveLabel(tester), '');

    await container.read(chatTurnProvider.notifier).cancel();
    await tester.pump();
    // Stop flushes the partial the user was reading — it is not lost to a
    // pending cadence tick.
    expect(_liveLabel(tester), 'partial reply');
  });

  testWidgets('the live region is a single polite region reaching the '
      'semantics tree (adityas/ai/143)', (tester) async {
    final handle = tester.ensureSemantics();
    final transport = _FakeTransport();
    final container = _container(transport);
    await _pumpPanel(tester, container);

    container.read(chatTurnProvider.notifier).send('hi');
    await tester.pump();
    transport
      ..emit(const DeltaEvent('hi there', 'e1'))
      ..emit(const DoneEvent('e2')); // flush + no pending timer
    await tester.pump();

    expect(find.byType(StreamingLiveRegion), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(StreamingLiveRegion)),
      matchesSemantics(isLiveRegion: true, label: 'hi there'),
    );
    handle.dispose();
  });

  testWidgets('submitting during the post-Stop settling window keeps the typed '
      'text and the button stays Stop (adityas/ai/142)', (tester) async {
    final transport = _FakeTransport();
    final container = _container(transport);
    await _pumpPanel(tester, container);

    container.read(chatTurnProvider.notifier).send('hi');
    await tester.pump();
    transport.emit(const DeltaEvent('partial', 'e1'));
    await tester.pump();

    // Stop the turn — it enters the settling window (TurnCancelled, latch held).
    await container.read(chatTurnProvider.notifier).cancel();
    await tester.pump();
    expect(container.read(chatTurnProvider.notifier).isSettling, isTrue);
    // The affordance stays Stop, never reverting to Send during settling.
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.send), findsNothing);

    // Type and press Enter during the window: the send is refused, so the text
    // must NOT be silently discarded.
    await tester.enterText(find.byType(TextField), 'my question');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('my question'), findsOneWidget); // still in the field
    expect(transport.starts, 1); // no turn opened

    // The stopped turn settles; the affordance returns to Send.
    transport
      ..emit(const UsageEvent(TurnUsage(inputTokens: 1, outputTokens: 1), 'e2'))
      ..emit(const DoneEvent('e3'));
    await tester.pump();
    expect(container.read(chatTurnProvider.notifier).isSettling, isFalse);
    expect(find.byIcon(Icons.send), findsOneWidget);

    // The preserved text now sends (opens a turn) and the field clears — the
    // text lands as a user message in history rather than being lost.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(transport.starts, 2);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(
      container.read(conversationProvider).messages.last.text,
      'my question',
    );
  });
}
