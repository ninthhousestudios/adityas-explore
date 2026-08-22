# Chat State Architecture

Client-side state layer for the AI chat feature in `explore/`. This document
covers **only the state/observation layer** — the reactive machinery the UI
watches — and the migration that gets us there. It is roughly 15% of the client
chat work.

**What this is not:** the chat product spec. The chat feature does not yet have
its own PRD; that comes *after* this machinery is in place. We are laying the
reactive foundation the chat will need, modelled from the tier-1 design notes,
so the PRD can be built on top of it rather than around `setState`. Where this
doc enumerates chat-specific shape (the `ChatTurn` state machine, the
conversation model), treat it as the current best model from
[`../ai/docs/ai-chat-tier1-notes.md`](../../ai/docs/ai-chat-tier1-notes.md), to
be reconciled with the PRD when it lands — not a frozen contract.

Read alongside:

- [`../ai/docs/ai-chat-tier1-notes.md`](../../ai/docs/ai-chat-tier1-notes.md) —
  the "why" (durable server-side generation, billing rules, `show_being`,
  transport). The § *Client notes* and § *Transport and generation* sections are
  the source for most decisions below.
- [`layout-modes.md`](layout-modes.md) — the desktop layout is state-driven
  (`LayoutMode`, `PanelId`, docked vs floating layers). The overlay/popup ripple
  (below) interacts with it directly.

---

## Why out-of-tree reactive state at all

`explore/` is pure `setState` today. `_ExploreAppState` (`lib/main.dart`) is a
God-object that prop-drills ~20 fields and callbacks into `_ExplorePage`. Auth is
subscribed **three independent times** — `_ExploreAppState._authSub`
(`main.dart:154`), `_AccountButtonState._authSub` (`account_button.dart:35`), and
`_SignInDialogState._authSub` (`account_button.dart:166`) — each its own
`auth.onAuthStateChange.listen(...)`.

That is a smell, not a crisis. The crisis is `ChatPanel`: it is mounted
conditionally — `if (g.chatOpacity > 0.01)` in `_ChartWheelState.build`
(`chart_wheel.dart:363`) — so **any conversation or stream state held in the
panel's `State` is destroyed on a layout-mode switch.** That is a correctness
problem, not a style one, and it is what forces reactive state that lives
*outside* the widget tree. Four concrete drivers, from the tier-1 notes:

1. A generation is a **durable server-side job** the client attaches to
   (resumable via `Last-Event-ID`). The process outlives every widget and must
   survive `ChatPanel` unmounting on a mode switch.
2. Token deltas are throttled to a frame budget — this needs **scoped rebuilds**
   (only the streaming-text widget), not one `setState` on a fat `State` that
   rebuilds the whole panel.
3. Tool-driven UI: `show_being(slug)` must open the existing transient overlay,
   which was `_ChartWheelState._popupStack` / `_openPopup` widget state (lifted
   to `overlayControllerProvider` in /45). The stream handler needs to reach it
   **without callback-threading**.
4. Entitlement is a single `access_until` timestamp read from the backend DB
   (never JWT claims), cached and invalidatable. `chatAvailable` is derived from
   auth + entitlement, and expiry mid-stream is a real application state.

Plus: unforgiving billing (no refund on cancel, usage-at-end-or-never, expiry
mid-turn) makes **headless state-machine testability** — `ProviderContainer` +
injected transport/clock — a requirement, not a luxury.

---

## Decision: Riverpod 3, hand-written notifiers

**Adopt `flutter_riverpod: ^3.0.0`.** Scoped to auth / entitlement / chat /
overlay. Everything else stays `setState`.

**Riverpod 3, not 2** — this is a deliberate version pin, and v3 changes the
design (see § *The v3 pause trap* below). SDK `^3.12.0` is well clear of v3's
floor. Package is `flutter_riverpod` only — **not** `hooks_riverpod` (we don't
use `flutter_hooks`), and **not** `riverpod_generator`/`build_runner` (see
§ *Codegen*).

**Strongest rejected alternative: `provider` + `ChangeNotifier`.** It works, and
it bites on exactly the two things this design does most:

