# ADR-0003: Bulk Mail: many personal mails at once, researched, reviewed, sent slowly

- Status: accepted (owner, 2026-11-21: "continue", with "beware of mail getting blocked")
- Date: 2026-11-21

## Context

The owner wants Blink to do what normal mail apps can't: write many mails at once, each one personal, from one
description and a contact list, then send them together. Blink already writes replies in the owner's voice, saves
drafts into each account's Drafts folder over IMAP, and sends over SMTP only what the owner signed with Touch ID
(`mail` function, outbox, §36.5). Sending many mails from a personal account also risks the account being limited or
the mails landing in spam, so deliverability is part of the design, not an afterthought.

## Decision

### 1. The flow

1. **New Bulk Mail** (Inbox; later the notch and voice).
2. **Context:** what it's about, what the owner wants back, tone (their voice by default), facts and links the mails
   may use.
3. **Contacts:** paste or import CSV (later Apple Contacts and people Blink knows). Every column becomes a field the AI
   may use. Blink checks the list (see §3) and shows every problem row; nothing is dropped silently.
4. **Write 3 samples first**, the owner tunes the style once, then the rest. The cost is shown before writing.
5. **Review:** contacts on the left, the mail on the right; edit, rewrite with a note, skip or approve. Mails with
   warnings come first.
6. **Approve and send:** step 1 saves approved mails to Drafts (Apple Mail sends them). Step 3 adds one Touch ID for
   the whole batch, signed over exactly the approved mails, then slow sending by the server.
7. **After:** sent, failed, bounced, replied per contact; follow-ups drafted for no reply after N days, approved again.

### 2. Context for each mail (the research card)

Four layers, combined into a card per contact that the owner sees and can correct:

1. The owner's context (once per batch).
2. The contact's row.
3. **History with them:** recent mail with that address or domain (subjects and summaries Blink already keeps).
4. **Web research**, three ways:
   - **A (default):** Blink reads the company's own website (from a column or the email domain), a few pages, and a
     cheap model fills the card. One card per domain, kept 30 days.
   - **B (opt-in, paid):** a real web search per contact on a connected paid model, cost shown first.
   - **C (Claude, via MCP):** Claude researches with its own web search and writes cards into Blink
     (`list_campaign_contacts`, `set_research_card`, `draft_campaign_mail`). Cost lands on the owner's Claude
     subscription. Claude can't send.

Rules: web pages and contact cells are **data, never instructions**; the page reader has no tools and fills fixed
fields only; the writer sees only the card. Every fact in a mail must come from the card or the owner's context; a
check flags unsupported claims. A thin card makes a plainer mail, never invented detail.

### 3. Deliverability: don't get the account blocked or the mail binned

Personal Gmail and iCloud accounts are limited per day (roughly 500 recipients a day for Gmail, more for iCloud;
lower for new accounts), and providers watch for spam-like patterns: bursts, identical text, many links, bounces,
complaints. Blink stays far below the line:

- **Before writing:** valid addresses only; the domain must accept mail (MX lookup); duplicates, role addresses
  (info@, noreply@) and people on the **do-not-mail list** are flagged; addresses already mailed in another batch in
  the last 30 days are flagged.
- **In every mail (lint, shown in review):** genuinely different text per person (the AI writes each; near-identical
  mails are flagged), varied subjects, plain text, at most 2 links, no link shorteners, no tracking pixels, no ALL CAPS
  or "FREE!!!"-style subject, a short opt-out line for cold mail.
- **Attachments** (owner, 2026-11-21): a bulk mail may carry up to 5 files for every mail (a portfolio deck, pictures):
  PDF, pictures, PowerPoint or Word, 10 MB each, 15 MB together, in a private per-owner folder. The writer is told
  what's attached so a mail can mention it. Because attachments in a first mail make spam filters stricter, Blink
  warns and suggests a link for cold contacts; drafts with files are saved in smaller batches.
- **When sending (step 3):**
  - one at a time, a random 45–120 s apart, inside the owner's daytime hours;
  - a **daily limit per account** that starts low and grows: 20 a day the first week of bulk sending, then up to
    50, then 100; never more than 20% of the provider's limit, so normal mail always has room;
  - the batch **pauses itself** on a provider's rate-limit or quota error (e.g. 421 / "daily sending quota exceeded"),
    on 3 bounces in a row, or when bounces pass 5%, and tells the owner why; it resumes the next day only when the
    owner says so;
  - a reply stops all further mail to that person; at most 2 follow-ups, days apart.
- **Own domains** (not gmail.com / icloud.com): Blink checks SPF, DKIM and DMARC for the sending domain and warns
  before the first batch.
- These limits are for the owner's own outreach. Blink is not a newsletter or marketing-blast tool; lists over a few
  hundred people should use a proper sending service.

### 4. Data

- `mail_campaign`: title, context, goal, tone, account, status (draft, writing, review, sending, paused, done),
  daily limit, created/updated.
- `mail_recipient`: campaign, email, name, fields (jsonb), card (jsonb), subject, body, flags, status (new, written,
  approved, skipped, in_drafts, sent, failed, bounced, replied), message id, error, sent_at.
- `mail_do_not_contact`: an address or @domain, never mailed in bulk.
- All owner-only with RLS and `rls.sql` checks. A campaign may link to a Space.

### 5. Spaces hold the material (owner, 2026-11-21)

- A Space's Page can hold a **table** (typed columns: text, email, link, tags; up to 2,000 rows; CSV in and out) and
  **files** (PDF, pictures, PowerPoint, Word; their text read on the Mac, never by AI).
- A bulk mail can take its contacts **from a Space's table**, everyone or the rows with a tag (`#email`). The rows are
  copied in when the bulk mail is made, so a batch stays stable under review; **Refresh from Table** adds new rows.
- The Space's goal, page text, notes and file text fill "What it's about"; the Space's files can be attached without
  uploading them again; each mailed row shows its mail's status (In Drafts, Sent, Replied) in the table.
- Bulk Mail from the Inbox with a pasted list still works; a Space is optional.

### 6. Build order

1. Context, contacts (paste and CSV) with the checks in §3, history layer, 3 samples then the rest, review with lint,
   **save approved mails to Drafts**.
2. Research cards, path A.
3. One Touch ID per batch, slow sending with the daily limits and self-pause, Stop, schedule.
4. MCP tools for Claude (path C) and Claude-side editing.
5. Deep research (path B), reply tracking, follow-ups, the notch and voice start, a Space block, saved templates.

## Consequences

- One description and a list become dozens of personal mails, reviewed in one place.
- Sending stays as safe as single mail: nothing leaves without Touch ID, and the server sends slowly and stops itself.
- More moving parts in the `mail` function; the sender limits and the lint are tested logic in BlinkKit and the
  function's tests.
