# Build status

## Where we are (2026-10-13)

| Phase | Status | What's left |
|---|---|---|
| 0 Foundation | ✅ Done | |
| 1 Notch, calendar, Ask-First | ✅ Done | State matrix (§9.8) not formally covered |
| 2 Notes, tasks, habits, Spaces, Mac window | ✅ Done | |
| 3 Chat and content engine | 🟡 In progress | LinkedIn/X playbooks as skills; per-post metrics over time; posting by API (copy & open today) |
| 4 Claude app connector | ⬜ Not started | No `mcp` function yet |
| 5 Email | 🟡 Nearly done | First real send on each account; check Sent has no duplicate copy |
| 6 iPhone | ⏸ Paused (owner, 2026-10-12) | Decision on the paid Apple Developer account |
| 7 Money | 🟡 In progress | Owner sets up the iPhone automation; 80/100% limit alerts; bank SMS (rare in Germany) |
| 8 Polish | ⬜ Not started | Weekly review, learned rules, health page |
| Onboarding and one-click server | 🟡 Built, not proven | One real end-to-end run with the registered OAuth app |
| /meet (Google Calendar) | ✅ Done (2026-10-14, real invites sent) | Google app is in Testing (reconnect weekly) until published: privacy page section ready, not pushed |
| Launch (free DMG + site) | 🟡 Ready to publish | Owner: helper on its own project, DNS for www.blinkk.app, host the site (docs/LAUNCH.md) |

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

## Onboarding, visual Today, storage (Mac session, 2026-10-13)
Owner: Blink sets up each person's server (one-click via Supabase, next); distribution not decided yet.
- [x] First run: Welcome → Server → Account → Calendar (real next meeting = value moment) → About you; existing installs skip it.
- [x] Settings in plain sight: sidebar, notch menu, menu bar; prompts open the right tab.
- [x] Setup ring on Today and just-in-time "Add …" prompts (AI key in the notch chat and Blink panel, handle, mail, money, habit).
- [x] Today redesigned: day rings, clickable number tiles, day strip, habits and spending this week.
- [x] Notch peeks when ideas, drafts, a week plan or a page read finish (or fail).
- [x] Storage: nightly cleanup job (setup/cleanup_schedule.sql), clipboard caps 200 KB, post images pruned.
- [x] One-click server creation: "Sign in with Supabase" through a stateless helper (functions/signin, holds the OAuth client secret, stores nothing), then the app creates the project, runs the bundled migrations, deploys the functions, creates the owner's login, closes sign-ups, runs the schedules; resumable.
- [x] Owner registered the "Blink" OAuth app; BLINK_OAUTH_CLIENT_ID / BLINK_OAUTH_CLIENT_SECRET set on the helper.
- [ ] One real end-to-end run of one-click setup.
- [x] Restart Setup in Settings (sign out, forget the server here, show onboarding again).
- [x] The notch confirms finished ideas and drafts even if it was open.
- [x] Toolbar crash fixed: search fields moved into the pages, Blink's own sidebar button.
- [x] Energy at rest (2026-10-13): ≈1% CPU, energy impact ≈1 (Activity Monitor numbers, Debug build).

## Content redesign (Mac session, 2026-10-12)
Owner: Apify only for Instagram; LinkedIn and X numbers typed in (no X account yet); post performance first; tab layout approved.
- [x] Content page in four tabs: Overview · Posts · Plan · Ideas; New Post (⌘N) as a sheet; posts open in their own sheet.
- [x] Posts: one line each, search, platform filter, folding sections (Ready · Drafts · Posted).
- [x] Overview: connected accounts (follower numbers typed in, `social_account`), likes/comments/reel views per post, engagement per post, best format, best day, posts per week, top posts, "what works".
- [ ] Owner: set Voice (handle + creator brief), then Read My Page once to fill Overview.

## Phase 7 status (Mac session, 2026-10-12): first slice
Owner: "a basic entry, like a budget calculator at max, with AI that sorts it properly"; meals left out for now.
- [x] `transaction` + `budget` tables (RLS tests); `money` Edge Function sorts free text into spends with categories on the free Groq model (checked amounts, categories, days).
- [x] Money page: type the day's spending → Sort It → check/edit → Save; this month per category against a monthly limit; latest spends by day (change category, delete).
- [x] Notch `/spent 8.50 lunch, 3 bus` saves at once with Undo. Blink panel on Money answers "Where is my money going?" from this month's numbers.
- [x] Money dashboard: pace, day-by-day and category charts, month-end forecast.
- [x] Accounts with balances (`money_account`, view `money_account_now`); a spend can come off an account; "Left at month end" and "Lasts N days" at this month's pace.
- [x] Apple Pay capture (2026-10-13): Money › Apple Pay makes a private link for an iPhone Shortcuts "Transaction" automation; the `capture` function saves each tap (euros, category from the shop, account from the card, the same tap twice in a minute once). Live and checked end to end with a test key.
- [x] Receipts from mail: paid receipts and card debits in non-spam mail become spends (no account, never twice with a tap: same amount within 2 days).
- [x] Evening money nudge in the notch 45 minutes before the evening check-in (20:45 by default), with what was caught today.
- [ ] Later in Phase 7: 20:45 "Any spends I missed today?" nudge, Apple Pay / bank SMS capture via Shortcuts, limit alerts (P1 at 80/100%), Money on iPhone.

