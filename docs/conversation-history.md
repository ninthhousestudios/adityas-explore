# Conversation History

How a user browses, resumes, downloads, and deletes past AI chat conversations,
and the session-organization decisions that shape it. Companion to
[`chat-surface.md`](chat-surface.md) (where chat lives on the page),
[`chat-state-architecture.md`](chat-state-architecture.md) (the client state
layer), and [`layout-modes.md`](layout-modes.md) (the panel/dock architecture).

Design task: adityas/ai/64. Desktop first; mobile is a separate pass after the
desktop UX lands (adityas/ai/90).

---

## The organizing principle: new by default, resume is deliberate

A conversation is a thread the user talks in; a new subject warrants a new
thread. The app **starts a fresh conversation on every app load and every chart
load** — this is live today (`SseTurnTransport._conversationId` is minted lazily
on the first turn, cached in memory, never persisted; reset on user change).
Past conversations are not auto-hydrated. Continuing one is a **deliberate,
mildly discouraged opt-in** through the picker, because resuming a long thread
costs more (history is resent every turn) and degrades output quality — and the
typical user does not grasp that. The UX makes new-chat the frictionless path and
resume the explicit one.

### Conversations are NOT linked to a chart

Deliberate. A conversation carries a **creation-time chart-name snapshot** used
only as a human-readable label in the list — it is **not** a binding. Resuming a
conversation never loads, changes, or restores a chart. The intended (if
uncommon) flow: a user exploring a topic opens a *different* chart and resumes the
*same* conversation to carry the thinking across. The current chart is ambient
context, not a property of the thread.

- **`chart_facts` always reports the currently-loaded chart**, never a chart
  stored on the conversation. This is how the model notices the chart changed
  mid-thread. Enforcing this is an orchestration / knowledge-layer concern (lives
  with the `chart_facts` operation and the TurnEngine, not with picker work); it
  is a constraint on that code, called out here so it is not lost.

---

## Settled decisions

Carried forward from `../ai/docs/ai-chat-tier1-notes.md § Open questions` and the
ai/64 design session. Do not re-litigate.

