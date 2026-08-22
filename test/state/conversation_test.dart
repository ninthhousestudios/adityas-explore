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
