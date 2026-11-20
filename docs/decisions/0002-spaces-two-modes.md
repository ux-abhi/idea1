# ADR-0002: Spaces as the place to think: Canvas and Page modes, content inside Spaces, templates later

- Status: proposed (design agreed in conversation with the owner, 2026-11-20; review before building)
- Date: 2026-11-20

## Context

Blink has a Spaces canvas (FigJam-like, ARCHITECTURE §35, space canvas prefs: edit in place, never navigate away) and a
separate Content section in the sidebar (ideas, drafts, posted). The owner wants content to stop being its own place:
a Space is where they ideate and plan, and whatever belongs to it (notes, tasks, posts, links, images) is attached
there. They also want a structured, Notion-like way to work in a Space next to the free canvas, and, long term, Space
templates that people can make, share and sell.

What exists today (`SpaceCanvas.swift`, `space_node`): canvas cards of kind project, task, note, reminder, image, post,
heading and section; each task, note, reminder and post card points at the real item (`ref`), never a copy. Tasks,
notes and posts already carry a Space link (`segment_id`). There is no link (URL) card and no page view.

## Decision

### 1. One set of things, linked to Spaces

- Tasks, notes, reminders and posts live in one place each (Tasks, Notes, Content data) and may be linked to a Space.
  A Space links to them; it never owns a separate copy. Edit a task in the Space or in Tasks: it's the same task.
- Anything linked shows a small **Space badge** where it appears elsewhere (e.g. a task in Tasks shows "UXabhi").
- **Posts are items tagged Content.** Tasks, Today and Calendar show dated posts with a **Content** tag and a filter
  chip ("Content"), which is the global view across all Spaces.
- **The Content sidebar section goes away** once the Content tag, the filter and attaching posts in Spaces work. Its
  pieces move: voice and brief into Space setup (§4), ideas and drafts onto Space boards, the posting buttons onto the
  post card and the post's own sheet.

### 2. Two modes per Space

- **Canvas** (today's, kept as it is): free and visual.
- **Page** (new, Notion-like): a page built from blocks, top to bottom.
- A **Canvas | Page** toggle in the Space toolbar. A new Space opens in Canvas; after that, in the mode used last.
- Both modes show the same linked items. The Page lists everything linked to the Space; the Canvas shows what has
  been placed on it, with "Add to canvas" on anything not placed yet (so a Space with 200 tasks isn't 200 cards).

### 3. Adding things: right-click and the side panel

- **Canvas, right-click on empty space**: Add Note, Task, Reminder, Heading, Section, Image, **Link** (new: paste a URL;
  the card shows its title, site and preview image), and **Attach Content…**, which lists existing posts and ideas to
  link to this Space, plus **New Post…**.
- **Page**: a "/" menu and a "+" side panel with the same list as blocks: heading, text, task table, content board,
  linked note, link, image, and small plain "fun" blocks (timer, stopwatch, more later). Links and images are Page
  blocks as well as canvas cards (owner, 2026-11-20).
- Blocks that show items are **live views**, not copies: a task table lists the Space's tasks (tick one, it's ticked
  everywhere); a **content board** shows the Space's posts in columns Idea → Draft → Ready → Posted.
- Open question (owner, later): how a content board looks on the Canvas (a card that opens the board, or the posts as
  cards).

### 4. "What's this Space for?" and AI-built Spaces

- New Space asks one question: what it's for.
  - **A brand or page** (e.g. "UXabhi, my design Instagram"): the Space gets **its own voice, brief and social
    account**, and its posts are written as that brand.
  - **A project or plan**: it uses the owner's main voice.
  - **General** (ideas, scratch): no voice setup.
- From the answer, Blink drafts the first version: Page blocks (a content board for a brand, a task table for a
  project), a starter Canvas, and the setup steps the Space needs ("connect Instagram to read your posts"). The owner
  edits from there. Nothing is posted or sent; drafts only, as everywhere in Blink.
- **When a block needs something** (e.g. the Instagram reader key for a content board), it asks right there, with a
  link to the setting, instead of failing silently.

### 5. Claude builds Spaces too (MCP)

- Blink's MCP connection (today: read the day and mail summaries, add tasks and notes) gains Space tools:
  `create_space` (with purpose), `add_block`, `add_items` (tasks, notes, post ideas, links), all linked to the Space.
- Example in Claude: "Make me a Space for my UXabhi Instagram with a 4-week content plan and a redesign task list."
- Like every other connector action, what Claude creates can be kept, changed or removed in Blink; Claude can't post.

### 6. Built for templates from day one

Long-term goal (owner): people make Space templates, share them, and sell them, like Notion.

- A Space's **structure** is stored apart from its **contents**: Page blocks, Canvas layout (positions, sections,
  headings), the Space's purpose and setup steps. Items (the owner's tasks, notes, posts) are linked, not embedded.
