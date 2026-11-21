# ADR-0005: Product direction: Blink keeps you on track

- Status: accepted (owner, 2026-11-21: "rest is fine"; Tasks and Notes left as they are)
- Date: 2026-11-21

## The problem

**"I planned it, and still didn't do it."**

People who run their own work (creators, freelancers, indie founders, students with side projects) keep their plans
in many places: Notion, Reminders, Notes, mail, the calendar, a spreadsheet. Two things go wrong:

1. **Plans go quiet.** Tools hold plans but never bring them back at the moment they matter. A meeting is scheduled,
   then forgotten; finding the details means checking several apps and opening a browser.
2. **Setting up a system is work.** Flexible tools must be built by hand, so people give up or keep a system they
   don't trust.

## What people told us (2026-11-21)

- The owner's CA: "It's useful for me because I forget the meetings." "Sometimes I have too many tasks; at the end of the
  day I forget how much I've done." "Most people don't even open Notion."
- A friend: the money feature, seeing her current transactions and who she paid, matters most to her.

Three everyday jobs follow, all "keeping you on track":

1. **Don't let me forget:** meetings and anything due come back at the right moment.
2. **Show me what I did:** an end-of-day recap of what was done (tasks ticked, meetings had, mail handled), so a busy
   day feels like progress.
3. **Where did my money go:** who I paid, how, and what's left, filled in from Apple Pay taps and typed spends.
4. **Reach many people, personally:** a solo person writing to dozens of founders, clients or studios (with a CV or
   portfolio) can't write each mail by hand. Bulk Mail (ADR-0003) writes one personal mail per person from a list,
   for the owner to review and approve. The owner: "I can automate this using Claude. Claude can give me a list. I can
   just upload the list here, and it can do that."

And one rule for the design: **people don't open apps, so Blink comes to them** (the notch, notifications, widgets, the
Lock Screen) and **fills itself in** (calendar, Apple Pay, mail, ticks), instead of waiting to be opened and typed into.

## Who it's for (year one)

One person running their own work, with no team keeping them on track, on their **Mac and iPhone as one system**. The
owner is the first user.

## The promise

**Plan anything in a Space. Blink keeps you on track: your day, your work, your money.**

Notion gives you a place for your plans. Blink makes sure they happen, and makes you faster while they do. It comes to
you on whichever device you're on.

## Why Blink is different

| Others | Blink |
|---|---|
| Structure tools (Notion) don't remind you | Anything with a time comes back to you: the notch before it's due, Today, the calendar |
| Reminder tools (Reminders, Things) have no structure | Spaces with cards seen as table, board, calendar or canvas (ADR-0004) |
| AI chats (ChatGPT, Claude) forget | AI builds and changes your Spaces and cards, and they stay |
| Web apps are a tab you forget, and people don't open them | Blink comes to you: the notch on the Mac; notifications, widgets, the Lock Screen and the Dynamic Island on the iPhone |
| Productivity tools don't show progress | An end-of-day recap of what you did |
| Money apps need a bank login or manual work | Spends fill in from Apple Pay taps; no bank connection |
| Your data feeds someone else | Your own server now; Blink Cloud later, without ads or training on your plans |

Example, a meeting: Blink knows it's at 15:00. At 14:50 the notch shows it with the join link and the notes from last
time, one click to join. Afterwards: "Capture notes? Follow-up?" and what was agreed becomes cards with dates, which
come back when they're due. No searching through apps, no browser.

## Principles

1. **One connected system, never separate apps.** Everything is a card in a Space, or links to one. Mail, meetings,
   notes, voice and AI all turn into cards; dated cards all come back through the notch, Today and Calendar. A new
   feature that doesn't connect to cards and time doesn't get built.
2. **Faster, not busier.** Every feature must save the owner steps (fewer apps, fewer clicks, no browser). If it adds
   work, it's wrong.
3. **Reminds, never acts for you.** Blink organises and reminds. It never posts or sends on its own; mail goes out only
   after the owner's own review and Touch ID.
4. **Design from one language.** Apple-native windows, the notch with its own personality. Mockups first, then build;
   no screen redesigned piece by piece.
5. **Depth over breadth.** Finish the core (Spaces, cards, time, the notch, the AI command) before anything new.

## What stays and what changes now

The owner uses the notch for creating tasks, notes and reminders and for meetings, so those stay easy to reach.

