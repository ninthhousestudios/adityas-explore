# Chat Surface

Design for the Solar Prism chat as a first-class element of the desktop explore
page: where the input lives, how the chat column resizes, and how the surface
presents to users who can't (yet) use it. Companion to
[`layout-modes.md`](layout-modes.md) (the mode/dock architecture this builds on)
and [`chart-wheel.md`](chart-wheel.md).

Design task: adityas/ai/80. Build task: adityas/ai/81. Desktop only — mobile is a
separate concern (two full-screen pages + a labelled `Explore | Solar Prism`
switcher; see layout-modes.md § Mobile and adityas/ai/95).

## What already exists

- Chat is the `conversation` `LayoutMode`. `_geometryFor(conversation)` already
  shrinks the chart into `leftRegion = w − chatW − gap` and recenters it while a
  docked chat column claims the right. Today `chatW` is the constant
  `_chatColumnWidth(w) = (w*0.3).clamp(300, 460)`.
- The conversation + in-flight turn live in keepAlive providers
  (`conversationProvider` / `chatTurnProvider`), **not** in the widget. Switching
  modes unmounts `ChatPanel` but loses no history — this is why "leave chat, come
  back, same chat" works. Preserve this.
- The input ("Hold something up to the Prism…") lives *inside* `ChatPanel`
  (`_composer`). It does not exist in explore mode today.
- Gating is `chatEnabledProvider` — a hard-coded allowlist. "Entitled" today
  means "allowlisted." Non-entitled users who reach conversation mode see a
  `_placeholder` + dead `_lockedComposer`.

## 1. Placement

**Extract the composer into a shared widget.** It is used in two places:

- **Explore mode** — a standalone composer *pill* docked bottom-right
  (`bottom: 24, right: 8`, matching the right-gutter `panelWidth`). It reads as
  the entrance beneath the "Your Beings" / Shop / waitlist column, which ends
  ~⅔ down and leaves the lower-right free. No collision with the bottom-left
  settings gear.
- **Conversation mode** — the same composer at the bottom of `ChatPanel`, as now.

The explore-mode pill is **composer-only** — no message history preview over the
chart. History belongs to the panel.

### The pill is a ramp into conversation mode

You cannot stream an answer in explore mode (no panel to render it). So the rule
is simple and uniform:

> **Submitting from the explore-mode pill always transitions to conversation
> mode**, pre-seeded with the typed text, then sends.

Mid-conversation this is the same motion: an entitled user who switched back to
explore (via settings → Mode) still sees the pill; typing + Enter re-enters
conversation mode with prior history intact and continues the thread. "Continues
the chat" means *the panel comes back with its history* — not that replies render
in explore mode.

## 2. Sizing / resize

The chart-shrink machinery already exists; resize just feeds `_geometryFor` a
**stateful** `_chatWidth` instead of the `_chatColumnWidth` constant.

- **Min** = today's `_chatColumnWidth(w)` — the current width is the floor.
- **Max** = the width at which the chart hits its floor. **Chart floor = 60% of
  its explore size** (its explore side is `min(w, boxH)`). So
  `maxChatW = w − gap − 0.6 * min(w, boxH)`, clamped so `maxChatW ≥ minChatW`.
- **Handle**: a thin drag handle on the **left edge** of the docked chat column.
  Dragging left grows `_chatWidth` (clamped to `[minChatW, maxChatW]`); the chart
  shifts left and shrinks via the existing geometry. On web, show a horizontal
  resize cursor on the handle (`MouseRegion` / `SystemMouseCursors.resizeLeftRight`).
- Build a **docked one-axis edge handle**, not a reuse of the floating-popup
  resize corner — different geometry (docked column vs. free window).
- Live drag updates `_chatWidth` via `setState` (no animation); the explore↔
  conversation mode transition still animates, lerping to the current
  `_chatWidth`.
- Session-only. Do not persist `_chatWidth` to prefs — out of scope.
- Resize is conversation-mode only; the explore-mode pill is fixed width.

## 3. Visible-but-gated presentation

The pill is visible to **everyone** so the feature is discoverable. Behavior
forks on `chatAccessProvider` — a three-state signal (`available` / `lapsed` /
`none`, `lib/state/entitlement.dart`) that supersedes the old
`chatEnabledProvider` boolean for surface reachability. `available` folds in the
allowlist (the only non-`none` population today) and a live paid window:

- **Available** — real composer. Type, Enter, ramp into conversation.
- **Lapsed** (adityas/ai/120) — a former subscriber whose window closed. The
  wired surface stays reachable: the composer stays visible, but a new turn is
  refused into the *renew prompt* (`TurnAccessLapsed`) — the same surface a
  mid-session 403 lands on. The Conversations picker gates **Resume** behind
  renewal ("Renew to resume") while keeping download / rename / delete
  (owner-gated, adityas/ai/181); in-app read-only reopening of a past thread is
  deferred to a future "View" action (adityas/ai/182). The backend serves reads
  during the retention window (adityas/ai/89).
- **None** — never entitled / signed out. The pill is a *look-alike button*, not a
  real field. It does not accept focus/typing. **Tapping it opens a modal.** This
  is the deliberate choice over let-them-type-then-reject.

### Focus-to-trigger, not submit-to-reject

Non-entitled users get the modal the moment they click the pill — they never type
into a dead end.

### One "coming soon" modal now — split at launch

Purchase is not live, so **collapse logged-out and logged-in-without-entitlement
into one modal now**: a brief "Solar Prism · Contemplate AI Chat" coming-soon
card with a short description. Showing "sign in to unlock" today would be a lie —
signing in unlocks nothing until purchase ships.

- **Style**: a **centered modal** (focused interruption, dismiss to return) — not
  a draggable transient popup.
- **Single source of copy.** The settings → Mode → Chat back-door still drops any
  user into conversation mode, where a non-entitled user sees the panel's
  coming-soon placeholder. That placeholder and the pill modal must render the
  **same copy from one source**. Two routes, one message.

The modal and the placeholder are the **`none`** surface only. A **`lapsed`**
user does *not* see them — they get their read-only history + renew prompt
(adityas/ai/120), a distinct branch.

**At launch** (see the pre-launch task, gates adityas/ai/74) the single `none`
modal splits into the two real states:

- **Logged out** → invitation to sign in / create an account.
- **Logged in, no entitlement** → prompt to buy the Solar Prism.

This is the client face of the `chatAvailable`/`chatAccess` gating in
adityas/ai/18 — keep the two in sync so entitlement truth and its presentation
don't drift.

## 4. Transient popups vs. an expanded chat

Being / planet / being-type popups are the transient floating layer
(`overlayControllerProvider`). Today `_defaultPopupRect` centers a new popup over
the **whole** desktop area and `_clampPopupRect` clamps to the full width — so in
conversation mode a popup spawns half-under the chat column and can be dragged
under it.

**Make the transient-popup bounds mode-aware.** In conversation mode the popups'
area is the `leftRegion` (the chart side): right edge at `chatLeft − gap`. This
both spawns new popups centered over the chart and clamps drags so they can't
slide under the chat. Users keep full freedom *within* that region. Explore /
focus modes keep the full-width bounds. Thread the effective bounds into
`overlayWindowRect` and the drag/resize clamps rather than hard-coding full
width.

## Out of scope / unchanged

- Mobile (two full-screen pages + labelled switcher; layout-modes.md § Mobile).
- Persisting chat width or custom layouts.
- The keepAlive provider architecture for conversation/turn state — reuse as-is.
- Focus mode hides the pill along with the other panels (clean read).