## Phase 5 status (Mac session, 2026-10-12): started
Owner choices: Gmail + iCloud (two iCloud+ custom-domain addresses); important = jobs, uni and official, clients and products, money and bills; checking runs on the server.
- [x] Server can reach imap.gmail.com/imap.mail.me.com:993 and smtp.gmail.com:465/587, smtp.mail.me.com:587 (probe, then retired).
- [x] email_msg + mail_state tables (summaries only, apps change status only; RLS tests, live).
- [x] mail Edge Function: own IMAP client (tested on recorded replies), triage on the free Groq model, reply drafts in the owner's voice appended to the account's Drafts folder (shows in Apple Mail), reply sent from the address the mail went to; mail text fenced as data.
- [x] Schedule: pg_cron every 5 minutes with a Vault secret (backend/supabase/setup/mail_schedule.sql); ran OK.
- [x] App: Inbox page (Important / Needs a reply / Everything else / Newsletters), Draft Reply (with a note), Open in Mail, Done; important mail peeks in the notch and shows on Today; Sync Now also checks mail.
- [x] Owner added the Gmail and iCloud secrets; first real check ran. University mailbox: code ready; not connected yet (needs UNI_ADDRESS, UNI_PASSWORD and UNI_IMAP_HOST as secrets, checked 2026-10-13).
- [x] Stricter triage: job-board alerts and renewal spam never important (rule in code + prompt), larger free model.
- [x] Owner teaches triage: Mark Important / Not Important per sender (mail_sender_rule), applied before the model and shown to it as examples; undoable.
- [x] Inbox: mailbox tabs (All / Gmail / iCloud / Uni), search, folding sections; sidebar groups fold.
- [x] Send from Blink after Touch ID: review sheet (edit, now or later), red mail.send action signed over the exact mail, own SMTP client on the server, 10 s Cancel for "now", scheduled sends cancellable in the Inbox, copy to Sent, Blink's draft removed from Drafts.
- [x] Chat: "send the reply to Sam on the 15th" proposes a card; approving opens the reply for review with that time.
- [ ] First real send on each account (Gmail, iCloud, uni); check Sent has no duplicate copy on iCloud and uni.

## Phase 3 status (Mac session, 2026-10-12): started
Owner choices: Instagram, LinkedIn and X first; posts go out by copy & open (no platform APIs yet).
- [x] content_piece + voice_profile tables (RLS tests, live); `content` Edge Function drafts one native post per platform with structured output.
- [x] Content page: idea → drafts, writing check (AI-sounding phrases, placeholders, limits, never-say words), edit, approve, copy & open; Voice sheet.
- [x] Morning card: approved posts show in the notch glance ("2 posts ready · Open") and a "Ready to post" card on Today.
- [x] Weekly content plan: Plan My Week (4–5 posts on the next 7 days), Write / Write All, planned day on drafts, "Today's post" in the notch and on Today.
- [x] Notch: /post, /ideas, Copy & Open on ready posts; chat history kept across restarts (last 20 turns, on this Mac).
- [x] Model choice per feature in Settings: Claude or free Groq models (chat with tools, content drafts); server allowlist.
- [x] Quick model switcher in the Blink panel header and on the Content page (same setting as Settings › AI & Usage).
- [x] Daily limit for paid models (Claude + OpenRouter) in Settings, over the last 24 hours; $5 when not set (`BLINK_DAILY_CAP_USD`); free Groq models keep working. Enforced by the chat, content, page and mail functions.

