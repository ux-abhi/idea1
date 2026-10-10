# Design Direction

> **Superseded on conflict by [ARCHITECTURE.md](ARCHITECTURE.md)**, the single source of truth for tech and UX architecture.

Companion to [PLAN.md](PLAN.md). This file decides **how the assistant looks, feels, thinks and saves battery**. Planning only: no app code yet.

---

## 1. What makes it different from every other AI

| Typical AI app | This assistant |
|---|---|
| A chat box you have to open | **Ambient:** it lives in the notch and the Dynamic Island and comes to you |
| A faceless text bot or a humanlike avatar | **A small character made from the notch itself** (see Blink below) |
| Asks the same questions every time | **Ask once, learn forever:** one setup conversation, then it infers and adapts |
| Answers when asked | **Prepares ahead:** overnight work, morning brief, evening planning |
| Does things, or can't do anything | **Ask-First:** prepares everything, acts after your OK |
| One model for everything | **Picks the right Claude model per job**, and you can switch any time |

### Ask once, learn forever
- **One setup conversation** (about 10 minutes, with Blink) covers who you are, goals, which platforms you use, 5–10 samples of your writing, wake and sleep times, habits, budget categories, and important people.
- After that it **never asks the same thing twice**. It learns from what you approve, edit or skip, and proposes changes ("You skip Friday posts. Stop planning them?").
- Everything it has learned is visible and editable in **Settings → What Blink knows**.

---

## 2. Blink: the mascot

**Name: Blink.** It suits the character: the eyes and the blink are Blink's whole personality.

