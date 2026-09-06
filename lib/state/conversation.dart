import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';

/// The conversation model and its provider.
///
/// One active conversation per explore app (../ai tier-1 notes § Open
/// questions). Messages are stored as a **tree** (`parent_message_id`) even
/// though the v1 UI renders them linearly — regenerate and edit-and-resend need
/// the tree, and retrofitting a DAG onto a populated store is painful (tier-1
/// notes § Data model). v1 only ever appends, so the tree is a linear chain.

enum MessageRole { user, assistant }

/// One message in the conversation tree.
class ChatMessage {
  /// Local id until the backend assigns one. Stable within a conversation.
  final String id;

  /// The message this one replies to; `null` for the first message.
  final String? parentId;

  final MessageRole role;
  final String text;

  const ChatMessage({
    required this.id,
    required this.parentId,
    required this.role,
    required this.text,
  });
}

/// An immutable snapshot of the conversation: server [id] (null until the first
/// turn persists) and the messages in linear render order.
class Conversation {
  final String? id;
  final List<ChatMessage> messages;

  const Conversation({this.id, this.messages = const []});

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;
}

/// The one active conversation.
///
/// **keepAlive** (the default): it survives a layout-mode switch — the chat
/// panel unmounts on `conversation` → `explore` → back, and its messages must
/// not go with it (docs/chat-state-architecture.md § Lifecycle policy).
///
/// **Reset on sign-out:** `build` watches only the user *id* (via `select`), so
/// a background token refresh — same user, new `User` object — does not wipe the
/// conversation, but a sign-out or a user switch rebuilds it to empty. Signing
/// out must never leave another user's conversation resident.
final conversationProvider =
    NotifierProvider<ConversationNotifier, Conversation>(
      ConversationNotifier.new,
    );

class ConversationNotifier extends Notifier<Conversation> {
  int _seq = 0;

  @override
  Conversation build() {
    // Rebuild (→ empty) only when the user identity changes, not on every auth
    // event. keepAlive keeps it across mode switches; this clears it on
    // sign-out / user switch.
    ref.watch(authProvider.select((user) => user?.id));
    _seq = 0;
    return const Conversation();
  }

  /// Append the user's message; returns it so the caller can thread the
  /// assistant reply beneath it in the tree.
  ChatMessage appendUser(String text) => _append(MessageRole.user, text);

  /// Append the assistant's completed reply.
  ChatMessage appendAssistant(String text) =>
      _append(MessageRole.assistant, text);

  ChatMessage _append(MessageRole role, String text) {
    final message = ChatMessage(
      id: 'local-${_seq++}',
      parentId: state.lastMessage?.id,
      role: role,
      text: text,
    );
    state = Conversation(id: state.id, messages: [...state.messages, message]);
    return message;
  }

  /// Remove a message by id — a pre-accept 402 rolls back its optimistic user
  /// append so local history does not diverge from the server (adityas/ai/129).
  /// No-op if absent. v1 only ever removes the just-appended tail, so the chain
  /// stays linear: the next [appendUser] threads off the new last message.
  void removeMessage(String id) {
    state = Conversation(
      id: state.id,
      messages: state.messages.where((m) => m.id != id).toList(),
    );
  }

  /// Replace the buffer with a resumed transcript (Resume, adityas/ai/86).
  /// [id] is the server conversation now being appended to — held so the picker
  /// can tell when a deleted conversation is the active one. Local ids continue
  /// past the loaded messages so a subsequent [appendUser] stays unique.
  void loadTranscript(
    String id,
    List<({MessageRole role, String text})> messages,
  ) {
    _seq = 0;
    final loaded = <ChatMessage>[];
    String? parentId;
    for (final m in messages) {
      final message = ChatMessage(
        id: 'local-${_seq++}',
        parentId: parentId,
        role: m.role,
        text: m.text,
      );
      loaded.add(message);
      parentId = message.id;
    }
    state = Conversation(id: id, messages: loaded);
  }

  /// Clear to a fresh, empty conversation (New Chat, or deleting the active
  /// one). The transport mints a new server id on the next turn.
  void reset() {
    _seq = 0;
    state = const Conversation();
  }
}
