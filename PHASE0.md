# Phase 0: foundation

**Done when** (ARCHITECTURE §29, §36.7): the app opens behind Face ID / Touch ID; your server accepts only your login; Blink's eye states are approved on screen; CI is green.

## Already done (cloud session)
- [x] Database: `backend/supabase/migrations/20261011000000_core.sql` (Phase 0–1 tables, owner-only security, server revisions, red actions can only be approved by a signed device challenge).
- [x] Database checks: `backend/supabase/tests/run.sh` (passes).
- [x] Project rules for Claude Code: `CLAUDE.md`. Build settings template: `apps/Blink/Config/Local.xcconfig.example`.
- [x] CI: migrations + security checks, secret scanning (`.github/workflows/ci.yml`).

## Your steps (about 15 minutes, in a browser)
1. **Supabase:** create a free account at supabase.com → New project (name `blink`, strong database password saved in your password manager, region nearest you).
2. **Database:** open SQL Editor → paste the whole of `backend/supabase/migrations/20261011000000_core.sql` → Run.
3. **Only you can log in:** Authentication › Sign In / Providers → turn **off** "Allow new users to sign up". Then Authentication › Users › Add user → your email + a strong password.
4. **Keys for the app:** Project Settings › API → copy the **Project URL** and the **publishable (anon) key**. You type these into Blink on first run; they never go in the code.
5. **Anthropic:** console.anthropic.com → create an API key and set a monthly spend limit. Keep it for Phase 1 (it goes into your server's Vault, not the app).

## On your MacBook: paste this into Claude Code (in the `idea1` folder)

```
Read CLAUDE.md, PHASE0.md, ARCHITECTURE.md §13, §14, §22, §36.1, §36.5, §36.9 and design/tokens.json.
Build Phase 0 "Mac and iPhone app" from PHASE0.md. Work in small steps, build after each step,
run the app and check it yourself before moving on. Ask me only for things you cannot do
(Apple ID sign-in in Xcode, Face ID prompts, typing my password).
```

## Mac and iPhone app (Claude Code on the Mac builds this)
1. **Project:** `apps/Blink/Blink.xcodeproj`, one multiplatform app target `Blink` (macOS 26 + iOS 26) and a local Swift package `apps/Blink/BlinkKit`. Signing from `Config/Local.xcconfig` (copy the example; your Team ID from Xcode › Settings › Accounts). Swift 6, Approachable Concurrency.
2. **Dependency:** `supabase-swift` (MIT) via Swift Package Manager; add it to `THIRD_PARTY_NOTICES.md`.
3. **First run:** "Connect your server" screen (Project URL + publishable key) → "Sign in" (email + password) → session saved in the Keychain (`AfterFirstUnlockThisDeviceOnly`) → this device registered in the `device` table → `profile` row created with the device's time zone.
4. **App lock:** on launch and after 5 minutes in the background, unlock with Face ID / Touch ID, falling back to the device passcode or Mac password (`deviceOwnerAuthentication`). Cancel keeps the lock screen; never a blank app.
5. **Home (placeholder):** "Connected to <server host> as <email>", last sync time, and a sign-out button. Server unreachable and signed-out states shown in words, not just an error.
6. **Blink eyes preview:** SwiftUI-drawn panda duo-tone eyes (no images, no Rive yet) with every mood from ARCHITECTURE §7, colours from `design/tokens.json`, motion from `motion` tokens, Reduce Motion fallback, VoiceOver label per state. A picker to switch states so you can approve them.
7. **Tests (Swift Testing):** Keychain wrapper round-trip, server URL validation, mood → colour/shape mapping.
8. **Check:** builds for "My Mac" and for an iPhone simulator; app lock works on the Mac; signing in with any other account fails; `/ponytail-review` has no must-fix items.

## Status (Mac session, 2026-10-11)
- [x] Steps 1–7 built: project, supabase-swift, first run, app lock, home, eyes preview, tests.
- [x] Builds for My Mac and the iPhone simulator; tests pass; iPhone app lock checked; a wrong account can't sign in; `/ponytail-review` must-fix fixed.
- [x] Eyes approved as a first pass; refine the look later.
- [x] Sign-ups turned off in Supabase (checked: `disable_signup = true`).
- [x] Mac signing (free team) and Mac app lock checked; Mac and iPhone each registered once.

## Phase 1 status (Mac session, 2026-10-12)
Built: notch panel (rest, peek, glance), calendar and reminders with server snapshots, T−10 / T−3 meeting cues, morning brief on first unlock, Ask-First cards with server-verified red approvals (Secure Enclave + `approve` Edge Function), menu bar entry.

Gates (ARCHITECTURE §29, §36.7):
- [x] Meeting card pops out at T−10 (and opens at T−3); morning brief on unlock. Checked on the Mac.
- [x] Ask-First works: amber reminder done; red approved only via a verified Touch ID signature; 8 bypass attempts refused.
- [x] Idle CPU ≈ 0 and 0 fps at rest (Instruments: only the designed 0.2 s blink; no timers).
- [x] `/ponytail-audit` must-fix items fixed; every shortcut has an upgrade trigger.
- [x] Reduce Motion passes. CI green (database, secrets, Swift, Edge Function tests).
- [x] First run to the notch in ~85 s on a fresh test copy (target 2 min); no meeting was on the calendar that night, so the notch showed "All clear".
- [x] VoiceOver: confirmed by the owner (2026-10-12).
- [ ] State matrix (§9.8) not formally covered; offline, signed-out, permission-denied and empty states exist.

## Phase 2 status (Mac session, 2026-10-12): done
Built: Mac window (Today, Calendar, Notes, Tasks & Habits, Waiting, Activity), notes with Groq text edits, tasks with due dates and bulk actions, Apple Reminders edit/complete/delete, habits with forgiving streaks, evening check-in that asks before planning tomorrow, chat in the notch (⌃⌥Space) with Ask-First proposals. Extras on request: Pomodoro and timers in the notch ears, clipboard history (⌃⌥V, local only, drag out).

Still to build for the Phase 2 gate (ARCHITECTURE §29):
- [x] Today timeline (one time axis for meetings, tasks and reminders) — this is the "schedule checker" the evening check-in fills.
- [x] Done ∩∩ with an Undo chip in the notch and the window (ticking off; deletes still ask first).
- [x] Spaces (Segments), Project template first: migration + RLS tests (live), sidebar, Space page, Move to Space for tasks and notes.
- [x] Blink panel on every window screen (inspector, ⌥⌘B: eyes, Ask-First card, suggestions for the page, the shared chat).
- [x] Settings: wake and evening times, shortcuts, which AI does what, cost meter from `model_usage` (model choice stays a server setting).
- [x] Tasks grouped Overdue / Today / Upcoming / Someday, with every open Apple Reminder.

Gates:
- [x] `/ponytail-audit` (2026-10-12): 6 findings, all fixed (panel context fenced as data, chat turn order, all-day reminders, clipboard saves and disk cap, bulk reload). CI green.
- [x] `/ponytail-debt`: 22 shortcuts, every one with an upgrade trigger.
- [x] Idle at rest: 0.0 % CPU, 58 MB, about one wake-up a second (clipboard check with tolerance), measured with `top`.
- [x] VoiceOver confirmed by the owner.
- [x] New screens checked by the owner: Spaces, timeline, Blink panel, Settings.
- [x] Evening check-in fills tomorrow on the timeline, checked end to end by the owner.

## After Phase 0
Phase 1: the notch panel (rest, peek, glance), calendar and reminders from EventKit, the meeting card at T−10, and Ask-First approvals with server-verified signatures.