- **Reading/writing state from the SSE async callback with no `BuildContext`.**
  A Riverpod `Notifier` holds `ref` and drives state from a bare async callback;
  v3's unified `Ref` (no per-provider `FooRef`) and `ref.mounted` make the
  post-`await` guard clean. `ChangeNotifier` wants a `context` to reach other
  state, which is precisely what the detached stream handler does not have.
- **Lifecycle.** keepAlive-across-mode-switch vs autoDispose-on-sign-out is a
  first-class Riverpod concept and a manual bookkeeping chore with
  `ChangeNotifier`.

**Also rejected: stay pure `setState`.** It cannot hold a stream that outlives a
conditionally-mounted panel. This is the disqualifier, full stop.

---

## The v3 pause trap (load-bearing)

Riverpod 3 **pauses a provider's subscription when nothing is actively listening**
— and explicitly, *"StreamProvider now pauses its StreamSubscription when the
provider is not actively listened."* A provider is also paused if all its
listeners are themselves paused.
([whats_new](https://riverpod.dev/docs/whats_new),
[riverpod#1344](https://github.com/rrousselGit/riverpod/issues/1344))

This collides head-on with driver #1. `ChatPanel` unmounts on a mode switch, so
its `ref.watch`es are **removed from the tree**, not merely hidden. Consequences,
and the rules they impose:

- **The turn must NOT be a `StreamProvider`.** Model it as a
  `NotifierProvider`, `keepAlive`'d, owning an **imperative** `StreamSubscription`
  — the manual `fetch`+`ReadableStream` (web) / `dart:io` (desktop) parse, not a
  Riverpod-managed stream. keepAlive prevents disposal on unmount; the imperative
  subscription keeps filling the delta buffer with zero widget listeners. A
  `StreamProvider` here would silently pause mid-generation on a mode switch —
  the exact bug out-of-tree state exists to prevent.

- **Correctness is server-side, not client-side.** The generation is a durable
  append-only log with a `Last-Event-ID` cursor. If the client notifier is ever
  dropped or paused, on remount it re-attaches and resumes from the cursor.
  keepAlive + imperative subscription is the **UX optimization** (no gap, no
  re-fetch on every mode toggle); the cursor is the **correctness backstop**. We
  do not have to win the fight against Riverpod's lifecycle to be correct.

- **Keep Riverpod's build-retry away from the turn.** v3 auto-retries a failing
  provider's `build` (200 ms → 6.4 s backoff) and wraps errors in
  `ProviderException`. We do not want that racing our own reconnect /
  `Last-Event-ID` logic — another reason the turn is an imperative Notifier, not
  an async-`build` provider whose thrown error trips Riverpod's retry.
  Build-retry is *welcome* on `entitlementProvider`, where a transient fetch
  failure should self-heal.

---

## Provider surface

| Provider | v3 type | Source | Lifecycle |
|---|---|---|---|
| `authProvider` | `StreamProvider<AuthState>` (or thin `Notifier` exposing `User?`) | `Supabase.instance.client.auth.onAuthStateChange` | keepAlive. Always has a live watcher (the account button is always mounted), so pause is a non-issue here. Collapses the **3** current subscriptions → 1. |
| `entitlementProvider` | `AsyncNotifier<Entitlement>` | backend DB (`access_until`), **never JWT** | autoDispose on sign-out; invalidatable on webhook/expiry; auto-retry welcome |
| `chatAvailableProvider` | derived `Provider<bool>` | `authProvider` valid && `access_until > clock.now()` | follows its deps; clock injected for testability |
| `conversationProvider` | `NotifierProvider` | message list — tree in the model (`parent_message_id`), linear in the v1 UI | **keepAlive** (survive mode switch); dispose on sign-out. One active conversation per explore app. |
| `chatTurnProvider` | **`NotifierProvider`, keepAlive, imperative subscription** | injected transport | the state machine below. **Never a `StreamProvider`.** |
| `overlayControllerProvider` | `NotifierProvider` | the popup/floating layer | keepAlive. The `show_being` target — see § *Overlay ripple*. |

Notes:

- **Unified `Ref`** (v3) is the enabler for the detached stream handler: the
  notifier holds `ref`, mutates state from the async callback with no
  `BuildContext`, and guards post-`await` writes with `ref.mounted`.
- **`chatAvailableProvider` is derived, never stored.** Auth OR entitlement
  changing recomputes it; expiry mid-stream flows through it as a state change
  the turn can observe.

---

## `ChatTurn` sealed state machine

```
idle → connecting → streaming ⇄ reconnecting
                       │  │
                       │  ├→ cancelled   (client stop → server-side stop; usage still billed)
                       │  ├→ error       (terminal-with-retry; carries last cursor)
                       │  └→ done
```

A sealed class hierarchy (`idle` / `connecting` / `streaming` / `reconnecting` /
`done` / `error` / `cancelled`), exhaustively matched.

- **Delta buffer + `Last-Event-ID` cursor live in the Notifier**, not the widget.
  `reconnecting` replays from the cursor. The buffer is the streaming text
  accumulated so far; the cursor is the resume point.
- **cancel → server-side stop**, not merely closing the client stream — or we
  keep paying (tier-1 notes, § Client notes). Cancel does not refund; a stopped
  turn still writes a usage event. This is a transition with a network side
  effect, not a local flag flip.
- **Frame-budget throttle on the delta sink** (not `setState`-per-token). Only
  the streaming-text widget rebuilds; the message list and panel chrome do not.
- **The client must ignore unknown event types** — `explore` is a shipped binary
  and old versions must survive new SSE event types (tier-1 notes).
- Model the turn's transport events as an **internal event enum**, not any
  vendor's JSON — mirrors the backend adapter discipline.

---

## Lifecycle policy

- `conversationProvider` and `chatTurnProvider`: **keepAlive** — a conversation
  and an in-flight turn survive a mode switch (`conversation` → `explore` →
  back).
- Everything auth-derived (`entitlementProvider`, and the conversation on
  sign-out): **autoDispose / invalidate on sign-out** — signing out must not
  leave another user's conversation or entitlement resident.
- `authProvider`, `overlayControllerProvider`: keepAlive (app-lifetime).

The invariant: **a conversation outlives a mode switch but not a sign-out.**

---

## Testability seam

Billing/expiry/cancel transitions must be unit-testable headless. The seam:

- **Transport injected** behind an interface (a `TurnTransport` that yields the
  internal event enum). Tests supply a fake that emits scripted
  `delta`/`usage`/`error`/`done` sequences, including mid-stream expiry and
  broken-stream (no `usage`) cases.
- **Clock injected** so `chatAvailableProvider` expiry and any timeout/backoff is
  deterministic.
- Every transition is exercised via `ProviderContainer` with overrides — no
  widgets, no real network, no wall clock. This is why the transport is an
  interface from day one and not folded into the Notifier.

---

## Overlay ripple (decision: define the seam, defer the lift)

`show_being(slug)` wants to open the existing transient popup, which today is
`_ChartWheelState._popupStack` + `_openPopup` — **widget state**, reachable only
by callback-threading. The clean answer is to lift the popup stack into
`overlayControllerProvider` so the stream handler drives it directly.

**Decision: define `overlayControllerProvider` as the target seam now, but make
the actual lift its own task, sequenced last and low priority.** Rationale: the
tier-1 notes mark `show_being` as *design-for, not build-now* ("not sure how this
will actually work or if I want this exactly. regardless, we should design with
the possibility in mind"). Chat MVP ships without it. Front-loading a
`_ChartWheelState` refactor — which is `layout-modes.md` territory (the transient
popup layer, `_buildOverlay`, `FloatingConfig`, drag/resize) — for a capability
we haven't committed to is the wrong trade.

**Rejected: lift `_popupStack` as part of the chat work.** It couples the
streaming feature to a layout refactor and blocks a shippable chat on an
uncommitted AI-driven-UI feature.

**Landed (task /45).** `overlayControllerProvider` (`lib/state/overlay.dart`)
owns the popup stack + floating-window geometry; `_ChartWheelState` watches it
and drives it through the notifier (`open` / `push` / `pop` / `close` / `drag` /
`resize`). The transient-vs-persistent split in `layout-modes.md` is unchanged —
this moved *where the transient stack lives*, not the two-layer rule.

The `show_being` seam is **ready but not driven**:
`OverlayController.showBeing(BeingRef)` opens a `BeingFromName` popup with no
`BuildContext`, callable from the chat stream handler (a Notifier holding
`ref`). It stays dormant because `ToolEndEvent`
(`lib/state/turn_transport.dart`) carries only the tool *name*, not its
arguments — so there is no being to resolve yet. Wiring the dispatch needs the
transport to carry tool args (the sibling SSE task) and the chat PRD to fix the
being identifier's shape. The dispatch point is marked in `chat_turn.dart`'s
`ToolEndEvent` handler.

---

## `setState` stays — explicit boundary

Only auth / entitlement / chat / overlay move to Riverpod. These **do not**:

- `birth_form` and all its field state.
- All dialogs (`_SignInDialog`, `_SaveChartDialog`, `_MyChartsDialog`) and their
  `_loading` / `_message` / `_isError` flags.
- `_zoom` (and min/max/step), theme (`_useLight`).
- Hover state (`_hoveredPlanet`, `_hoveredCusp`).
- Chart calculation state (`_chartData`, `_chart`, `_uncertainty`,
  `_calculating`, `_calcToken`), PDF export (`_exportingPdf`), boot
  (`_booted`, `_bootError`), and the messenger/navigator keys.

This is **not a big-bang migration of the God-object.** Auth and its saved-charts
reaction move; the rest of `_ExploreAppState` stays as-is.

---

## Codegen: hand-written first

Start with hand-written `Notifier` / `AsyncNotifier`. No `riverpod_generator`,
no `build_runner`. In v3, `AutoDisposeNotifier` and friends are gone — you extend
`Notifier` / `AsyncNotifier` and express disposal at provider construction, so
the hand-written surface is small.

**Trigger to revisit:** when provider boilerplate becomes a maintenance tax, or
when we want compile-time-safe families (e.g. per-conversation providers keyed by
id). Adopting codegen later is additive — it does not invalidate hand-written
providers.

---

## Migration sequence (auth-first, each step independently shippable)

Tracked as `adityas/explore` tasks /42–/45. This doc is the shared fundamentals;
each task carries its own implementation plan.

1. **/42 — Riverpod 3 foundation + unified `authProvider`.** Add
   `flutter_riverpod: ^3.0.0`, wrap the app in `ProviderScope`, create
   `authProvider`, and collapse the 3 `onAuthStateChange` subscriptions to one
   watcher each in `_ExploreAppState`, `_AccountButtonState`, `_SignInDialogState`.
   Move the saved-charts refresh to react to `authProvider`. **Standalone win,
   independent of chat** — banks the 3-subscription cleanup on its own.
2. **/43 — `entitlementProvider` + `chatAvailableProvider`.** Async
   entitlement from the backend `access_until`, invalidatable; derived
   `chatAvailable`; clock injected. Depends on /42. Cross-repo dependency: a
   backend endpoint that returns `access_until` (see § *Depends on / out of
   scope*).
3. **/44 — Conversation + `ChatTurn` state machine.** The providers and sealed
   state machine above, with transport + clock **injected** and headless tests.
   **Excludes the real SSE wire** — that is the sibling transport task. Depends
   on /42 and /43. Reconcile the state/transition set with the chat PRD when it
   lands.
4. **/45 — Overlay controller lift + `show_being` seam.** Lift `_popupStack`
   into `overlayControllerProvider`; wire the tool-call path. Depends on /44.
   Deferrable / low priority (see § *Overlay ripple*).

`explore/39` ("Gate stub chat / conversation mode until real chat lands") is
resolved when /44 lands.

---

## Depends on / out of scope

Necessary siblings this plan deliberately does **not** cover (noted so the graph
is honest; filed separately, mostly under `adityas/backend`):

- **SSE transport** — `fetch`+`ReadableStream` (web) / `dart:io` (desktop)
  conditional-import pair, `Last-Event-ID` resume, server-side cancel, frame
  throttle. `package:http` does not stream on web (`BrowserClient` buffers to
  completion), so the streaming path needs `package:web`. Mirrors the existing
  `file_util` / `navigate` conditional-import pattern. `chatTurnProvider` consumes
  this behind the `TurnTransport` interface.
- **Backend `access_until` endpoint** + chat orchestration, metering, encryption
  — `adityas/backend`.
- **Sentry content-scrubbing** (`before_send`, no bodies) in `sentry_flutter`,
  before any chat data exists.
- **`flutter_markdown` replacement** — it is discontinued; pick a maintained
  renderer before building the message view. Render plain text while streaming,
  parse on completion (per-token markdown re-parse is the jank source).
