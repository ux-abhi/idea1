# ADR-0001: Blink Cloud, a shared server Pexilim runs

- Status: proposed, parked: to discuss with the owner before any work starts (2026-11-20)
- Date: 2026-11-20

## Context

Today every Blink user runs their own Supabase server (ARCHITECTURE §33). That is Blink's privacy promise, and it is
also the hardest step in setup: a non-technical user must make a Supabase account and an organization before Blink can
do anything. In the open beta this costs a 15-minute setup call per person, and it rules out most of the people we want.

We want a second way in: sign up inside Blink and be using it in a minute, on a server Pexilim runs, for a monthly fee.
"Your own server" stays, unchanged, for people who want it.

What the code already gives us:

- 30 of 32 tables carry `owner_id` with row-level security (each row is only ever visible to its owner), tested in
  `backend/supabase/tests/rls.sql`. That is exactly what a shared database needs.
- `model_usage` already records every AI call per owner, and `capProblem` already enforces spending limits.

What assumes one owner per server:

- `is_server_owner()` (SQL) and `isServerOwner` / `ownsServer` (`functions/_shared/owner.ts`) are true only when the
  server has exactly one profile. Nine functions refuse anyone else: chat, text, dictate, content, money, image, page,
  connections, google, mail.
- Keys and mail passwords are server-wide: `server_key` (no `owner_id`) points at Vault secrets, read by `server_keys()`
  and `secret(name)` in `functions/_shared/secrets.ts`.
- The mail worker's schedule (`x-cron-secret`) works only with exactly one owner.
- `server_info` is server-wide (fine: it describes the server, not a person).

## Decision

**One shared Supabase project in the EU (Frankfurt), run by Pexilim, using the same code as self-hosted servers.**
A server knows which mode it's in (`server_info.mode`: `self` or `cloud`). Self-hosted servers keep behaving exactly as
today; cloud mode turns on the multi-user paths below.

Rejected: one Supabase project per cloud user, created by the existing installer. It reuses the most code, but at
about $10 a month per project on a paid organization, and hundreds of projects to update and watch, it doesn't work at
€6–8 a month per user.

### 1. Who may use a function

`ownsServer(user)` becomes `mayUse(user)`:

- **self**: as today, the server's one owner.
- **cloud**: any signed-in user with a profile and an active plan (`subscription`, below). Server-wide checks in
  `google` and `mail` become per-user: each user reaches only their own links and mailboxes, which RLS already scopes.

`is_server_owner()` gets the same split for the SQL functions that use it.

### 2. Keys and mail passwords per user

- New table `user_key (owner_id, name, secret_id, updated_at)`, RLS owner-only, names readable, values never; written
  only through `set_user_key` / `remove_user_key` (security definer, like today's `set_server_key`).
- `secret(name)` becomes `secret(name, owner)`, looked up in this order:
  1. the user's own key (`user_key`),
  2. in cloud mode, Pexilim's pooled key, **only** for AI features the user's plan includes,
  3. the Edge Function environment (self-hosted servers set up the old way).
- Self mode reads `server_key` as today; nothing changes for existing servers.
- Mail passwords, the Google link and the custom AI endpoint are always the user's own; Pexilim has no pooled mailbox.

### 3. AI: included, or bring your own

- A plan includes a monthly AI allowance on Pexilim's keys (free Groq models, and a capped amount of paid ones).
  `capProblem` already sums paid spend per owner; cloud mode passes the plan's limits instead of the owner's settings.
- A user may connect their own key (Claude, OpenRouter, Groq, Sign in with ChatGPT once OpenAI approves it). Their own
  key is then used first and costs Pexilim nothing.

### 4. Background work for many users

- The mail worker's scheduled call loops over the users who have a mailbox, a few at a time, with a time budget per
  run and a per-user lock (`pg_try_advisory_lock`), so one large mailbox can't delay everyone else.
- The same pattern for any later scheduled job (morning brief, cleanup).

### 5. Sign-up, plans and payment

- Sign-ups on for the cloud project only: Sign in with Apple and email codes, with Supabase's CAPTCHA and rate limits.
- New table `subscription (owner_id, plan, status, current_period_end, provider_customer_id)`, RLS owner-read-only,
  written only by a `billing` Edge Function that verifies the payment provider's webhook signature.
- **Paddle or Lemon Squeezy** as merchant of record: they collect EU VAT and issue invoices, which plain Stripe would
  leave to Pexilim.
- Plans (to confirm): Free (own server, or cloud with bring-your-own AI), Cloud ~€6–8/month with AI included,
  Founding member for beta users.

### 6. The app

- Onboarding's first choice: **Blink Cloud** (sign up, about a minute) or **Your own server** (today's flow).
- The cloud project's address and publishable key ship in the app's build configuration (product settings, not a
  person's data; nothing personal goes in code).
- Settings › Account: plan, manage subscription, export data, delete account (cascades through `auth.users`).

### 7. Privacy and GDPR

- The privacy policy gains a cloud section: data stored in the EU, encrypted at rest, never sold, never used for ads or
  to train AI; AI requests go to the chosen provider; Google data under Limited Use as today.
- Supabase's data processing agreement in place; a record of processing; export and deletion on request (in the app).
- The self-hosted promise ("Pexilim never sees your data") stays true for self-hosted servers and is stated only there.

### 8. Security checks before anyone signs up

- `rls.sql` gains a cloud-mode block: two users with every table filled, each reading and writing only their own rows,
  including `user_key` names, `subscription` and the balance views.
- Function tests: a second user can't use the first user's keys, mailboxes, Google link or AI allowance.
- A review of every security-definer SQL function for the one-owner assumption.

## Consequences

Easier:

- Setup drops from a Supabase account plus a 15-minute call to a one-minute sign-up. Beta invites scale.
- One server to update instead of asking each user to press Update Server.
- A business model: the subscription pays for hosting and included AI.

Harder:

- Pexilim holds user data in the cloud: GDPR duties, backups, incident response, and the trust that comes with it.
- Pooled AI keys need abuse limits and monitoring; one user's spend must never become another's problem.
- Two modes to keep working; every change is tested in both (CI runs `rls.sql` in self and cloud mode).

Order of work (about 1–2 weeks for steps 2–4, a few days for 5):

1. Notarized app build (Apple Developer account) before anything public.
2. Mode flag, `mayUse`, `user_key` and per-user `secret()`; RLS and function tests in both modes.
3. Per-user mail worker and AI limits from the plan.
4. Onboarding choice and the cloud sign-up in the app.
5. `subscription`, the `billing` webhook, and Paddle or Lemon Squeezy.
6. Privacy policy, DPA, export and delete; then invite beta users to the cloud.

Revisit when the cloud passes about 1,000 active users, or Supabase costs pass about 30% of revenue: then consider
splitting heavy work (mail sync) onto its own worker or a second project.

Open questions for the owner: the price and what each plan includes; Paddle or Lemon Squeezy; Sign in with Apple only,
or email too; how large the included AI allowance is.
