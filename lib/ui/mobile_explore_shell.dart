import 'package:flutter/material.dart';

import 'tokens.dart';

/// The mobile two-page surface (adityas/ai/108): a swipeable [PageView] of the
/// Explore page (chart wheel + Soul Stances / Your Beings) and the full-screen
/// Solar Prism chat page, with a persistent labelled segmented control pinned at
/// the bottom (thumb zone) as the switcher.
///
/// Both pages stay **mounted** (keepAlive) so switching never rebuilds the wheel
/// or drops in-flight chat state — the chat page keeps streaming even while
/// Explore is on screen, and `show_being` opens its overlay on the Explore page
/// without switching here. The swipe is a bonus on top of the tappable labels,
/// which are the discoverability contract. See docs/layout-modes.md § Mobile.
class MobileExploreShell extends StatefulWidget {
  final Widget explorePage;
  final Widget chatPage;
  final Color color;
  final Color backdropColor;

  const MobileExploreShell({
    super.key,
    required this.explorePage,
    required this.chatPage,
    required this.color,
    required this.backdropColor,
  });

  @override
  State<MobileExploreShell> createState() => _MobileExploreShellState();
}

class _MobileExploreShellState extends State<MobileExploreShell> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Soft keyboard up → the composer owns the above-keyboard slot; the
    // segmented control yields while typing (docs/layout-modes.md § Mobile).
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _controller,
            onPageChanged: (p) => setState(() => _page = p),
            children: [
              _KeepAlive(child: widget.explorePage),
              _KeepAlive(child: widget.chatPage),
            ],
          ),
        ),
        if (!keyboardUp)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _PageSwitcher(
                page: _page,
                color: widget.color,
                backdropColor: widget.backdropColor,
                onSelect: _goTo,
              ),
            ),
          ),
      ],
    );
  }
}

/// Keeps a [PageView] child mounted while off screen (via
/// [AutomaticKeepAliveClientMixin]) so the wheel isn't rebuilt and the chat
/// state isn't dropped on a page switch.
class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The `Explore | Solar Prism` labelled segmented control. The *labels* are the
/// affordance that tells the user a chat exists — a bare swipe carousel was
/// rejected as invisible (docs/layout-modes.md § Mobile).
class _PageSwitcher extends StatelessWidget {
  final int page;
  final Color color;
  final Color backdropColor;
  final ValueChanged<int> onSelect;

  const _PageSwitcher({
    required this.page,
    required this.color,
    required this.backdropColor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: backdropColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _segment(tokens, label: 'Explore', index: 0),
          _segment(tokens, label: 'Solar Prism', index: 1),
        ],
      ),
    );
  }

  Widget _segment(
    ExploreTokens tokens, {
    required String label,
    required int index,
  }) {
    final active = page == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? tokens.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? tokens.onGold : color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
