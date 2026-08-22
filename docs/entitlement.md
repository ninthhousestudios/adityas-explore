# Entitlement layer

The client state that decides whether to offer AI chat. Step 2 of the chat
state migration (`docs/chat-state-architecture.md`, task adityas/explore/43).

## What it is

`access_until` is the whole entitlement model — a single timestamp, read from
the backend DB, never from JWT claims. One-time purchases (and a future opt-in
subscription) extend it; the chat gate reads only this one field.

- `Entitlement` (`lib/api/chart_service.dart`) — `{ accessUntil: DateTime? }`.
  `null` = no active access window.
- `entitlementProvider` (`lib/state/entitlement.dart`) — `AsyncNotifier`,
  autoDispose, auth-keyed. Watches `authProvider`: a sign-out rebuilds to
  `Entitlement.none()`; a sign-in refetches. Riverpod 3 build auto-retry is on
  (a transient fetch failure self-heals). Invalidate it on a purchase/webhook
  signal to pull a fresh window.
- `chatAvailableProvider` — derived `Provider<bool>`: signed in AND
  `access_until > clock.now()`. The clock is injected (`clockProvider`) so
  expiry is deterministically testable.

**UX gate only.** `chatAvailableProvider` decides whether to *show* the chat
entry point. It is not the security boundary — the authoritative entitlement
check runs server-side at the chat endpoint. A non-null `access_until` here is
not proof the backend will serve a turn.

## Wire contract (frozen with adityas/backend)

- `GET /v1/entitlement`
- Auth: `Authorization: Bearer <JWT>` (same extractor as `/v1/charts`). 401
  without a valid token.
- 200 body: `{ "access_until": "<RFC3339>" | null }`, UTC (e.g.
  `2026-09-21T15:30:00Z`). `null` = no active window.
- Past timestamps are returned **verbatim, not nulled** — the client's
  `now < access_until` check is what expires them.
- Forward-compatible: unknown fields (a future `budget_remaining`, etc.) are
  ignored; the shape won't bump.

Backend follow-up: nothing writes `access_until` yet — the purchase→extend
wiring is `adityas/backend/45`. Until it lands, the endpoint returns `null` for
every user (the acceptable "stub returns null" state).

## Testing

**Headless (deterministic, no network):** `test/state/entitlement_test.dart`.
Injects a fake `EntitlementClient` and an advanceable `Clock`; proves the
clock crossing `access_until` flips `chatAvailable` to false. Run:
`flutter test test/state/entitlement_test.dart`.

**Local integration** (once a chat entry point exists — task /44): point the
client at a locally-run backend and seed a row.

1. Backend (in `../backend`): run against a **local** Postgres (not live
   Supabase), keeping `JWKS_URL` at the real Supabase project so real login
   tokens validate:
   ```
   DATABASE_URL=postgres://josh@localhost/postgres \
   JWKS_URL=https://<project>.supabase.co/auth/v1/.well-known/jwks.json \
   cargo run -p server
   ```
   Migrate once first (`scripts/setup-local-db.sql` then
   `sqlx migrate run --source migrations`). Seed your user:
   ```sql
   INSERT INTO public.entitlements (user_id, access_until)
   VALUES ('<your-jwt-sub-uuid>', now() + interval '30 days');
   ```
   Use a past interval to test the expired path.
2. Client: run against it —
   `flutter run -d chrome --dart-define API_BASE_URL=http://localhost:3000`.