### Future: more free models (owner, 2026-10-12)
- **GLM-4.7-Flash / GLM-4.6V-Flash on z.ai**: listed free with no end date, OpenAI-style API with tools and JSON; one request at a time, slow. Needs a free z.ai key as a server secret.
- **On this Mac (Ollama)**: 16 GB Mac → Qwen 3.5 9B or Qwen 3 8B. Called from the Mac app itself (the server can't reach the Mac), so for text edits, idea lists and summaries, or an offline "this Mac only" mode.
- **Cloudflare Workers AI FLUX** for free carousel and cover images (10,000 free units a day); needs a free Cloudflare token.
- Skipped for now: DeepSeek, Kimi, Qwen on Alibaba Cloud (trial credits only), SiliconFlow (needs Chinese ID check). OpenRouter is in use for best models only (four picks, small prepaid credit), not for free models.
- [x] Read My Page (Apify, own public Instagram): suggested voice, what works / avoid, best posts; ideas and the week plan build on the best posts.
- [x] Post images: Cloudflare FLUX (free allowance, 100 a day cap); carousel slides drawn on the Mac over one background, drag or Export…; covers for other posts.
- [x] Settings › Connections: checks each server key (Anthropic, Groq, Apify, Cloudflare) with a free read-only call.
- [ ] Per-post metrics over time; LinkedIn/X playbooks as skills.

Phase 3 audit (2026-10-12):
- [x] `/ponytail-debt`: 24 shortcuts, all with an upgrade trigger (chat-history note updated: kept on this Mac).
- [x] `/ponytail-audit`: page reader now reads only the handle saved in Voice (the request can't name another account); every Apify try counts toward the 10-minute guard; fixed and deployed.
- [x] Owner rule: no post design until asked (slides and images only after Design Slides / Make Image).

## Phase 6 (iPhone): paused
Owner, 2026-10-12: stop the iPhone for now, pending the paid Apple Developer account decision (push, Live Activity updates). Shared code keeps building for iOS.

## Marketing (2026-10-13)
- [x] Launch film in `marketing/intro-video` (Remotion): 60 s plus 30 s and 15 s cuts, 16:9 and 9:16; Kenney CC0 sound effects; the Pixabay music track is git-ignored.

## Audit gate for onboarding, one-click setup, money accounts and content tabs (2026-10-13)
- [x] `/ponytail-debt`: 26 shortcuts, all with an upgrade trigger (two stale phase labels reworded).
- [x] Backend `/ponytail-audit`: no must-fix; fixes in `20261013090000_audit_fixes.sql` (expired cards cleaned, spend-cap index, account names unique without case, server-side balance time, one-step default account), money function no longer ignores a failed account read, sign-in helper returns only fixed error words.
- [x] App `/ponytail-audit`: 4 must-fix fixed (one-click setup asked for the keys at an encoded URL; amounts of 1,000+ became 0 and "1.250" became 1.25; setup could get stuck after a lost reply, now each migration is recorded in the server's own ledger in the same transaction; the owner's handle in placeholders). Also: sign-out session counter (no polling, no data across accounts), setup's last-step sign-in notice, notch notices queue, build fails if a dotfile would be bundled, one currency setting, draft images load off the main thread, no double sync after onboarding.
- [x] Personal names, emails, employer and university removed from code, prompts and tests; the owner's mail priorities moved to the `MAIL_PRIORITIES` secret (set on the owner's server).
- [x] `/ponytail-review` of the fixes: 1 must-fix (relaunch within 30 s showed an empty app) and 4 should-fix, all fixed.
- [x] CI green (functions, swift, database, secrets); migration applied live; money, mail and signin redeployed; the next mail check ran OK.
- [x] VoiceOver on the new screens: confirmed by the owner (2026-10-13).
- [ ] Instruments 0 fps at rest (§36.7).

## Launch kit (2026-10-13)
- [x] `apps/Blink/scripts/release.sh`: free, ad-hoc signed Release DMG (sandboxed, same entitlements minus keychain-access-groups; the login keychain stands in). Test copy launched without errors.
- [x] Site in `marketing/site` (home, install guide with Open Anyway, privacy, terms); no third-party requests.
- [x] `docs/LAUNCH.md`: the owner's steps (helper on its own project, DNS, hosting) and what $99 adds.
- [ ] First install of the DMG on a second Mac or user account, through the whole first run.

## Feature polish (2026-10-14)
- [x] Mail: a batch the AI couldn't sort is marked unsorted and sorted on a later check (newest first, up to 10 a run, 3 days; mail gone from the inbox is let go). Reply digest: the notch lists mail waiting for a reply and peeks once a day from 10:00.
- [x] Money: notch alerts at 80% and over 100% of a category's limit (once each a month) and last week's summary on the first sync of a new week.
- [x] Start at login (owner's switch in onboarding and Settings); the morning brief also comes when Blink starts before noon.
- [x] A drawn notch on screens without one (external display, lid closed). Not tested on such a screen yet.
- [x] Chat streams word by word (Claude, Groq, OpenRouter; server-sent events), cut-off answers say so, a mid-answer refusal resets cleanly.
- [x] `/ponytail-review`: 2 must-fix and 6 should-fix found and fixed. CI green; migration and functions live.
- [ ] Owner: try chat streaming, a real login with "Open at login" on, and an external screen with the lid closed.
