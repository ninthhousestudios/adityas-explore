# Layout Modes

Foundational layout architecture for the explore app's desktop view, built to
make room for the upcoming AI chat feature. Read this before touching the panel
composition in `lib/ui/chart_wheel.dart` or building the chat UI.

## The problem

Today the desktop layout is a centered square chart (`side = min(w, h)`) with
info panels pinned into the **side gutters** — the dead horizontal space a wide
viewport leaves on either side of the square. See `_ChartWheelState.build`:
`SoulStancesPanel` is `Positioned(left: 8)`, the beings column is
`Positioned(right: 8)`, both sized to `panelWidth = panelMargin - 16`. Mobile is
detected implicitly by `panelMargin < 80`.

This works, but every panel's position is **coupled to the gutter**. When chat
opens, the chart must shrink and shift to one side, the gutters collapse, and the
panels have nowhere to live. The gutter coupling is the thing chat breaks.

## The decision: modes, not a window manager

We considered a general window-manager paradigm — every element freely
moveable, resizeable, closable, with z-ordering, overlap, and saved layouts,
toggled via right-click context menus. **Rejected.**

Rationale:

- The actual goal is "make room for chat," which is a **mode transition**, not
  manual window juggling.
- Free-floating overlapping panels are a known-bad default for consumer products
  (users don't arrange them well, create clutter, and can strand a panel
  off-screen with no way back). Serious tools — Figma, Linear, VS Code — use
  docked/reflowing regions, not free float.
- The build cost (drag handles, hit-testing, resize cursors, collision,
  z-order, persistence) is large and buys a UI most users would break.
- There is no real user need pulling toward arrangeable panels.

Instead: **layout is state driven by a small set of named modes.** The chart's
size/position and where panels go are functions of the current mode. Transitions
become animatable because layout is data, not hardcoded `Positioned` widgets.

## Two layers, two behaviors

The clean rule that resolves the rest:

| Layer | Members | Behavior |
|-------|---------|----------|
| **Persistent panels** | Soul Stances, Your Beings, Shop/Waitlist CTAs, (future) Chat | Dock and reflow with the mode. Toggle on/off. Never overlap each other. |
| **Transient popups** | being detail, planet detail, being-type detail | Float above everything, overlap freely, z-ordered. Draggable + resizable. |

The transient layer lives in `overlayControllerProvider`
(`lib/state/overlay.dart`) — the popup stack + floating-window geometry — with
`overlay_shell.dart` + `_ChartWheelState._buildOverlay` rendering it. It was
lifted out of widget state so the chat tool-call path (`show_being`) can drive
it with no `BuildContext` (adityas/explore/45; docs/chat-state-architecture.md
§ Overlay ripple). This move changed *where the transient stack lives*, not the
two-layer rule above.

## Modes

`LayoutMode { explore, conversation, focus }`

- **explore** — today's layout. Chart centered, persistent panels docked in the
  gutters, all visible by default.
- **conversation** — chart shrinks and shifts to one side; the chat panel claims
  a docked column on the other. Info panels collapse out of the dock and become
  toggle-to-overlay (user or AI can summon one; it floats over the chart and
  dismisses). Entered when a chat begins. The chat surface itself — bottom-right
  input pill in explore mode, drag-to-resize of the docked column, and the
  visible-but-gated presentation — is specified in [`chat-surface.md`](chat-surface.md).
- **focus** — chart only; all persistent panels hidden. Escape hatch for a clean
  read.

Chat is stubbed in this foundation — a placeholder panel is enough to prove the
mode transition. The chat UI itself is a later feature.

## Foundation to build (pre-chat)

1. **`PanelId` enum + a layout controller.** Holds which persistent panels are
   visible and the current `LayoutMode`. `_ChartWheelState.build` renders panels
   from this state instead of hardcoded `Positioned` blocks.
2. **`LayoutMode` enum + reflow.** Chart size/position and panel placement derive
   from the mode. Explore = current behavior; conversation reserves a docked
   column and animates the chart aside; focus hides panels. Chat panel is a stub.
3. **Draggable + resizable transient popups.** Extend `overlay_shell` so the
   detail popups can be moved (drag the title bar) and resized (drag a corner).
   Exercises the exact floating-layer mechanics a floating chat window would
   reuse, and is an independent UX win shippable before chat exists.
4. **Visible panel-visibility affordance.** A control to show/hide persistent
   panels (and a per-panel close). Right-click context-menu toggling is allowed
   as a *secondary* power-user shortcut, never the primary discovery path —
   right-click is invisible to most users.

Done well, adding chat later is "add a `conversation` mode + a chat panel," not a
re-architecture. The hard part — and the real payoff — is the transition
choreography (chart resize/recenter + panel reflow), which falls out once layout
is animatable state.

## Explicitly out of scope

- Free move/resize of the **persistent** side panels (only transient popups move).
- Arbitrary z-order / overlap among persistent panels.
- User-saved custom layouts. Preset named modes only.
- Right-click context menu as the primary panel-toggle affordance.

## Mobile

Unchanged by this work. Mobile stays a carousel: chart on one page, chat on
another. The main mobile design task is signalling that a chat exists. Modes are
a desktop concern; the `panelMargin < 80` branch in `build` continues to drive
the mobile path.
