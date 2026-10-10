# Personal Assistant: Master Plan

> **Superseded on conflict by [ARCHITECTURE.md](ARCHITECTURE.md)**, the single source of truth for tech and UX architecture.

> **One line:** A Claude-powered second brain that lives in your MacBook notch and your iPhone Dynamic Island. It knows your day, prepares things before you ask, and never acts without your OK.

Status: **Planning.** Nothing is built yet. This file is the single source of truth: update it as decisions are made.
Look, mascot (**Blink**), model switching, content engine and battery decisions live in **[DESIGN.md](DESIGN.md)**.

---

## 1. The 7 principles

1. **Part of your life, not another app.** It comes to you: when you wake up, open the laptop, unlock the phone, finish a meeting, or wind down at night.
2. **Prepares ahead of time.** It plans tomorrow with you at night, researches and drafts overnight, and has everything ready in the morning.
3. **Asks before acting.** "Do you want me to do it?" is on every screen. Small things take one tap with Undo; email, posts and money need Face ID.
4. **Everything is connected.** Meetings ↔ notes ↔ emails ↔ people ↔ tasks ↔ projects ↔ habits ↔ money ↔ content. So "Summarise everything about X" works.
5. **Claude is the brain.** One AI provider: Claude. An Auto router picks Opus, Sonnet or Haiku per job, and you can switch any time.
6. **Ask once, learn forever.** One setup conversation with Blink; after that it learns from what you approve, edit and skip, and never asks the same thing twice.
7. **Only you can see it, and it's easy on the battery.** Private backend, Face ID, keys never displayed. The server does the work and the devices sleep.

---

## 2. A day with it

| Moment | Where | What you see |
|---|---|---|
| **Wake up** | iPhone Lock Screen + Dynamic Island | ☀️ "Good morning. Today: 3 meetings (first at 10:00) · Focus: notch animations · posts ready for your platforms · 2 important emails · Workout planned 7:00" |
| **Open the laptop** | Mac notch expands once | Same morning brief + **project status**: "Assistant app: Phase 1, 4/7 done · Client X: waiting on their reply" → [Start focus] [Review post] [Open inbox] |
| **Chat** | Mac notch, app or Claude app | "What are we creating content on today?" → Claude answers with options from your projects + overnight research → [Save to content board] |
| **"Remind me about the 3 pm meeting"** | Chat | Claude fetches the 3 pm event from your calendar → "Design sync with Priya at 3:00, 2 linked notes. Remind you 10 min before?" → [Do it] |
| **2:57 pm** | Dynamic Island + Mac menu bar + notch | ⏱ "Design sync in 3 min" · notes · [Join] |
| **3:03 pm** | Dynamic Island | "Design sync started 3 min ago" · [Open notes] |
| **Meeting ends** | Notch / notification | "Capture notes? Set a follow-up? Draft a follow-up email?" |
| **Important email** | Notch / notification | "Client X replied about the invoice. Draft ready." → [Review] [Send] [Snooze] |
| **Spending** | Quiet badge | "$42 at Whole Foods. Food budget 70% used." |
| **To-do check** | Notch, afternoon | "You have 'Send proposal' due today and a free hour at 4. Work on it then?" |
| **Night (~9:30)** | Notch / Dynamic Island | "You haven't planned tomorrow yet. **Plan with me** / **Auto-plan, I'll review** / Later" |
| **Evening check-in** | Chat card | "Workout today?" No → ❌ → "Put it at 7:00 tomorrow?" · "Here are tomorrow's important meetings" (mini calendar) · "Anything from today worth posting?" |
| **Overnight** | Backend | Researches your topic, drafts today's content for each of your platforms, summarises the day, prepares tomorrow's brief |

---

## 3. Modules

### 3.1 Today (home screen)
- One screen: next meeting, focus task, to-dos, important emails, habit checklist, budget pulse, content of the day, project status.
- The same data powers the notch, Dynamic Island, widgets and the morning brief.

### 3.2 Calendar
- Reads all your calendars through **EventKit**: iCloud, Google and Exchange accounts that are added to your Mac or iPhone.
- **Before a meeting:** a brief with attendees, your linked notes, last email thread with them, and open tasks.
- **After a meeting:** a wrap-up prompt (notes / follow-up / email).
- Can create, move and decline events from chat, always through an Ask-First card.

### 3.3 Notes / second brain (your own system, primary)
- Fast notes in Markdown, with templates (meeting, idea, journal).
- **Links:** any note can link to a meeting, person, email, project or idea, and back-links appear automatically.
- **Semantic search:** "what did I promise Sam?" finds it even if the words don't match.
- **Quick capture** from anywhere: notch, global hotkey, iPhone Action Button, Share Sheet, Siri, or dragging something onto the notch.