- **Save as Template** writes the structure, plus optional sample items marked as samples, to a portable file
  (versioned JSON), never the owner's real data, voice or keys. **New Space from Template** reads it back and runs the
  template's setup steps (e.g. "this template uses a content board: connect Instagram").
- Sharing as a file or link works on self-hosted servers today. A gallery with selling needs accounts and payments:
  that waits for Blink Cloud (ADR-0001, parked), and uses the same file format, so templates made now keep working.

### 7. Data model (outline)

- `space_block (id, owner_id, segment_id, position, kind, data jsonb, created_at, updated_at)`: Page blocks in order.
  `kind`: heading, text, task_table, content_board, note_link, link, image. `data` holds only display settings
  (a heading's text, a board's filter), never copies of items. RLS owner-only, like every table.
- `space_node` gains kind `link` (URL, title, preview image kept in its fields).
- `segment` gains `purpose` (brand, project, general), `last_mode` (canvas, page) and, for brands, the Space's own
  voice and brief (or a `voice_profile` row per Space).
- Items keep using `segment_id` for their Space link; posts gain the **Content** tag through their kind, not a new
  table.
- Template file: `{ "version": 1, "purpose", "blocks": [...], "canvas": [...], "setup": [...], "samples": [...] }`.
- `rls.sql` gains checks for `space_block` (B sees nothing of A's) and for the new columns.

### 8. Habits & Goals replaces Content in the sidebar; "Plan my week"

Decided with the owner, 2026-11-20:

- The sidebar's Content entry becomes **Habits & Goals**:
  - **This week** at the top: the week's goals, each with a counter the owner ticks by hand ("Create 5 posts · 2 of 5",
    a +1 button) or a single check ("Finish the onboarding redesign"). Nothing counts automatically.
  - **Habits** below: ongoing daily habits, each shown as a **pixel grid** (a square per day, lit when done), following
    the habit rules in ARCHITECTURE §36.2 (no guilt, a missed day isn't a failure).
  - Today shows a small **This week** card with the goals' progress.
- **"Plan my week"** (said or typed in the notch, button in Habits & Goals, offered Sunday evening or Monday morning)
  is a short check-in: Blink asks "What do you want to get done this week?", turns the answers into this week's goals,
  and may suggest days around the calendar; nothing is added without the owner's OK. Friday: a short look back, and
  unfinished goals can move to next week.
- A goal can be linked to a Space ("5 posts" → UXabhi), like any other item.
- Tasks stays for one-off to-dos.

### 9. Design language (direction, pending mockups)

- The **main window and Settings** move to an Apple-native look (system fonts, sidebar and toolbars, the macOS glass
  materials, standard controls).
- The **notch** keeps its own personality (the eyes, pixel loader, pixel glow).
- **Pixels as Blink's signature, not a theme**: loaders, empty states and the habit grid; never a full pixel-art window.
- Next step: a few mockups (Habits & Goals, a Space in Page mode, Today) for the owner to judge before changing screens.

## Consequences

Easier:

- One place per project; content stops being a separate app inside the app.
- One model (items linked to Spaces, shown through blocks and cards) for everything that comes later: more block types,
  more modules, templates, Claude building Spaces.
- A clear story for selling: "Plan in Claude or in Blink; your Space has everything; share it as a template."

Harder:

- The Content page's jobs (voice, ideas, the week plan, Read My Page) must each find a new home before it's removed.
- Two views of the same Space must stay in sync and never duplicate items.
- A template format is a promise: changes need a version number and an upgrade path.

Build order (each step usable on its own):

1. **Content tag and filter** in Tasks, Today and Calendar, and **Space badges** on linked items.
1b. **Habits & Goals** section (weekly goals with manual counters, habits as pixel grids) and **Plan my week**.
2. **Right-click on the Canvas**: Attach Content…, New Post…, and the new **Link** card.
3. **Page mode**: the toggle, `space_block`, the "/" menu and side panel, blocks for heading, text, task table,
   content board and linked note.
4. **"What's this Space for?"**: purpose, per-Space voice and brief for brands, the AI-drafted first version.
5. **Move the Content page's remaining jobs** into Spaces, then remove the Content section.
6. **MCP Space tools** for Claude.
7. **Save as Template / New Space from Template** (file or link).
8. Later, with Blink Cloud: a template gallery and selling.

Open questions for the owner:

- How a content board appears on the Canvas. (§3)
- Mockups for the design language (§9) before any screen changes.
