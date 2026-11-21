# ADR-0004: Cards and views: one set of things in Spaces, seen as a table, board, calendar or canvas

- Status: proposed (owner, 2026-11-21: "think more on this"; no sending or posting, reminders only; Notion-style
  properties the owner names)
- Date: 2026-11-21

## Context

The owner wants Spaces to become the place where everything happens (see ADR-0002, ADR-0003 §5, and the direction that
Spaces may become Blink's main surface). Three things came up together:

- The **Content** section and the content board block feel like a special case. The owner wants to build their own
  boards: their own columns, categories, filters and links, with content being just one board among others.
- **Apify** and the Instagram reading and analysis are not part of Blink's aim. They go.
- Cards that have a time ("we have to do this by Friday") should behave like tasks, the way Notion does it, but
  better: no setup, and Blink's own strengths (the notch, voice, AI, mail, approvals) on top.
- Later, boards and canvases should run automations. Not now, but the design must allow it.

Today a Space has a canvas (cards placed freely, pointing at real tasks, notes and posts) and a page of blocks,
including a **table** block (typed columns, rows, CSV) that bulk mail already reads from.

## Decision

### 1. One object: the card, in a collection

- A **collection** is the table block a Space already has: named, with typed columns. Its rows are **cards**.
- A card is data only. How it shows is up to the **view**. There is never a copy: change a card in one view and it's
  changed in all of them.
- **Properties** (columns), Notion-style, added from a card or the table header, each renamable and removable:
  - **Text** and **Long text** (a script, notes, a caption draft)
  - **URL** (opens in the browser) and **Email**
  - **Date** and **Time**: a day, a day and time, with an optional end
  - **File** (from the Space's files, or uploaded on the card)
  - **Category** (one choice) and **Chips** (several), shown as coloured chips. The owner adds, renames, recolours
    and reorders the options, such as Idea / Draft / Ready / Done or Reel / Carousel / Story
  - **Checkbox**
- Property and option names are the owner's own; nothing is fixed or built-in.
- Each collection can mark three columns with a **role**: its **Title**, its **Date** and its **Done** column. Roles
  are what let Blink understand any collection without special code (§3).

### 2. Views: table, board, calendar, canvas

- Every collection has one or more saved **views**, switched with tabs above it:
  - **Table:** rows and columns, as now.
  - **Board:** cards in columns grouped by a Category column; drag a card to change its value.
  - **Calendar:** cards on their Date; drag to another day or time; cards with a time and an end are time blocks.
  - **Canvas:** the Space's canvas can hold cards from any of its collections, next to stickies, links and pictures.
    It is the free view of the same cards, not a separate world.
- Each view keeps its own **filters** (such as "Platform is Instagram", "tagged #reel", "date this month",
  "not done"), its **sort**, and the columns it shows on cards.
- Clicking a card opens a **side panel** with every field, the long text and files, edited in place. The owner never
  navigates away (space canvas preferences).

### 3. Cards with a time act as tasks, with no setup

This is where Blink beats Notion, where you build a tasks database and relations yourself.

- Any card with a **Date** (its Date role) and not **Done** is **actionable**:
  - it shows in **Today** (due today or overdue), in **Calendar**, and in **Tasks** (one list of everything due,
    across all Spaces, grouped by Space);
  - the **notch** gives a heads-up before a timed card ("Post the Figma reel in 15 min") with the card's own actions;
  - ticking it done anywhere (notch, Today, Tasks, board) ticks its Done column.
- "Okay, we have to do this" works on anything: say it about a card, a line of text, a mail or a note, and Blink
  gives it a date (and a Space and collection), and it is a task from then on.
- Posts are just cards with a time: a Content board with Status, Platform, Date, the caption and media. When the date
  comes, the notch **reminds** the owner. Blink is not a social media tool: it never posts or sends from a card.
- Existing Blink tasks stay as they are for now; Tasks shows them together with actionable cards. Whether tasks later
  become cards in a home Space is a later decision (§8).

### 4. AI shapes boards; it never edits silently

- **Board builder:** "make this board my content calendar", "turn this into a hiring pipeline", "add a priority
  column", "group by platform". The AI returns a **plan** (columns to add or change, select options, roles, views,
  filters). Blink shows a short preview ("Adds 4 columns and a Calendar view, keeps your 12 cards") and applies it
  only on **Apply**. Nothing the owner wrote is deleted; removing a column is always the owner's own click.
- **On a card:** write it (fills the long text from the title, notes and the owner's writing voice), shorter, change
  tone, make an image.
- **On a board:** suggest ideas (adds cards in the first column), spread cards over the week (sets dates).
- **Turn this into cards:** a note, a text block, a mail or a meeting becomes cards in a chosen collection.
- The same works from the notch, by voice, and from Claude through MCP (`create_collection`, `apply_board_plan`,
  `add_cards`), always as a previewed plan or Ask-First card.

### 5. Automations later, designed in now

- Later, a collection can have **rules**: *when* (a card is added, moves to a column, its date arrives, a mail comes
  from one of its emails) → *if* (filters) → *then* (set a field, move it, remind, draft a mail, ask the AI, add to
  another collection). **Automations never send or post anything**: they organise and remind. (Mail is only ever
  sent by the owner, through Bulk Mail's own review, ADR-0003.)
- To allow this without a rewrite: card changes are recorded as events (who, what changed, when), and rules are data
  (`trigger`, `conditions`, `actions` as JSON), never code.
- Built-in behaviours come first and cover most needs: date → reminder, done → leaves Today, a card's emails → bulk
  mail from the collection (ADR-0003 §5).

### 6. Content and Apify go

| Today | After |
|---|---|
| Content in the sidebar | Removed |
| Posting buttons and publishing | Removed: Blink reminds, the owner posts in the app they use |
| Content board block | Removed; a Board view of a collection replaces it |
| Existing posts | Moved once into a "Content" collection in their Space (Status, Platform, Post at, Post, Media); posts with no Space go to a new Content Space |
| Content tag and filter in Tasks, Today, Calendar | Replaced by actionable cards (§3) |
| Writing voice and brief | Kept, in Settings › Writing; used by every AI write |
| Idea generator | "Suggest ideas" on a board |
| Image generation | "Make an image" on a card |
| Week plan | Already "Plan my week" in Habits & Goals |
| Apify, the `page` function, Read My Page, Instagram analysis | Removed, with the Apify key in Settings › Connections |

Old post data stays on the server until the owner has checked the move, then a migration removes it.

### 7. Data (outline)

- Collection: a `space_block` of kind `table`; its `data` gains `views` (`[{id, name, kind, group_by, date_column,
  filters, sort, shown}]`) and column `roles` (`title`, `date`, `done`). Category and Chips options live in
  the column (`options: [{id, name, color}]`, Apple system colours by name).
- Card: a `space_table_row`. For fast cross-Space queries (Today, Tasks, Calendar, notch) it gains server-side
  `title text`, `starts_at timestamptz`, `ends_at timestamptz`, `done boolean`, kept in step with the role columns,
  indexed by owner and date. RLS as every table; `rls.sql` checks for each new column.
- Cell limit raised for Long text (a post can be 3,000 characters), with a total row cap.
- Canvas: `space_node` gains kind `card` with `ref` → the row's id.
- Later: `card_event` (the change log) and `space_rule` (automations).

### 8. Open questions for the owner

- Should existing Blink tasks later become cards in a home Space, so there's only one kind of task? (Not part of this
  plan; Tasks shows both until then.)
- Which collections feed Today and Calendar: all of them by default (proposed), with a per-collection switch?

## Build order (each step usable on its own)

1. **Card basics:** properties (Long text, URL, Date and Time, File, Category, Chips, Checkbox), renamable with
   editable options; roles; the card side panel with "+ Add a property".
2. **Views:** Table, Board and Calendar tabs, filters and sort, saved views; `/board` and `/calendar` templates.
3. **Actionable cards:** dated cards in Today, Tasks and Calendar, notch heads-ups, done everywhere.
4. **Content moves to cards:** posts into a Content collection; remove the Content section, the content board block,
   Apify, the `page` function and Read My Page.
5. **AI:** the board builder (plan → preview → Apply), card and board actions, "turn this into cards".
6. **Canvas view:** cards from collections on the canvas.
7. **Universal command:** the notch, voice and Claude (MCP) for collections and cards.
8. Later: automations (§5), and Google Sheets as a collection's source.

## Consequences

- One model (cards in collections, shown through views) replaces Content, and later can absorb tasks: less special
  code, and everything the owner builds works with the notch, AI, mail and Calendar.
- Blink gets simpler (Apify, the `page` function and the Content page gone) while doing more.
- Views and roles must be designed carefully: a view that hides data must never look like data was lost, and the
  server-side date fields must always match the cells.
