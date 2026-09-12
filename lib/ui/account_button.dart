import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/chart_service.dart';
import '../api/conversation_service.dart';
import '../file_util.dart';
import '../format/date_labels.dart';
import '../navigate.dart' if (dart.library.js_interop) '../navigate_web.dart';
import '../state/auth.dart';
import '../state/backend.dart';
import '../state/chat_open_request.dart';
import '../state/chat_turn.dart';
import '../state/conversation.dart';
import '../state/entitlement.dart';
import '../state/turn_transport.dart';
import 'chat_coming_soon.dart';
import 'sign_in_dialog.dart';
import 'tokens.dart';

class AccountButton extends ConsumerStatefulWidget {
  final bool hasChart;
  final List<SavedChartSummary> savedCharts;
  final VoidCallback? onSaveChartToServer;
  final void Function(String chartId)? onLoadSavedChart;

  const AccountButton({
    super.key,
    this.hasChart = false,
    this.savedCharts = const [],
    this.onSaveChartToServer,
    this.onLoadSavedChart,
  });

  @override
  ConsumerState<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends ConsumerState<AccountButton> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    if (user != null) {
      final atLimit = widget.savedCharts.length >= 25;
      // Show *Conversations* when chat is live, or whenever a stored archive
      // exists. Gating on existence rather than entitlement lets a former
      // subscriber (lapsed, or access expired to none) still reach their
      // history to download / rename / delete it, and survives access_until
      // being cleared — the ai/120 entitlement proxy hid the item exactly then
      // (adityas/ai/181, superseding that proxy). The archive naturally ages
      // out with the retention-window crypto-shred.
      final hasArchive = ref.watch(hasConversationsProvider);
      final showConversations =
          ref.watch(chatAccessProvider) == ChatAccess.available ||
          hasArchive.when(
            data: (archive) => archive.has,
            // Couldn't check (offline / backend blip): don't read the unknown
            // as a confirmed-empty archive — that would silently strand a
            // former subscriber, since the picker holds the only Retry. Show
            // the item so its own load/error/Retry surface stays reachable
            // (adityas/ai/181).
            error: (_, _) => true,
            // Mid-refresh: keep the last known answer rather than flicker to
            // hidden.
            loading: () => hasArchive.value?.has ?? false,
          );
      return PopupMenuButton<String>(
        icon: const Icon(Icons.person),
        tooltip: 'Account',
        position: PopupMenuPosition.under,
        onOpened: () {
          // If the last archive check errored, retry it on menu-open so a
          // recovered backend un-hides Conversations (and re-hides it for a
          // genuinely empty archive) without an app reload (adityas/ai/181).
          if (ref.read(hasConversationsProvider).hasError) {
            ref.invalidate(hasConversationsProvider);
          }
        },
        onSelected: (value) {
          if (value == 'account') navigateToUrl('/account/');
          if (value == 'save_chart') widget.onSaveChartToServer?.call();
          if (value == 'my_charts') _showMyChartsDialog(context);
          if (value == 'conversations') _showConversationsDialog(context);
          if (value == 'sign_out') _signOut();
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Text(
              user.email ?? 'Signed in',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const PopupMenuDivider(),
          if (widget.hasChart)
            PopupMenuItem(
              value: 'save_chart',
              enabled: !atLimit,
              child: Row(
                children: [
                  const Icon(Icons.save, size: 20),
                  const SizedBox(width: 12),
                  Text(atLimit ? 'Save Chart (limit reached)' : 'Save Chart'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'my_charts',
            child: Row(
              children: [
                Icon(Icons.folder, size: 20),
                SizedBox(width: 12),
                Text('My Charts'),
              ],
            ),
          ),
          if (showConversations)
            const PopupMenuItem(
              value: 'conversations',
              child: Row(
                children: [
                  Icon(Icons.forum, size: 20),
                  SizedBox(width: 12),
                  Text('Conversations'),
                ],
              ),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'account',
            child: Row(
              children: [
                Icon(Icons.manage_accounts, size: 20),
                SizedBox(width: 12),
                Text('Account'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'sign_out',
            child: Row(
              children: [
                Icon(Icons.logout, size: 20),
                SizedBox(width: 12),
                Text('Sign out'),
              ],
            ),
          ),
        ],
      );
    }

    return IconButton(
      icon: const Icon(Icons.person_outline),
      tooltip: 'Sign in',
      onPressed: () => showSignInDialog(context),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  void _showMyChartsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _MyChartsDialog(
        charts: widget.savedCharts,
        onSelect: widget.onLoadSavedChart,
      ),
    );
  }

  void _showConversationsDialog(BuildContext context) {
    // Resume (reopen the thread in live chat to send new turns) is the one
    // entitlement-gated action — the backend refuses turns without a live
    // window. Managing your own archive (download / rename / delete) is
    // owner-gated, so it stays available whether access is live or lapsed
    // (adityas/ai/181). The dialog watches entitlement itself so a renew/lapse
    // (or a still-loading window that resolves) while it is open flips Resume
    // live, rather than freezing whatever state held at open.
    showDialog<void>(
      context: context,
      builder: (context) => const _ConversationsDialog(),
    );
  }
}

class _MyChartsDialog extends StatelessWidget {
  final List<SavedChartSummary> charts;
  final void Function(String chartId)? onSelect;

  const _MyChartsDialog({required this.charts, this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.ink;
    final cardBg = t.cardBg;
    final accent = t.gold;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    'My Charts',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: color, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (charts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No saved charts yet.\nSave a chart from the explorer to see it here.',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.6),
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: charts.length,
                    separatorBuilder: (_, _) => Divider(
                      color: color.withValues(alpha: 0.15),
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final chart = charts[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelect?.call(chart.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome, size: 18, color: accent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  chart.name,
                                  style: TextStyle(color: color, fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The conversation-history picker (adityas/ai/86). Mirrors [_MyChartsDialog]'s
/// chrome; owns its own load/error/action state (dialogs stay `setState` per
/// docs/chat-state-architecture.md). Rows expose Resume, Download, Delete, and
/// Rename — resume is deliberately one option among several, not a one-tap.
class _ConversationsDialog extends ConsumerStatefulWidget {
  const _ConversationsDialog();

  @override
  ConsumerState<_ConversationsDialog> createState() =>
      _ConversationsDialogState();
}

class _ConversationsDialogState extends ConsumerState<_ConversationsDialog> {
  bool _loading = true;
  String? _loadError;
  String? _actionError;
  // Id of the conversation whose PDF export is in flight; its Download button
  // shows a spinner and is disabled to swallow re-taps (adityas/ai/106).
  String? _downloadingId;
  List<ConversationSummary> _items = const [];

  ConversationService get _service => ref.read(conversationServiceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _service.list();
      if (!mounted) return;
      setState(() {
        _items = page.conversations;
        _loading = false;
      });
    } on ConversationApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.statusCode == 401
            ? 'Session expired — please sign in again.'
            : 'Could not load your conversations.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load your conversations.';
        _loading = false;
      });
    }
  }

  Future<void> _resume(ConversationSummary c) async {
    try {
      final history = await _service.fetch(c.id);
      final messages = history.messages
          .map(
            (m) => (
              role: m.fromUser ? MessageRole.user : MessageRole.assistant,
              text: m.content,
              createdAt: m.createdAt,
            ),
          )
          .toList();
      ref
          .read(chatTurnProvider.notifier)
          .resumeConversation(
            history.id,
            messages,
            compactedThrough: history.compactedThrough,
          );
      ref.read(chatOpenRequestProvider.notifier).request();
      if (mounted) Navigator.of(context).pop();
    } on ConversationApiException catch (e) {
      _showActionError('Could not open that conversation. ${e.message}');
    } catch (_) {
      _showActionError('Could not open that conversation.');
    }
  }

  Future<void> _download(ConversationSummary c) async {
    // The Typst compile takes a few seconds; ignore re-taps while it runs.
    if (_downloadingId != null) return;
    setState(() {
      _downloadingId = c.id;
      _actionError = null;
    });
    try {
      final bytes = await _service.exportPdf(c.id);
      await saveFileBytes(
        '${chartFileStem(_label(c))}.pdf',
        bytes,
        dialogTitle: 'Save conversation',
      );
    } on ConversationApiException catch (e) {
      _showActionError(
        e.statusCode == 404
            ? 'PDF export is not available yet.'
            : 'Could not download that conversation. ${e.message}',
      );
    } catch (_) {
      _showActionError('Could not download that conversation.');
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _rename(ConversationSummary c) async {
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _RenameConversationDialog(initialTitle: c.title ?? ''),
    );
    final title = next?.trim();
    if (title == null || title.isEmpty) return;
    try {
      await _service.rename(c.id, title);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in _items)
            if (item.id == c.id)
              ConversationSummary(
                id: item.id,
                title: title,
                updatedAt: item.updatedAt,
                turnCount: item.turnCount,
              )
            else
              item,
        ];
      });
    } on ConversationApiException catch (e) {
      _showActionError('Could not rename. ${e.message}');
    } catch (_) {
      _showActionError('Could not rename that conversation.');
    }
  }

  Future<void> _delete(ConversationSummary c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConversationDialog(label: _label(c)),
    );
    if (confirmed != true) return;
    try {
      await _service.delete(c.id);
      // Deleting the currently-active thread resets the panel to a fresh one.
      // The active id lives in [Conversation.id] only for a *resumed* thread; a
      // conversation minted this session is tracked solely by the transport
      // (adityas/ai/86), so check both.
      final resumedActive = ref.read(conversationProvider).id == c.id;
      final mintedActive =
          ref.read(turnTransportProvider).conversationId == c.id;
      if (resumedActive || mintedActive) {
        ref.read(chatTurnProvider.notifier).startNewConversation();
      }
      if (!mounted) return;
      setState(() => _items = [..._items.where((x) => x.id != c.id)]);
      // Refresh the account-menu gate so *Conversations* disappears once the
      // last thread is gone (adityas/ai/181).
      ref.invalidate(hasConversationsProvider);
    } on ConversationApiException catch (e) {
      _showActionError('Could not delete. ${e.message}');
    } catch (_) {
      _showActionError('Could not delete that conversation.');
    }
  }

  void _showActionError(String message) {
    if (!mounted) return;
    setState(() => _actionError = message);
  }

  String _label(ConversationSummary c) {
    final raw = c.title;
    return (raw == null || raw.trim().isEmpty) ? 'Conversation' : raw.trim();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.ink;
    final actionError = _actionError;
    // Watched (not snapshotted at open): Resume is the one entitlement-gated
    // action — the backend refuses turns without a live window. Managing your
    // own archive (download / rename / delete) is owner-gated, so it stays
    // available regardless. Watching means a renew/lapse — or a window still
    // loading at open — flips every row live instead of freezing (adityas/ai/181).
    final canResume = ref.watch(chatAccessProvider) == ChatAccess.available;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    'Conversations',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: color, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (actionError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    actionError,
                    style: TextStyle(color: t.error, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              Flexible(child: _body(color, t, canResume)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Color color, ExploreTokens t, bool canResume) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final loadError = _loadError;
    if (loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loadError,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => unawaited(_load()),
              child: Text('Retry', style: TextStyle(color: t.gold)),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No conversations yet.\nStart chatting with the Prism to see your threads here.',
          style: TextStyle(
            color: color.withValues(alpha: 0.6),
            fontSize: 14,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          Divider(color: color.withValues(alpha: 0.15), height: 1),
      itemBuilder: (context, index) => _row(_items[index], color, t, canResume),
    );
  }

  Widget _row(
    ConversationSummary c,
    Color color,
    ExploreTokens t,
    bool canResume,
  ) {
    final subtitle = c.turnCount >= 20
        ? '${relativeTimeLabel(c.updatedAt)} · Long conversation'
        : relativeTimeLabel(c.updatedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _label(c),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (canResume)
            _action(Icons.play_arrow, 'Resume', t.gold, () => _resume(c))
          else
            // Access has lapsed: Resume would dead-end on the backend's turn
            // gate (403), so offer renewal instead of a play button that fails
            // on send. PLACEHOLDER — routes to the shared renew modal, whose
            // real copy + purchase CTA land in adityas/ai/85.
            _action(
              Icons.lock_outline,
              'Renew to resume',
              t.gold,
              () => showChatRenewModal(context),
            ),
          _action(
            Icons.download,
            'Download',
            color.withValues(alpha: 0.7),
            () => _download(c),
            loading: _downloadingId == c.id,
          ),
          // Owner-gated, not entitlement-gated: you can always curate your own
          // archive, live window or not (adityas/ai/181).
          _action(
            Icons.edit,
            'Rename',
            color.withValues(alpha: 0.7),
            () => _rename(c),
          ),
          _action(Icons.delete_outline, 'Delete', t.error, () => _delete(c)),
        ],
      ),
    );
  }

  Widget _action(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onPressed, {
    bool loading = false,
  }) {
    return IconButton(
      icon: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 20, color: color),
      tooltip: tooltip,
      onPressed: loading ? null : onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
    );
  }
}

/// Rename dialog for one conversation. Returns the new title, or null on cancel.
class _RenameConversationDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameConversationDialog({required this.initialTitle});

  @override
  State<_RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isNotEmpty) Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.ink;

    return AlertDialog(
      backgroundColor: t.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      title: Text(
        'Rename conversation',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: color),
        decoration: InputDecoration(
          labelText: 'Title',
          labelStyle: TextStyle(color: color.withValues(alpha: 0.7)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.gold),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: color.withValues(alpha: 0.7)),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: t.gold,
            foregroundColor: t.onGold,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Delete confirmation — the deliberate friction on an irreversible shred.
class _DeleteConversationDialog extends StatelessWidget {
  final String label;

  const _DeleteConversationDialog({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.ink;

    return AlertDialog(
      backgroundColor: t.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      title: Text(
        'Delete conversation?',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      content: Text(
        'This permanently deletes "$label". It can\'t be recovered.',
        style: TextStyle(color: color.withValues(alpha: 0.85), height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: color.withValues(alpha: 0.7)),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: t.error,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
