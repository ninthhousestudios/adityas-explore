import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explore/state/auth.dart';
import 'package:explore/state/conversation.dart';

const _stubUser = User(
  id: 'test-user',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

/// An auth stub whose user the test can clear, to drive sign-out.
class _MutableAuth extends AuthNotifier {
  User? _user;
  _MutableAuth(this._user);

  @override
  User? build() => _user;

  void signOut() {
    _user = null;
    state = null;
  }
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('appends thread into a parent chain (user → assistant)', () {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _MutableAuth(_stubUser))],
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationProvider.notifier);
    final user = notifier.appendUser('tell me about my Soul Stance');
    final reply = notifier.appendAssistant('Your Sun sits with the Adityas…');

    final convo = container.read(conversationProvider);
    expect(convo.messages, hasLength(2));
    expect(convo.messages.first.role, MessageRole.user);
    expect(convo.messages.last.role, MessageRole.assistant);
    expect(user.parentId, isNull); // first message has no parent
    expect(reply.parentId, user.id); // reply threads beneath the user message
  });

  test('loadTranscript replaces the buffer and records the server id', () {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _MutableAuth(_stubUser))],
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationProvider.notifier)
      ..appendUser('a stale message from the previous thread')
      ..loadTranscript('server-convo-1', const [
        (role: MessageRole.user, text: 'what is my Soul Stance?'),
        (role: MessageRole.assistant, text: 'Your Sun sits with the Adityas…'),
        (role: MessageRole.user, text: 'tell me more'),
      ]);

    final convo = container.read(conversationProvider);
    expect(convo.id, 'server-convo-1');
    expect(convo.messages, hasLength(3));
    expect(convo.messages.first.role, MessageRole.user);
    expect(convo.messages.first.parentId, isNull);
    // Loaded messages form a linear chain.
    expect(convo.messages[1].parentId, convo.messages.first.id);
    expect(convo.messages[2].parentId, convo.messages[1].id);

    // A subsequent append continues the chain with a unique id.
    final next = notifier.appendUser('and after that?');
    expect(next.parentId, convo.messages.last.id);
    expect(
      container.read(conversationProvider).messages.map((m) => m.id).toSet(),
      hasLength(4),
    );
  });

  test('reset clears to a fresh empty conversation', () {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _MutableAuth(_stubUser))],
    );
    addTearDown(container.dispose);

    container.read(conversationProvider.notifier).loadTranscript(
      'server-convo-1',
      const [(role: MessageRole.user, text: 'hi')],
    );
    expect(container.read(conversationProvider).id, 'server-convo-1');

    container.read(conversationProvider.notifier).reset();

    final convo = container.read(conversationProvider);
    expect(convo.id, isNull);
    expect(convo.messages, isEmpty);
  });

  test('keepAlive: survives an unwatch/rewatch (a mode switch)', () {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _MutableAuth(_stubUser))],
    );
    addTearDown(container.dispose);

    container.read(conversationProvider.notifier).appendUser('hello');

    // Simulate the chat panel mounting then unmounting on a mode switch.
    container.listen(conversationProvider, (_, _) {}).close();

    // keepAlive → the conversation is not disposed when unwatched.
    expect(container.read(conversationProvider).messages, hasLength(1));
  });

  test('resets to empty on sign-out', () async {
    final auth = _MutableAuth(_stubUser);
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => auth)],
    );
    addTearDown(container.dispose);

    // Keep the provider resident so the auth dependency is live.
    final sub = container.listen(conversationProvider, (_, _) {});
    addTearDown(sub.close);

    container.read(conversationProvider.notifier).appendUser('hello');
    expect(container.read(conversationProvider).messages, isNotEmpty);

    auth.signOut();
    await _pump();

    expect(container.read(conversationProvider).messages, isEmpty);
  });
}
