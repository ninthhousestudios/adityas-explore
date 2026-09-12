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
- **None** — never entitled / signed out, *or* a former subscriber whose window
  was cleared. The pill is a *look-alike button*, not a real field. It does not
  accept focus/typing. **Tapping it opens a modal** — the coming-soon/buy modal,
  or the renew modal for a former subscriber who still has history (the fork on
  archive existence, adityas/ai/183, below). This is the deliberate choice over
  let-them-type-then-reject.

### Focus-to-trigger, not submit-to-reject

Non-entitled users get the modal the moment they click the pill — they never type
into a dead end.

### The `none` gate — split into sign-in vs. buy (adityas/ai/85)

The `none` surface is a **centered modal** (focused interruption, dismiss to
return — not a draggable transient popup) headed "Solar Prism", with a
"Contemplative AI Chat" tagline and a short description. It forks on auth
(`authProvider`) into the two real states:

- **Logged out** → *"Sign in to your account to purchase Solar Prism."* CTA
  **Sign in** opens the in-app sign-in dialog (`showSignInDialog`,
  `ui/sign_in_dialog.dart`) — the user stays in Explore, and on sign-in the
  entitlement refetch re-renders this surface into the buy state below.
- **Logged in, no access** → *"Unlock Solar Prism to begin."* CTA **Get Solar
  Prism** opens the shop page (`solarPrismShopUrl`, `/shop/solar-prism`) in a new
  tab. Explore never runs checkout itself (no client-side business logic); the
  shop page owns sign-in, pricing, and Stripe.

Both states, plus the copy/CTA mapping, live in one source (`ChatGate` +
`ChatComingSoon` in `ui/chat_coming_soon.dart`). The settings → Mode → Chat
back-door drops a non-entitled user *with no history* into the panel placeholder,
which renders the same `ChatComingSoonMessage` + `_gateCta` — two routes, one
message (a former subscriber *with* history gets the renew surface below). This is
the
client face of the `chatAvailable`/`chatAccess` gating in adityas/ai/18; keep the
two in sync so entitlement truth and its presentation don't drift.

The modal and the placeholder are the **`none`** surface only. A **`lapsed`**
user does *not* see them — they get their read-only history + renew prompt
(adityas/ai/120), a distinct branch. The renew prompt (in-thread bubble and the
explore-mode/`Renew to resume` modal) carries a **Renew Solar Prism** CTA to the
same shop page.

### Former subscriber with history → renew, not buy (adityas/ai/183)

`none` conflates two populations: a **never-entitled** user (correct buy-stub
audience) and a **former subscriber whose `access_until` was cleared/deleted**
(refund, chargeback, admin revoke). Natural expiry leaves `access_until`
non-null-in-the-past → `lapsed`; only a *cleared* entitlement collapses to
`none`. So the `none` surface forks again on whether the user **owns chat
history**. Both chat surfaces read this from one shared helper, `chatAccessFork`
(`lib/state/entitlement.dart`), so the panel and pill cannot drift (adityas/42);
it answers from two independent signals, either sufficient:

- an **in-session transcript** (`conversationProvider`) — the strongest signal,
  and the one that defends the *visible* thread when a mid-session 403 clears
  access. It holds even if the archive check cached `false` before this
  conversation was minted (adityas/42).
- **archived conversations** (`hasConversationsProvider`,
  `lib/state/conversation.dart`) — the same signal that gates the account-menu
  *Conversations* item (adityas/ai/181), for a fresh open with no in-session
  thread. A lookup **error is not a confirmed-empty archive** (that provider's
  contract, ai/181): it reads as history too, matching the account menu
  (`account_button.dart`) rather than stranding a former subscriber on the buy
  stub during a backend blip (adityas/42). The answer is **tagged with the auth
  id it was resolved for** (`ResolvedArchive`): on a user switch Riverpod retains
  the prior identity's answer as an `AsyncLoading`-with-previous, and the fork
  reads a value only when its id matches the current user — so user B is never
  routed by user A's archive; a mismatch reads as still-pending until B's own
  lookup lands (adityas/ai/198 finding A, mirroring the entitlement seam's
  identity guard, ai/196).

The fork then routes:

- **`none` + owns history** → the **renew surface**: the renew ask
  (`chatRenewPanelCopy`) plus a pointer to where the history still lives
  (`chatRenewPanelHistoryNote` → account menu → *Conversations*), and a **Renew
  Solar Prism** CTA. In the panel this is `_renewSurface` / `_renewCta`
  (`ui/chat_panel.dart`); on the explore pill the look-alike opens
  `showChatRenewModal` instead of the coming-soon modal.
- **`none` + confirmed no history** → the never-entitled buy/sign-in stub
  described above.
- While the archive check is on its *first* load (nothing known yet), both
  surfaces stay in the *pending* state (panel: quiet loader; pill: inert
  look-alike) — the buy stub never flashes before the fork settles. A reload that
  retains a prior value or error is not pending (it answers from what it has).

The archive signal can go stale while warm: `hasConversationsProvider` is
`autoDispose` but the always-mounted account button keeps it subscribed, so it
can cache `false` for a user before their first conversation. The server mints a
session-new conversation the moment it **accepts that conversation's first turn**
— the conversation POST precedes the turn stream — so `ChatTurnNotifier`
refreshes the archive signal from *any* accepted turn, guarded once per
conversation id (`_reflectConversationMint`, `lib/state/chat_turn.dart`, called
from `_onEvent`/`_onStreamError`/`_onStreamDone`). This covers the paths a
non-empty-completion-only refresh missed — a first turn that is **cancelled,
errors, or completes with no deltas** still mints an archive row, so refreshing
only on completion would let a later New Chat + 403 read the stale `false` and
revert to the buy stub (adityas/ai/198 finding B, completing adityas/42/ai/197,
which refreshed only on `_finish`). A resumed thread is already in the archive,
so `resumeConversation` pre-seeds its id to suppress a redundant refetch.

This also cures a **flash-then-revert**: a mid-session 403 latches
`TurnAccessLapsed` (renew bubble) *and* invalidates entitlement; when the refetch
returns a cleared `access_until`, access flips `lapsed → none`, which used to swap
the conversation for the buy stub mid-read. Routing `none`-with-history to the
renew surface resolves that invalidate into a renew prompt instead. (Signed-out
users have no history — `hasConversationsProvider` short-circuits to `false` — so
they stay on the sign-in gate.)

**Post-purchase refresh.** A buy/renew CTA opens the shop in a new tab, so on
return the app refetches entitlement on the tab-visibility signal
(`onTabVisible` → `ref.invalidate(entitlementProvider)`, `main.dart`) — the gate
resolves to live chat without a manual reload.

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