| Keep | Fold in | Park | Remove |
|---|---|---|---|
| Today (dashboard and evening recap), Spaces, Tasks, Notes, reminders, Calendar and meeting heads-up, Inbox (triage, mail → card), Bulk Mail, Money, Clipboard history, the notch, dictation, voice commands, Claude (MCP), the model router | Habits & Goals → the evening check-in and a habit board in Today (§Habits); weekly goals and Plan my week → dated cards and a Monday check-in; Focus timer → the Space timer block; Activity log → the evening recap | Image generation; draft-quality statistics (in Settings, out of sight) | Content, Apify, Read My Page, Instagram analysis |

- **Sidebar order:** **Today** always first (the dashboard), then **Spaces**, then the rest (Inbox, Calendar, Tasks,
  Notes, Money, Clipboard), then Settings.
- **Tasks and Notes stay exactly as they are** (owner, 2026-11-21): tasks carry their reminders, and the notch already
  understands whether something is a task, reminder or note and files it. No work on merging them.
- **Core, not optional:** **Money** (who you paid, how, what's left), the **end-of-day recap**, and **Bulk Mail**.

### Habits: Blink asks, kindly

Habits stop being a page to open. Once each evening the notch (by voice if the owner likes) asks about the day's
habits together: "Did you get to the gym today?"

- **Yes:** a pixel lights up, one warm line.
- **No, I forgot:** "That's okay, one day doesn't undo anything. Want to pick a time tomorrow?" The answer becomes a
  card with a time, and the notch reminds them tomorrow.
- **Rest day:** no judgement; it doesn't count against them.

Grounded in research: self-compassion after a lapse raises motivation to improve (Breines & Chen, 2012); one missed
day barely affects habit formation (Lally et al., 2010), while broken streaks demotivate (Silverman & Barasch, 2023),
so Blink shows consistency ("4 of the last 7 days") and never a streak that resets to zero; deciding when and where
raises follow-through (implementation intentions, Gollwitzer & Sheeran, 2006). Guard rails: one check-in a night,
skippable with one click, quiet hours, short and never guilt-tripping. The pixel board stays as a card in Today and a
block for any Space; answers feed the evening recap.
- **Goes:** the Content section and content board block, Apify, the `page` function and Read My Page (ADR-0004 §6).
- **Waits:** Blink Cloud, until Google's verification is through (ADR-0001). Self-hosting stays the setup until then.

## Roadmap (in order, each step usable on its own)

0. **Bulk Mail sending** (ADR-0003 step 3): one Touch ID approves a batch; the server sends slowly within daily limits,
   pauses itself on bounces or errors, and stops for anyone who replies. Then **Claude fills Bulk Mail through MCP**
   (ADR-0003 step 4): a list made in Claude goes straight into a bulk mail, no copy and paste.

1. **Design language:** mockups of a Space page, a board, a card panel, Today and the notch reminder, approved
   before building screens.
2. **Cards and views** (ADR-0004 steps 1–2): properties you name (text, URL, date and time, file, category, chips,
   checkbox), the card panel, Table, Board and Calendar views with filters.
3. **Time and reminders** (ADR-0004 step 3): dated cards in Today, Tasks and Calendar, notch heads-ups, done
   everywhere; the meeting flow above.
4. **The AI command** (ADR-0004 steps 5 and 7): build and change boards by asking, turn mail, notes and meetings into
   cards, from the notch, voice and Claude.
5. **Connect what's there:** mail → card, note → cards, a habit as a repeating card, Bulk Mail from a collection, and
   the **end-of-day recap** (done cards, meetings, mail, spends) in the notch and as an evening notification.
6. **Content moves to cards**, then Content and Apify are removed (ADR-0004 step 4).
7. **The iPhone app**, connected to the same data: reminders and meetings on the Lock Screen and Dynamic Island,
   Apple Pay spends, Today, quick capture by voice, the evening recap. Needs the paid Apple Developer account (push,
   Live Activities, TestFlight).
8. **When Google approves:** Blink Cloud and onboarding, then 20 beta users like the owner.

## How we'll know it works

- **Day one:** a new user makes a Space, a card with a time comes back to them through the notch, and they act on it.
- **Week one:** they're still opening Blink and acting on its reminders a week later.
- **Evening:** people read their recap and feel the day counted.
- **Money:** people can say who they paid this week without opening a bank app.
- **The owner:** stops checking several apps to find what's next.

## Not now

Teams and shared Spaces, automatic posting or sending, social analytics, a full mail client, a template marketplace
(after Blink Cloud).
