# Enforcement ledger — explore

Routing table for every architectural constraint in the explore Flutter app.
**Backfilled** from `.sutra/rules.toml` provenance at the adityas/ai/13 tend
(2026-08-30): explore was sutra-*adopted* (reconstructed from the import graph),
not seeded from a PRD, so this ledger is built from the adopted rules rather than
from PRD claims. Every `.sutra/rules.toml` constraint has a row here; new rules
append with their provenance. When an accepted exception is added, record it in
(b).

## (a) Live sutra constraints — guard-enforced

| Constraint | Kind | Boundary | Provenance |
|---|---|---|---|
| `astro-no-ui` | forbidden_dep | `lib/astro` ↛ `lib/ui` | adopt:explore — calc engine sits below presentation |
| `api-no-ui` | forbidden_dep | `lib/api` ↛ `lib/ui` | adopt:explore — external services sit below presentation |
| `ui-no-raw-swe` | forbidden_dep | `lib/ui` ↛ `lib/astro/swe*.dart` | doc:docs/chart-wheel.md — UI goes through chart_calculator, never raw Swiss Ephemeris |
| `state-no-sse-wire` | forbidden_dep | `lib/state` ↛ `lib/ai/sse*.dart` | checkpoint:adityas/ai/13 — state reaches the transport only via its injected `TurnTransport` interface; the shared `chat_access` gate is exempt |
| `api-no-cycles` | no_cycles | `lib/api` acyclic | adopt:explore |
| `astro-no-cycles` | no_cycles | `lib/astro` acyclic (1 accepted) | checkpoint:adityas/ai/13 — names the ephemeris conditional-import cycle so it accepts against a real rule (see (b)) |
| `being-uncertainty-fan-in` | max_fan_in (advisory) | `being_uncertainty.dart` ≤ 12 | adopt:explore — domain-logic hub, current 9 |
| `turn-transport-fan-in` | max_fan_in (advisory) | `turn_transport.dart` ≤ 8 | checkpoint:adityas/ai/13 — chat-layer seam (TurnEvent/TurnTransport), current 5-6 |
| `no-ignore-comments` | forbidden_pattern | no `// ignore:` in `lib/` | house analysis_options.yaml baseline; vidhi/language-rules/dart.toml |
| `gpt-markdown-swap-seam` | confined_external | `gpt_markdown` only in `lib/ui/message_markdown.dart` | checkpoint:adityas/ai/13 — ai/12 one-file renderer swap seam. First confined_external in this repo (confirmed working for a Dart package) |

## (b) Accepted exceptions — `.sutra/accepted.toml`

| Exception | Constraint | Rationale |
|---|---|---|
| `ephemeris_service.dart` ↔ `ephemeris_service_native.dart` | `astro-no-cycles` (ack) | Dart platform-conditional import (`dart.library.js_interop`): the native impl implements the abstract `EphemerisService`. Structural, not architectural. |

## (c) Not expressible in sutra — house analyzer baseline

- **`analysis_options.yaml`** mirrors the canonical `vidhi-dart` baseline
  (flutter_lints variant; strict-casts / strict-inference / strict-raw-types;
  `prefer_const_*`, `cascade_invocations`, `only_throw_errors`, `avoid_print`).
  The analyzer enforces the const-constructor, cascade, and collection-operator
  discipline that the catalog (`dart.toml`) deliberately routes to the analyzer
  rather than to a sutra rule.

## Deferred — catalog guards not yet adopted

| Rule (vidhi/language-rules/dart.toml) | Trigger | Tracked |
|---|---|---|
| `no-dynamic-type`, `no-bang-null-assertion`, `no-silent-empty-catch` | measure the full-`lib/` surface, then adopt blocking | **adityas/explore/57** |

## Checkpoint adityas/ai/13 — durable-chat state-layer tend (2026-08-30)

First tend touching `lib/state` + `lib/ai` (the chat-state layer, ai/12 / ai/60),
folding the ai/60 review. All new rules zero-violation at adoption.

- **Added:** `state-no-sse-wire`, `astro-no-cycles`, `turn-transport-fan-in`,
  `gpt-markdown-swap-seam`. The astro cycle is ack'd (b).
- **`state-no-sse-wire` was narrowed at the tend.** The initial proposal
  (`lib/state ↛ lib/ai` wholesale) had a real violation the exploration missed:
  `state/entitlement.dart → ai/chat_access.dart`. `chat_access` is the chat
  *allowlist* gate (an entitlement helper that imports `state/auth`), not the
  wire. Narrowed to the SSE wire (`sse*.dart`), mirroring `ui-no-raw-swe`. The
  `chat_access` placement (it arguably belongs in `lib/state`) is left to a later
  pass, not forced by a guard.
- **Rule health:** the `.sutra/accepted.toml` entry keyed on `builtin:cycles`
  (not a rule name) was stranded — it suppressed nothing and sutra warned about it
  every run. Fixed by naming `astro-no-cycles` and re-accepting the cycle against
  it.
- **Drift fixed (docstrings):** `sse_turn_transport.dart` overclaimed client-side
  "persistence" — resume is server-durable + an in-memory cursor, and does NOT
  survive an app relaunch; `turn_transport.dart` claimed "no production impl / the
  chat panel is a stub" — both false (main.dart injects a live `SseTurnTransport`,
  `chat_panel` wires it).
- **FCA:** all mined conventions are structural tautologies (`vis:private ⇔
  in:lib` at 100% — a Rust-shaped visibility model misapplied to Dart); nothing
  promotable. `sutra_dead`'s 16 "dead" symbols in `chat_turn.dart` are tear-off
  false positives (the resolver doesn't track `listen(_onEvent, …)` edges).
- **I11 (review gate):** resume verified across widget unmount (keepAlive
  notifier) + transient reconnect; app-relaunch durability rides on
  adityas/ai/64.

## Mechanics (so the next tend doesn't relearn them)

- **`forbidden_pattern` / `no_cycles` `scope` is a literal path PREFIX** — `lib/`
  works; `**/` and `*/…` bind nothing.
- **`confined_external` works for Dart packages** (pubspec + `package:` import),
  not just Cargo crates — verified with `gpt_markdown`.
- **A `no_cycles` acceptance** is an `[[ack]]` keyed on the cycle's member
  file-set + the constraint *name*; a waiver keyed on a non-existent constraint
  name (e.g. the builtin detector's id) strands silently.