### 3.4 To-dos, reminders and habits ("schedule checker")
- To-dos with due dates, linked to projects, meetings and notes.
- Reminders show in the **notch** (Mac) and **Dynamic Island** (iPhone) first. Copying them into Apple Reminders is optional (for Siri).
- **Habits** (workout, reading, …) get daily ✅ / ❌ / ⏭, streaks, and weekly stats ("Workout 3/7").
- The nightly check-in fills the schedule checker by conversation.

### 3.5 Projects
- Each project has a status, next step, linked to-dos, notes, emails and people.
- Status is shown in the morning brief and on opening the laptop: "Phase 1, 4/7 done · blocked on X".
- Optional later: pull activity from GitHub so it knows what you shipped.

### 3.6 Email (works with your Apple Mail setup)
- Apple Mail is only the app that displays mail. The assistant connects to **the account behind it** (iCloud / Google / Outlook / your domain host) over **IMAP + SMTP**.
- **Triage:** Important / Needs reply / FYI / Noise. Only *Important* interrupts you.
- **Drafts in your voice** are saved to your Drafts folder, **so they appear inside Apple Mail too**.
- **Send / Send later** happens only after your approval (Face ID).
- **Summaries:** daily inbox summary, and "summarise this thread".

### 3.7 Budget: no bank app connection needed
Reading the bank app's **notifications** directly isn't possible: iOS never lets one app read another app's notifications, and on macOS the notification database is protected and changes between versions. The same information reaches you through three channels we *can* read, so we use those instead:

| Source | How | Covers |
|---|---|---|
| **Apple Pay taps** | Shortcuts **"Transaction" automation** (Wallet) runs our *Log Transaction* App Intent with amount + merchant + card, the moment you pay | Every Apple Pay purchase, any card in Wallet |
| **Bank SMS alerts** | Shortcuts **"Message" automation** (sender = bank, contains "debited"/"purchase") passes the text to our intent → Claude extracts amount, merchant, date | Card swipes, online purchases, transfers (turn on SMS alerts in each bank's settings) |
| **Bank email alerts** | Already flowing in through the email module → Claude extracts the transaction | Same as SMS, for banks that email instead |
| Optional: **SimpleFIN Bridge** | Read-only bank sync, $15/yr (Plaid/Teller as fallback) | Balances + anything the alerts missed; only if you want it later |

- **Duplicates are removed automatically:** the same purchase arriving via Apple Pay + SMS + email is merged by amount, merchant and time.
- **Manual entry** from the notch or Siri for cash.
- To test on your iPhone: which bank SMS formats parse cleanly, and whether the Message automation runs without asking each time on your iOS version.
- Auto-categorisation by Claude; monthly budgets per category; alerts at 80% / 100%.
- Weekly money summary in the Sunday review.

### 3.8 Content engine (any platform)
Full design: [DESIGN.md §5](DESIGN.md#5-content-engine-any-platform-no-setup-per-platform).
- **One idea becomes a "core message"** (story, points, proof, CTA, assets), which is **adapted natively** for each platform you use: LinkedIn post/carousel, Instagram carousel + caption + Reel script, X post/thread, YouTube script + titles + thumbnail idea + chapters, Shorts, and more.
- **Platform Playbooks:** one Claude skill per platform describes how it works (formats, limits, hooks, tone, timing, what performs now). They are refreshed monthly by research. **Adding a platform = adding a playbook**, with no code change.
- **Cadence is proposed, not asked:** every Sunday night Blink proposes the week's content plan from your goals, calendar load and results. You approve once.
- **Autopilot (nightly):** your day + research → today's pieces drafted in your voice → morning card [Review] [Post] [Schedule] [Skip].
- **Publishing:** direct API where allowed (LinkedIn, Instagram Creator/Business, X pay-per-use). **One-tap handoff** everywhere else (YouTube, TikTok, …): caption copied, media saved, app opened. **Nothing posts without your tap.**

### 3.9 Chat ("you + Claude together")
- A chat panel in the notch, the app and the Claude app, all sharing the same memory and data.
- Anything in chat can be **saved** (to notes, content board or to-dos) or **acted on** (reminder, calendar event, draft) through Ask-First cards.

---

## 4. The Ask-First Helper (everywhere)

One card design used across the whole system:

```
✨ Post to LinkedIn?
"3 things I learned building a notch app…"   Scheduled 9:00
[ ✓ Do it ]  [ ✎ Edit ]  [ ⏰ Later ]  [ ✕ ]
```

| Level | Examples | Confirmation |
|---|---|---|
| 🟢 Small | Mark habit, save idea, add note | Done immediately + 5 s **Undo** |
| 🟡 Medium | Reminder, calendar event, plan tomorrow | One tap **Do it** |
| 🔴 Important | Send email, publish a post, anything money | Preview → **Face ID** → 10 s "Sending… Undo" |

- **"Waiting for you" queue:** missed cards collect in one place ("3 things waiting").
- **Learns your preferences, and asks first:** "You always approve marking workouts. Do it automatically?" 🔴 actions are **never** automatic.
- **Suggestions while you work:** after you write a note → "Turn into a post?"; after a meeting → "Follow-up?"; when an email mentions a date → "Add to calendar?"

---

## 5. Where it lives: surfaces

### 5.1 Mac
- **Notch overlay**, built with [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit), using patterns from [Boring Notch](https://github.com/TheBoredTeam/boring.notch).
  - Resting: thin strip with dots/counts (unread important, next meeting countdown, reminders).
  - Hover/click: expands into a mini dashboard plus chat input.
  - Proactive pop-outs: meetings, reminders, important mail, Ask-First cards.
  - Drag-and-drop onto the notch saves to notes/content.
- **Wake/unlock trigger:** listen for `NSWorkspace.didWakeNotification` and the screen-unlock system notification → show the morning brief once per day (or "while you were away" later in the day).
- **Menu bar:** macOS 26+ automatically shows the **iPhone's Live Activities in the Mac menu bar**, so the meeting countdown appears there for free.
- **Global hotkey** (e.g. ⌥Space) for capture or chat.
- Distribution: signed and notarised, installed directly (not the Mac App Store, because the notch overlay doesn't fit App Store rules).

### 5.2 iPhone 15 (has the Dynamic Island)
- **Live Activities** (ActivityKit):
  - Meeting countdown "in 3 min" → "started 3 min ago", **started by the server via push-to-start**.
  - Reminder countdowns.
  - Morning brief activity (short-lived, ends when you open it).
  - Live Activities also mirror to the **Mac menu bar** and **Apple Watch Smart Stack** automatically.
- **Waking up:** iOS doesn't let apps detect "phone unlocked", so we cover it in three ways:
  1. **Lock Screen widget** that always shows Today.
  2. **Push-to-start Live Activity** at your usual wake time.
  3. Optional **Shortcuts automation**: "When Sleep Focus turns off → run *Morning Brief* (our App Intent)". Test this on a real device: there are developer reports that alarm-based triggers can be unreliable.
- **Notifications:** Time-Sensitive, with action buttons (Do it / Snooze / Draft reply).
- **Widgets:** Today, Next meeting, Habits (interactive checkboxes).
- **Action Button / Siri / Shortcuts:** "Add idea", "Plan my day", "What's next?"

### 5.2a Getting it onto your iPhone without the App Store
It never needs to go on the App Store. It's a personal app, so there's no App Store review and no listing. iPhone 15 and every later model has the Dynamic Island.

| Stage | Cost | How | What works | Limits |
|---|---|---|---|---|
| **A. Start free** | $0 | Use the assistant on iPhone through the **Claude app** (custom connector) + a **web app** saved to your Home Screen (Safari → Share → Add to Home Screen) | Chat, today, notes, to-dos, plans, approvals; **web push notifications** (iOS 16.4+) | No Dynamic Island, no widgets |
| **B. Native app, free account** | $0 | Free Apple ID in Xcode on your Mac → plug in the iPhone (Developer Mode on) → press **Run** | Native app, widgets, Dynamic Island **when started from the app**, Face ID, Shortcuts automations (Apple Pay / SMS budget capture) | App **expires every 7 days**: plug in and press Run again (data stays). No server push, so no automatic meeting countdowns or instant mail alerts. Max 3 such apps per phone |
| **C. Full** | $99/yr Apple Developer Program | Same app, signed for a year; install by cable or **TestFlight** | Everything: server push, automatic Dynamic Island countdowns, instant alerts | — |

- **The Mac notch app is free:** it runs on your own Mac with a free account; no fee and no weekly reinstall.
- Recommended path: build on **A + Mac notch** first, at no cost. Move to **B** when the native iPhone app is ready. Pay for **C** only when you want automatic Dynamic Island countdowns and instant alerts.
- The backend is designed so nothing changes when you upgrade: the same app gains push features once the account is paid.

### 5.3 Claude app (Mac, iPhone, web)
- Our backend exposes a **remote MCP server**, added in Claude under *Settings → Connectors → Add custom connector*, with an OAuth login so only you can use it.
- Tools it exposes: `get_today`, `search_notes`, `create_note`, `list_todos`, `create_reminder`, `get_calendar`, `draft_email`, `get_budget`, `content_board`, `project_status`, …
- **Skills** (our own, written in the style of [anthropics/skills](https://github.com/anthropics/skills)): `morning-brief`, `evening-planning`, `weekly-review`, `meeting-prep`, `email-triage`, `content-autopilot`, `linkedin-post`, `budget-check`.
- In the Claude app, write actions also go through confirmation: Claude asks, you say yes.

---

## 6. Architecture

```
┌──────────────── Apple apps — Swift / SwiftUI, shared code ────────────────┐
│ macOS: notch overlay · menu bar · hotkey · wake/unlock trigger            │
│ iOS:   Live Activities · widgets · App Intents · notifications            │
│ Both:  Face ID lock · Keychain · local cache (SwiftData, works offline)   │
│        EventKit (calendar + optional Apple Reminders)                     │
└──────────────────────────────────┬────────────────────────────────────────┘
                                   │ HTTPS (your login only)
┌──────────────────────────── Backend (Supabase) ───────────────────────────┐
│ Postgres + pgvector  — items, links, embeddings (semantic search)        │
│ Edge Functions       — API for apps · MCP server for Claude app          │
│ pg_cron schedules    — mail check · meeting watcher · nightly autopilot  │
│ Vault                — encrypted secrets (never returned to apps)        │
│ Push sender          — APNs: notifications + Live Activity start/update  │
│ Mail worker          — IMAP/SMTP (polling every 2–5 min to start;        │
│                        always-on IMAP IDLE worker later for instant mail)│
└───────────┬─────────────────────┬─────────────────────┬──────────────────┘
            │                     │                     │
  Claude API (router)  Apple Pay + SMS (Shortcuts)  Social APIs + handoff
```
Additional services (event bus, Blink state, model router, content engine, playbook refresher): see [DESIGN.md §7](DESIGN.md#7-architecture-additions).

### 6.1 Data model (simple version)
- `items`: one table for everything (note, todo, habit_log, event_ref, email_ref, transaction, idea, post, project), with `type`, `title`, `body`, `status`, `due_at`, `metadata`, `embedding`.
- `links`: `from_item`, `to_item`, `kind` (about, follow_up, source_of, belongs_to).
- `actions`: the Ask-First queue: proposed action, risk level, status (pending/approved/done/undone), who proposed it.
- `rules`: your auto-approve preferences.
- `daily_logs`: morning brief, evening check-in answers, summaries.

### 6.2 How Claude is used

Models are chosen by the **Auto router** ([DESIGN.md §4](DESIGN.md#4-model-switching-claude-only)). You can override per chat or per feature.

| Job | Claude feature | Auto picks |
|---|---|---|
| Evening planning, weekly review, content writing, hard questions | Messages API + **tool use** (tools = our modules), streaming | **Opus 5.5** (`claude-opus-5-5`) |
| Everyday chat, meeting briefs, summaries | Same | **Sonnet 5.5** (`claude-sonnet-5-5`) |
| Email triage, transaction extraction, categories | **Structured outputs** (fixed JSON categories) | **Haiku 5.5** (`claude-haiku-5-5`) |
| Overnight autopilot (content, summaries, tomorrow's brief) | **Message Batches** (50% cheaper, not urgent) + **web search tool** for research | Opus 5.5 |
| Your voice, preferences, long-term memory | **Prompt caching** of your profile + voice examples; memory stored in our DB | — |
| Nightly jobs, alternative path | **Claude Managed Agents** with scheduled deployments (Anthropic runs the loop; secrets in vaults) | Evaluate in Phase 3 |
| Safety | Email/web text treated as **data, never instructions**; write actions only via Ask-First; refusal fallback enabled | — |

### 6.3 Rough running costs (estimates, to verify)
| Item | Cost |
|---|---|
| Apple Developer Program | **Optional at first.** $0 with a free account (iPhone app reinstall every 7 days, no server push); $99 / year later for push, automatic Live Activities and TestFlight |
| Claude API | Under ~$1–2 / day with the Auto router (Haiku for small jobs, Batches overnight, caching) |
| Supabase | Free tier to start; Pro $25/month when needed |
| SimpleFIN Bridge (optional) | $15 / year |
| LinkedIn, Instagram APIs | Free |
| X API (optional) | ~$0.015 per post, ~$0.20 with a link |

---

## 7. Privacy and security

| Where | What | Protection |
|---|---|---|
| Apps | Everything | **Face ID** to open; a second Face ID check for **Email**, **Budget**, **Keys** |
| Device Keychain | Personal keys and tokens | Locked to *current* biometrics: adding a new face or finger makes them unreadable |
| Backend | Claude key, mail password, bank token, social tokens | Encrypted in **Supabase Vault**; **never sent to any app**. UI shows "Connected ✓"; replacing a key requires Face ID; viewing is not possible |
| Database | Your data | Row-level security, **sign-ups disabled**, single user |
| Claude connector | Claude app access | OAuth with your account only; write tools go through confirmation |
| Git | Code | **No secrets ever committed** (ignored config files + Keychain) |
| AI safety | Emails/web pages | Never followed as instructions; 🔴 actions always need Face ID |

Trade-off: the backend must be able to read mail and transactions to alert you while your phone is locked. Notes can optionally be **end-to-end encrypted** later; server-side AI search over them would then be turned off.

---

## 8. Build phases (one at a time)

| # | Phase | Done when… |
|---|---|---|
| 0 | **Setup + design:** Xcode multiplatform project (free account), Supabase project, Face ID lock, Keychain, secrets in Vault; **Blink designed in Rive** (all states + still poses); setup conversation script | App opens with Face ID on Mac + iPhone; backend reachable with your login only; Blink's states approved |
| 1 | **Notch + Blink + Calendar + Reminders + Ask-First Helper** | Blink lives in the notch; meeting "in 10 min" pops out with notes; Ask-First card works; morning brief on laptop open; **idle CPU near zero** |
| 2 | **Notes + To-dos + Habits + Evening planning + Projects + Mac app window** | Nightly "plan tomorrow?" conversation fills the schedule checker; project status in the brief; Blink panel on every screen |
| 3 | **Chat + model router + Content engine** (playbooks for your platforms) | One idea becomes native drafts per platform; overnight drafts wait in the morning; publish or one-tap handoff |
| 4 | **Claude app connector + skills** | Same assistant usable inside the Claude app with your login |
| 5 | **Email** | Important mail alerts; drafts appear in Apple Mail; send after Face ID |
| 6 | **iPhone app: Blink button, Dynamic Island + widgets + wake-up** | "Meeting in 3 min / started 3 min ago" with Blink's poses; Lock Screen Today widget; the app isn't a significant user in Settings → Battery |
| 7 | **Budget** (Apple Pay + SMS + email alerts) | An Apple Pay tap and a bank SMS both show up in the budget within a minute, without duplicates; categories + alerts work |
| 8 | **Polish:** weekly review, "while you were away", learning rules | Sunday review summarises habits, money, content, projects |

**How we'll work:** Claude Code running **on your Mac** (it can build with Xcode), or code written here → pushed to GitHub → you press Run in Xcode. Each phase gets a checklist in this file.

---

## 9. Building blocks (open source to learn from)

| Area | Repo / service | Use |
|---|---|---|
| Notch | [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | Core notch UI package |
| Notch | [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) | Reference: animations, calendar, shelf |
| Notch | [zzfadi/NotchFlow](https://github.com/zzfadi/NotchFlow) | Multi-display handling |
| Dynamic Island | [1998code/iOS16-Live-Activities](https://github.com/1998code/iOS16-Live-Activities) | Live Activity sample |
| Apple coding | [rshankras/claude-code-apple-skills](https://github.com/rshankras/claude-code-apple-skills) | Claude Code skills for Live Activities etc. |
| Email AI | [elie222/inbox-zero](https://github.com/elie222/inbox-zero) | Reference for triage + drafting design |
| Budget | SimpleFIN Bridge, Actual Budget, Firefly III | Bank data; category/rule design |
| Skills | [anthropics/skills](https://github.com/anthropics/skills), awesome-claude-skills | Templates for our own skills |
| Planning UX | Sunsama (shutdown ritual), Motion (auto-scheduling) | Inspiration for evening/morning flows |

> Check each repo's licence before copying code. For personal use any licence works. For a product you sell, copy only MIT/Apache code.

---

## 10. Decided, and what's collected in setup

**Decided:** Supabase backend · native SwiftUI · Blink mascot · Auto model router · platform playbooks with proposed cadence · free Apple account first · budget from Apple Pay/SMS/email alerts. Details in [DESIGN.md §8](DESIGN.md#8-decisions-made-so-you-dont-have-to-answer-them).

**Collected once in Blink's setup conversation (not separate questions):** which banks send alerts, the mail account behind Apple Mail, wake and evening times, platforms and goals, writing samples, habits, budget categories.

**Needed before Phase 0:** a Mac with Xcode installed (free).