| # | Decision |
|---|---|
| **Concurrency** | One explore app = one chat window = one active conversation. Two windows (two explore apps) = two conversations, no conflict — each mints its own id on first turn. No multiple concurrent conversations inside one app. |
| **Lapse retention** | On access lapse, conversations become **read-only for 6 months** (clock starts at `access_until`; resubscribing inside the window restores write access). At lapse + 6 months, a scheduled backend job **crypto-shreds the per-conversation data key** — irreversible deletion. |
| **Titles** | `{chart-name snapshot} · {date}`, deterministic and free, generated at conversation creation. **No LLM-generated titles in v1** (unclear they'd ever be worth the extra cheap call + prompt + failure path). **Manual rename ships in v1** — the `title` column is user-editable. |
| **Length cap + compaction** | Silent automatic compaction + an inline honesty marker. No blocking popup. See § Compaction. |
| **Delete** | Truly deletes, **per conversation**, by crypto-shredding that one conversation's data key. Never deletes all of a user's conversations at once (that is account deletion, a separate flow). No "archive" in v1. |
| **New by default** | Fresh conversation on every app load and every chart load. Already live per app-load; the per-chart rotate is the ai/64 decision. |

### Privacy mechanism (settled upstream, load-bearing here)

Envelope encryption: a per-conversation data key encrypts the content, wrapped by
a server-held master key. **The load path is a plain authenticated fetch of
server-decrypted plaintext over TLS — not client-side crypto.** Delete =
destroying the data key (crypto-shredding); it makes the honest "this is gone,
even from backups" possible and is *why* delete is real rather than a UI flag.

---

## Compaction (the length cap) — when and how

Refines adityas/ai/27. The user-facing decision is: **do not ask the naive user
to adjudicate token economics.** No modal offering "resume from summary / start
new" — that hands the steering wheel to the user this whole design protects.

- **Budget is conversation-message tokens only** — user turns + assistant
  replies. The stable system prefix (~14k, cached) is **not** counted; compaction
  never touches it. So the threshold is about accumulated *history*, which at
  ~30k tokens is dozens of turns, not two.
- **Trigger:** checked server-side **before sending each new turn**. When
  estimated history tokens cross the threshold, summarize the **older half** with
  the cheap model and replace it, keeping recent turns verbatim.
- **Honesty marker, not a decision point:** insert a subtle inline divider at the
  compaction seam in the transcript — e.g. *"Earlier messages condensed to keep
  this focused."* Non-blocking, no buttons. This keeps the AI "forgetting" detail
  from being mysterious without interrupting.
- **No live-history nudge in v1.** The earlier "~60k → suggest a fresh start"
  idea is dropped: compaction pins *live* history near the compact threshold by
  construction (compact the older half at ~30k → oscillate ~18k–30k forever), so
  a live-history ceiling of 60k is never reached and would be dead code. The only
  thing a "start fresh" nudge could address is **fidelity decay from repeated
  re-summarization** (each cycle folds the prior summary back into the older half
  and re-summarizes it — a telephone game), which is a function of *cumulative*
  conversation tokens / compaction-cycle count, not live size. We have no eval
  evidence that decay bites in practice, and the new-by-default UX makes deep
  multi-cycle threads rare, so we ship compaction alone and revisit a
  cumulative-based nudge only if decay is observed. See adityas/ai/27 decision.
- **Numbers are config, provisional:** starting point ~30k history tokens to
  compact the older half, keeping recent turns verbatim. Config surface is the
  compact threshold + retention ratio + the summarizer model (below) — **no
  nudge threshold.** Tune against the eval set + budget post-launch (I29).
- **Summarizer model:** compaction summarizes with **`gemini-flash-3.1-lite`**,
  configured **independently** of the main turn model and the crisis-identifier
  model — three separate model settings so each can move without touching the
  others. The compaction event logs the model that produced the summary (it may
  differ from the turn model).

---

## Picker UX/UI

### Entry point — account menu

Add a **"Conversations"** item to the account `PopupMenuButton` (upper-right,
`account_button.dart`), slotted between "My Charts" and the account/sign-out
divider. Icon `Icons.forum`. Shown only when the user has ≥1 conversation or is
entitled (no dead item for someone who's never chatted).

### The modal

Mirror `_MyChartsDialog` exactly — centered card, `cardBg`, radius 16, 30%-border,
close X, most-recent-first `ListView.separated`. Reuse that skeleton.

- **Sort:** most recent (last-turn time) at top.
- **Row content:** title line (`chart · date`, or the renamed title) + a secondary
  line with relative time. May show a soft "long conversation" hint from turn
  count — **never a dollar or token amount** (no-meter invariant).
- **Empty state:** mirror My Charts' empty copy.
- **No search in v1.** Titles are weak search targets and counts will be modest
  under new-by-default. Add a client-side title filter only once users
  accumulate large lists.

### Row actions — three options shown together (deliberate)

Each row exposes **Resume, Download, Delete as three visible options** (not
tap-to-resume). This is intentional friction: making resume a single tap would
undercut the "resume is the discouraged path" principle. The extra choice is the
point.

- **Resume** — loads the decrypted transcript into the panel and sets the
  transport's conversation id to the loaded one, then **sends nothing until the
  user types**. Reading-only (open it, re-read it, never continue) is a valid end
  state. If the loaded thread is already long, it inherits the compaction
  state. Does **not** touch the chart (see § Conversations are NOT linked).
- **Download** — a **branded PDF** rendered server-side via Typst
  (`GET …/export.pdf`). No markdown/text export — most customers don't know what
  markdown is.
- **Delete** — irreversible crypto-shred; requires a **confirm dialog** ("This
  permanently deletes this conversation. It can't be recovered."). Deleting the
  *currently active* conversation resets the panel to a fresh conversation.

### Rename (v1)

A rename affordance per row (inline edit or a small dialog) writes the user's
string to the `title` column. Ships in v1; sits *before* any future LLM-title
work.

---

## New Chat affordance

A **"＋ New"** control in the **ChatPanel header** (conversation mode) — the
canonical spot. It rotates the conversation *without* changing the chart:
fresh message buffer + fresh durable conversation id, prior thread archived and
resumable only through the picker. Covers "same chart, fresh thread" (topic
change, or the current thread got long) — distinct from New Chart, which rotates
the conversation as a side effect of changing the subject.

- **Not** on the explore-mode composer pill — the pill *continues* the current
  thread (per `chat-surface.md`); a New Chat control there would fight that.
- Starting a new chat while a turn is streaming must **cancel the stream
  server-side** (still billed) or confirm — never silently orphan an in-flight
  generation.

---

## Lapse presentation in the picker

Within the 6-month read-only window (client UX owned by adityas/ai/18):

- The Conversations modal still lists everything.
- "Resume" still opens the transcript, but the composer is disabled with the
  renew/gated presentation (`chatAvailable` false) — read + Download only, no new
  turns.
- Keep this in sync with ai/18's lapsed-read-only state and the gated-composer
  copy source in `chat-surface.md`.

---

## Backend contract the client needs

Filed as adityas/ai/87 (list/get) and adityas/ai/88 (PDF export); retention job
as adityas/ai/89.

- **`GET /v1/ai/conversations`** — list for the authenticated user. Per item:
  `id`, `title`, `updated_at` (last-turn time), optional turn count. Sorted
  recent-first. Include a `limit` + cursor even if v1 rarely needs it. **Only
  conversations with ≥1 turn appear** — the row is created lazily on first turn,
  so empty app-loads/chart-loads never produce ghost rows.
- **`GET /v1/ai/conversations/{id}`** — decrypted history (server unwraps the data
  key with the master key, returns plaintext over TLS). Feeds Resume.
- **`PATCH /v1/ai/conversations/{id}`** (or equivalent) — set `title` (rename).
- **`DELETE /v1/ai/conversations/{id}`** — crypto-shred this conversation's data
  key; keep the content-free metadata stub (timestamps, counts) for accounting,
  marked deleted; billing ledger is append-only and untouched.
- **`GET /v1/ai/conversations/{id}/export.pdf`** — branded PDF via Typst.

---

## Client seam to change

Today `SseTurnTransport._conversationId` can only be **self-minted**
(`sse_turn_transport.dart:123`). Resume needs it **externally settable** to a
loaded id so a continued thread appends to the right server conversation. Note
this for the client implementation task (adityas/ai/86 — picker + wiring).

---

## Follow-up tasks

| Task | Scope |
|---|---|
| adityas/ai/86 | **Client:** Conversations picker modal (account menu), three-option rows, Resume + settable conversation id seam, rename, delete + confirm, New Chat header button, lapse presentation. |
| adityas/ai/87 | **Backend:** `list` + `get(history)` + `rename` + `delete` (crypto-shred) endpoints; lazy-create on first turn; content-free metadata stub on delete. |
| adityas/ai/88 | **Backend:** branded Typst PDF export template + `export.pdf` endpoint. |
| adityas/ai/89 | **Backend/ops:** lapse read-only window + scheduled crypto-shred job at lapse + 6mo; resubscribe-restores-write. |
| adityas/ai/90 | **Mobile:** adapt + test all of the above on mobile web, after desktop (ai/86) lands. |
| adityas/ai/27 | **Backend (exists):** compaction + length cap — refined with the silent + inline-marker + history-token-trigger decisions above. |
| adityas/ai/18 | **Client (exists):** owns lapsed read-only + `chatAvailable` gating the picker presents. |
</content>