### Concept
Blink **is the notch.** The black notch on your MacBook and the black Dynamic Island on your iPhone become Blink's body, and **Blink only needs a pair of eyes** to come alive. That makes it:
- **Unique:** no other assistant turns the hardware into the character.
- **Native:** it looks like part of the Mac and iPhone, not a sticker on top.
- **Battery-light:** a few white pixels, not a 3D avatar.
- **Honest:** a friendly creature, not a fake human. Press coverage of humanlike AI avatars (Google's Live Avatar) reports researchers' concern that humanlikeness builds false trust; Blink avoids that by design.

Inspiration taken: the **liveliness** of Grok's animated companions and Google's Gemini avatars, which react, emote and feel present. What we leave out: humanlike faces and lip-sync, for the reasons above.

### Look: particles in glass (v1, from your droplet sketch)
Interactive study: [Blink Notch Studio](https://claude.ai/artifact/SDNx2J5QPNracfBuWnkaDS) · source in `design/blink-studio.html`.

- **Eyes:** two **tilted white pills** (about 16°), taken from your sketch. The left one sits slightly lower. They're tilted enough that they never read as a pause button ⏸, which the Dynamic Island uses for music.
- **Full body:** a **droplet of tinted glass** with **light particles drifting inside**. Used for the app icon, the setup conversation, the Mac Blink panel and the iPhone Blink button.
- **In the notch / Dynamic Island:** the black hardware is the body. Only the eyes, the particles and the glass sheen appear, **all clipped inside the notch outline. No glow or shadow outside it.**
- **Glass (Apple Liquid Glass style):** a soft specular band at the top inside edge, a thin rim of light along the bottom inner edge, and a faint colour glow rising from the bottom, all inside.
- **Home colour:** warm orange when idle; particles change colour and motion per mood.
- **Icon:** droplet with eyes, in light, dark and tinted variants for iOS 26 / macOS 26 icon modes.

```
  ╭──────────────────────────────╮
  │  ·  ˚   ⧸⧸   ·   ˚  ·        │   ← notch = body; tilted pill eyes,
  ╰──────────────────────────────╯      light particles + glass sheen inside only
```

### Expressions (state machine)

| State | Eyes | Particles (inside only) | When |
|---|---|---|---|
| **Idle** | Tilted pills, slow blink every 20–40 s | Few, orange, slow drift (frozen at rest on device) | Default |
| **Morning** | Opens slowly | Amber, rising | First wake/unlock of the day |
| **Heads-up** | Wide | Teal, livelier drift | Meeting soon, reminder due |
| **Important** | Wide | Coral, one pulse then calm | Important email, budget limit hit |
| **Listening** | Wide | Warm orange, breathing with your voice | You're talking or typing to it |
| **Thinking** | Look up | Ice blue, orbiting | Claude is working |
| **Done / happy** | ∩ ∩ arcs | Green, rising | Task done, approved, streak kept |
| **Concerned** | Tilt toward each other | Amber, slow | Habit missed, overspending, overdue |
| **Focus** | Closed | Almost none, very dim | Focus mode / Do Not Disturb: it stays quiet |
| **Sleepy** | Half-closed | Dim, sinking | After evening planning, until morning |
| **Celebrate** | ∩ ∩ arcs | Gold burst | Streaks, a post published, a goal hit |

**Particle budget:** at most 30 particles at 30 fps, only while Blink is reacting. At rest the frame freezes and only the blink plays. Calm mode stops all motion. iPhone surfaces use pre-rendered still poses.

Rules:
- **One reaction per event.** Blink nudges once, then waits in the "Waiting for you" queue, and never loops or nags.
- Glow colours are **semantic** and the same everywhere: teal = time/calendar, coral = important, green = money OK/done, amber = morning/night/attention.

### Where Blink appears
| Place | What Blink can do |
|---|---|
| **Mac notch** | Fully animated (Rive state machine), expands into cards, chat and quick capture |
| **iPhone Dynamic Island** | **Still poses** swapped per state. iOS doesn't allow continuous custom animation in Live Activities; the system animates the change between poses |
| **Mac menu bar** | Mirrors the iPhone Live Activity automatically (macOS 26+) |
| **Apple Watch Smart Stack** | Mirrors the Live Activity automatically |
| **App (Mac + iOS)** | Blink sits in the assistant panel and reacts to what you do |
| **Widgets** | Blink's face as today's mood: rested, busy day, overdue things |
| **Claude app** | Text only: the same personality through the connector |

### Personality (voice rules)
- **Short.** One line where one line will do. Numbers before adjectives ("3 meetings, first at 10").
- **Warm, a bit playful, never cute-spammy.** At most one emoji, and only in celebrations.
- **Never guilt-trips.** "Workout slipped. Tomorrow at 7?" never "You failed again."
- **Respects silence.** Focus, Sleep and meetings mean no pop-outs, only the queue.
- **Says what it did and how to undo it.** "Saved to Content · Undo"

### Production
- Eyes and glass in **Rive** (one file, a state machine with the states above); particles drawn natively (SpriteKit or a small Metal/Canvas layer) behind the eyes, capped as above. Rive suits stateful, interactive mascots; one React Native benchmark measured about 60 FPS for Rive versus about 17 FPS for Lottie.
- Export **still PNG poses** from the same file for the Dynamic Island, widgets and notifications.
- Measure battery with Xcode **Instruments** on a real device before shipping (see §6).

---

## 3. App design: a real Mac app, and a real iPhone app

### Look
- **Native SwiftUI** on macOS 26 / iOS 26+ with **Liquid Glass** on the navigation layer only (sidebar, toolbar, tab bar). Content stays on solid, readable surfaces, as Apple's guidance recommends.
- **SF Pro** system font and SF Symbols, so it feels like Apple made it.
- Calm neutral surfaces; colour is reserved for Blink's semantic glows and status.

### Mac window
```
┌───────────────┬──────────────────────────────────┬──────────────────┐
│ ◉ Today       │  TODAY · Thu 15 Oct              │  🟡 Blink          │
│   Inbox    3  │                                  │  "Design sync in │
│   Calendar    │  Next: Design sync 15:00         │   40 min. Your   │
│   Notes       │  Focus: notch animations         │   notes are      │
│   Tasks       │  ☐ Send proposal   ☑ Workout     │   ready."        │
│   Habits      │  Content: carousel ready (IG)    │  [Open notes]    │
│   Projects    │  Money: Food 70%                 │                  │
│   Content     │                                  │  Ask about this… │
│   Money       │                                  │  Model: Auto ▾   │
│ ─────────     │                                  │  Waiting (2)     │
│ Waiting   2   │                                  │                  │
└───────────────┴──────────────────────────────────┴──────────────────┘
   sidebar (glass)        content (solid)              Blink panel (inspector)
```
- **NavigationSplitView:** sidebar, content, and a **Blink panel** on the right.
- **The Blink panel is on every screen** and is aware of the screen's context. On a note: "Turn into a post?". On an email: "Draft reply?". On Money: "Why is Food high?".
- **⌘K / ⌥Space anywhere on the Mac** opens Blink from the notch. Typing goes to chat; `/` gives commands.
- **Notch** = the always-there version, **window** = the deep-work version. Same data, same Blink.

### iPhone app
- **Tab bar:** Today · Calendar · Notes · Content · Money, plus **Blink as a floating button** above the tab bar.
  - **Tap** to chat; **long-press** to talk (voice).
- **Same context awareness** as on Mac: Blink's suggestions change per screen.
- **Lock Screen widget**, **Action Button**, **Dynamic Island** with Blink's poses, and **interactive habit widget**.

### Ask-First cards (unchanged)
One card design everywhere, with the risk levels 🟢 / 🟡 / 🔴. Cards slide out of Blink in the notch or Dynamic Island.

---

## 4. Model switching (Claude only)

- **Auto (default):** a small **router** picks the model per job.
- **Manual:** a model chip in every chat ("Auto ▾") lets you switch **Opus / Sonnet / Haiku** for that conversation.
- **Per-feature overrides** in Settings, for example "always use Opus for weekly review".
- **Cost meter** in Settings: spend today, this month, by feature.

| Job | Auto picks | Why |
|---|---|---|
| Email triage, transaction extraction, categories, tagging | **Haiku 5.5** | Many small jobs: fast and very cheap |
| Everyday chat, meeting briefs, to-do updates, summaries | **Sonnet 5.5** | Quick and capable |
| Evening planning, weekly review, content writing, hard questions | **Opus 5.5** | Best thinking and writing |
| Overnight autopilot | Opus 5.5 via **Batches** (half price) | Not urgent, quality matters |

Behind the scenes, every feature asks the router for "fast", "balanced" or "best", never a model name. So when new Claude models come out, only the router table changes.

---

## 5. Content engine: any platform, no setup per platform

### Idea once, adapted everywhere
```
          Your day · projects · ideas · overnight research
                              │
                              ▼
                 ┌──────────────────────────┐
                 │   CORE MESSAGE (atom)    │  the one idea, story, proof,
                 │                          │  key points, CTA, assets
                 └────────────┬─────────────┘
          ┌────────────┬──────┴─────┬─────────────┬──────────────┐
          ▼            ▼            ▼             ▼              ▼
     LinkedIn     Instagram        X          YouTube        + any new
     post or      carousel +    single or   script, titles,  platform
     PDF carousel caption, Reel  thread     thumbnail idea,  (add a
                  script                    chapters, Short  playbook)
```

### Platform Playbooks
Each platform has a **playbook**: a Claude skill file that describes how that platform works.
- **Formats:** post types, length limits, aspect ratios, media types
- **Structure:** hook styles, body, call-to-action, hashtags/keywords
- **Tone and audience norms**
- **Timing defaults:** good posting windows, overridden by what works for you
- **What performs now:** refreshed monthly by an overnight research job, because platforms change
- **How to publish** (see the table below)

**Adding a platform = adding one playbook.** Blink drafts the playbook from research and you approve it once. No code change.

### Cadence: proposed, not asked
- Blink proposes a **weekly content plan** on Sunday night, based on your goals (from setup), how busy your calendar is, and what performed.
- You approve or adjust once; then it runs. It learns from skips and results, and **doesn't ask how often to post**.

### Publishing: direct where possible, one-tap everywhere else

| Platform | Direct publishing | Notes |
|---|---|---|
| **LinkedIn** | ✅ Own profile via official API | No partner review needed for your own profile (per vendor guides) |
| **Instagram** | ✅ via Graph API | Needs a **Creator or Business** account linked to a Facebook Page; free; your own account needs no app review |
| **X** | ✅ pay-per-use | ~$0.015 per post, ~$0.20 if it contains a link; no free tier for new developers |
| **YouTube** | ⚠️ | API uploads from an unaudited project are **locked to private**. Use one-tap handoff, or upload as private draft and publish in YouTube |
| **TikTok, Threads, others** | One-tap handoff | Until an API is worth adding |

**One-tap handoff:** on iPhone, tap **Post**. The caption is copied, media is saved to Photos, and the platform's app opens. You paste and post in seconds. This works for every platform, so **no platform is ever blocked**.

### Media
- Carousels and thumbnails are laid out from **templates** with your brand, using your photos and screenshots.
- Reel/Short/YouTube **scripts come with shot lists**, so recording is quick.

---

## 6. Battery: designed in from day one

**Main rule: the server works, the devices sleep.** All AI, research, mail checking and planning run on the backend. Phones and Macs only show results.

### iPhone
| Area | Decision |
|---|---|
| Background work | **No polling.** Updates arrive by push (paid account) or when you open the app. With a free account it uses system-scheduled background refresh, which iOS keeps rare |
| Live Activities | Countdowns use the **system-rendered timer text**, so no updates are sent each minute. Pushes only on real changes (start, moved, ended). End the activity as soon as the moment passes. Use low-priority pushes when timing isn't critical (iOS throttles bursts anyway) |
| Blink in the Dynamic Island | **Still images**, swapped only on state changes |
| Blink in the app | Animates only while on screen. Off in **Low Power Mode** and **Reduce Motion** |
| Widgets | A **day's timeline computed once**; reload only when data changes |
| Network | **Small, batched sync** (only what changed), no open connections in the background |
| Budget capture | Event-driven Shortcuts automations (Apple Pay / SMS), with **zero background cost** in between |
| Location, camera, mic | Not used in the background. The mic is used only while you hold to talk |
| On-device AI | **None**: no local models running on the phone |

### Mac
| Area | Decision |
|---|---|
| App | **Native Swift**, no Electron, no web views in the notch |
| Notch when idle | **No continuous rendering.** A blink is a single short animation scheduled every 20–40 s; otherwise 0 fps |
| Pause rules | Animations stop when the lid is closed, the display sleeps, a full-screen app or video is running, or the Mac is on battery below 20% (**calm mode**: still eyes, no glow pulses) |
| Data | **Event-driven:** calendar change notifications from EventKit, pushes from the server. No timers polling the server; on battery, a gentle fallback check at most every 15 min |
| Timers | Coalesced, with tolerance, so macOS can batch wake-ups |

### Targets (measured, not guessed)
- **Mac:** near-zero CPU when idle; "Low" in Activity Monitor's Energy column.
- **iPhone:** the app should not appear in *Settings → Battery* as a significant user on a normal day.
- Measured with **Xcode Instruments** (Energy Log) and **MetricKit** reports in each phase's "done when…" checklist.

---

## 7. Architecture additions

```
Apps (Mac + iOS)
  Blink renderer (Rive on Mac/app · still poses in Island/widgets)
  Context-aware Blink panel · Ask-First cards · ⌘K / ⌥Space
        │
Backend
  Event bus ──► Blink state service   (decides Blink's state from events + your focus/sleep)
            ──► Ask-First queue
  Model router  (fast / balanced / best → Haiku / Sonnet / Opus; overrides; cost meter)
  Content engine  (core message → Platform Playbooks → drafts → publish or handoff)
  Playbook refresher (monthly research per platform)
  Memory: "What Blink knows" (preferences, voice, goals — editable)
```

---

## 8. Decisions made (so you don't have to answer them)
- Mascot: **Blink**, eyes-in-the-notch concept, Rive for animation, still poses for iPhone surfaces.
- App: **native SwiftUI**, Liquid Glass on navigation only, Blink panel on every screen.
- Models: **Auto router** with manual Opus / Sonnet / Haiku switch.
- Content: **platform playbooks**; cadence proposed weekly by Blink; direct publish where allowed, one-tap handoff everywhere else.
- Setup: **one conversation**, then it learns.
- Battery: server does the work; no polling; still poses in the Island; calm mode on Mac.

Facts only you can provide come up once, in the setup conversation (which banks send alerts, which mail account, wake time). They are not separate questions.
