// © Pexilim
// What Claude or ChatGPT write into Space tables and bulk mails, checked the way Blink checks it on the Mac
// (SpaceTable.cells(from:), the bulk mail contact checks of ADR-0003 §3). Pure, for tests; index.ts does the reads and
// writes, always for the link's owner only.

export const KINDS = ["text", "category", "tags", "checkbox", "date", "email", "link"] as const;
export type Kind = typeof KINDS[number] | "file";
export type Option = { id: string; name: string; color: string };
export type Column = { id: string; name: string; kind: Kind; options?: Option[] };

// Byte limits sit below the database's (8 KB a row or contact field set, 20 KB a block), which counts jsonb's own spacing.
export const ROW_LIMIT = 2000, COLUMN_LIMIT = 30, CELL_LIMIT = 1000, ROW_BYTES = 7600, BLOCK_BYTES = 19000, CONTACT_LIMIT = 500;
export const bytes = (v: unknown) => new TextEncoder().encode(JSON.stringify(v)).length;
const COLORS = ["gray", "brown", "red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink"];
const EMAIL = /^[^@\s,;<>"]+@[^@\s,;<>"]+\.[^@\s,;<>".]{2,}$/;
const ROLES = new Set(["info", "contact", "hello", "office", "admin", "support", "sales", "team", "mail", "noreply", "no-reply",
  "donotreply", "billing", "jobs", "careers", "press", "marketing"]);

export const clip = (v: unknown, max: number) => (typeof v === "string" ? v : typeof v === "number" || typeof v === "boolean" ? String(v) : "")
  .replace(/\s+/g, " ").trim().slice(0, max);
export const newID = () => crypto.randomUUID().slice(0, 8);

/** "2026-11-24" or "2026-11-24 15:00" (a "T" is fine too) as Blink stores a Date cell; null when it isn't a real day. */
export function dateCell(v: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?$/.exec(v);
  if (!m) return null;
  const [y, mo, d] = [+m[1], +m[2], +m[3]];
  const day = new Date(Date.UTC(y, mo - 1, d));
  if (day.getUTCFullYear() !== y || day.getUTCMonth() !== mo - 1 || day.getUTCDate() !== d) return null;
  if (m[4] === undefined) return v.slice(0, 10);
  return +m[4] < 24 && +m[5] < 60 ? `${v.slice(0, 10)} ${m[4]}:${m[5]}` : null;
}

/** New columns for a table: names unique, kinds Blink knows (never File), Category options named once. */
export function newColumns(raw: unknown, id = newID): Column[] | string {
  if (!Array.isArray(raw) || !raw.length) return "A table needs at least one column.";
  const columns: Column[] = [];
  for (const c of raw.slice(0, COLUMN_LIMIT) as Record<string, unknown>[]) {
    const name = clip(c?.name, 60);
    if (!name || columns.some((x) => x.name.toLowerCase() === name.toLowerCase())) continue;
    const kind = (KINDS as readonly string[]).includes(String(c?.kind)) ? c.kind as Kind : "text";
    const column: Column = { id: id(), name, kind };
    if (kind === "category") {
      const names = [...new Set((Array.isArray(c.options) ? c.options : []).map((o) => clip(o, 40)).filter(Boolean))].slice(0, 30);
      column.options = names.map((n, i) => ({ id: id(), name: n, color: COLORS[(i + 4) % COLORS.length] }));
    }
    columns.push(column);
  }
  return columns.length ? columns : "A table needs at least one column with a name.";
}

/** Rows given by column name → cells by column id, each value checked for its column's kind. A Category value that
 *  isn't an option yet becomes one. Returns the columns (with any new options) and every value that was left out. */
export function toCells(rows: Record<string, unknown>[], columns: Column[], id = newID) {
  const out = columns.map((c) => ({ ...c, options: c.options ? [...c.options] : c.options }));
  const byName = new Map(out.map((c) => [c.name.toLowerCase(), c]));
  const problems: string[] = [], unknown = new Set<string>();
  const cells: Record<string, string>[] = [];
  rows.forEach((row, index) => {
    const cell: Record<string, string> = {};
    for (const [key, value] of Object.entries(row ?? {})) {
      const column = byName.get(key.trim().toLowerCase());
      if (!column) { unknown.add(clip(key, 60)); continue; }
      let v = Array.isArray(value) ? value.map((x) => clip(x, 60)).filter(Boolean).join(", ") : clip(value, CELL_LIMIT);
      if (!v) continue;
      switch (column.kind) {
        case "file": continue; // files are only added by the owner, in Blink
        case "checkbox":
          if (!/^(true|yes|y|1|x|done|✓)$/i.test(v)) continue;
          v = "true"; break;
        case "date": {
          const d = dateCell(v);
          if (!d) { problems.push(`Row ${index + 1}: “${v.slice(0, 40)}” isn't a date like 2026-11-24 or 2026-11-24 15:00.`); continue; }
          v = d; break;
        }
        case "email":
          v = v.toLowerCase();
          if (!EMAIL.test(v)) { problems.push(`Row ${index + 1}: “${v.slice(0, 60)}” isn't an email address.`); continue; }
          break;
        case "link":
          if (!/^https?:\/\//i.test(v)) {
            if (/\s/.test(v) || !v.includes(".")) { problems.push(`Row ${index + 1}: “${v.slice(0, 60)}” isn't a web address.`); continue; }
            v = "https://" + v;
          }
          break;
        case "tags":
          v = v.split(",").map((t) => t.trim().replace(/^#/, "")).filter(Boolean).join(", "); break;
        case "category": {
          const options = column.options ?? (column.options = []);
          const name = v.slice(0, 40);
          let option = options.find((o) => o.name.toLowerCase() === name.toLowerCase());
          if (!option) {
            option = { id: id(), name, color: COLORS[(options.length + 4) % COLORS.length] };
            options.push(option);
          }
          v = option.id; break;
        }
      }
      cell[column.id] = v;
    }
    if (!Object.keys(cell).length) return;
    if (bytes(cell) > ROW_BYTES) { problems.push(`Row ${index + 1} is too long (8 KB a row); left out.`); return; }
    cells.push(cell);
  });
  if (unknown.size) problems.push(`No column called ${[...unknown].slice(0, 5).map((n) => `“${n}”`).join(", ")}; those values were left out.`);
  return { cells, columns: out, problems };
}

/** A cell as the owner sees it: a Category's option name, a ticked box as "Yes", a file by its name. */
export function display(raw: string | undefined, column: Column): string {
  if (!raw) return "";
  if (column.kind === "category") return column.options?.find((o) => o.id === raw)?.name ?? "";
  if (column.kind === "checkbox") return raw === "true" ? "Yes" : "";
  if (column.kind === "file") return raw.split("|").slice(1).join("|");
  return raw;
}

/** Mails Claude wrote for contacts: one-line subjects, plain bodies, complete (no "[Company]" left in), one per contact. */
export function parseMails(raw: unknown): { id: string; subject: string; body: string }[] | string {
  if (!Array.isArray(raw) || !raw.length) return "Give at least one mail.";
  if (raw.length > 50) return "Up to 50 mails a call; send the rest in another call.";
  const seen = new Set<string>();
  const mails = (raw as Record<string, unknown>[]).map((m) => ({
    id: typeof m?.contact_id === "string" ? m.contact_id.trim().toLowerCase() : "",
    subject: clip(m?.subject, 300),
    body: (typeof m?.body === "string" ? m.body : "").replace(/\r\n?/g, "\n").trim().slice(0, 8000),
  })).filter((m) => m.id && m.subject && m.body && !seen.has(m.id) && seen.add(m.id));
  return mails.length ? mails : "Each mail needs a contact_id, a subject and a body.";
}

export type Contact = { email: string; name: string; fields: Record<string, string>; card: Record<string, unknown> };

/** A contact list from Claude, checked: real addresses, short fields, an optional research card that the mail writer
 *  then uses instead of reading the company's website (ADR-0003 §2, path C). */
export function parseContacts(raw: unknown): Contact[] | string {
  if (!Array.isArray(raw) || !raw.length) return "Give at least one contact with an email.";
  if (raw.length > CONTACT_LIMIT) return `Up to ${CONTACT_LIMIT} contacts at a time.`;
  return (raw as Record<string, unknown>[]).map((c) => {
    const fields: Record<string, string> = {};
    for (const [k, v] of Object.entries((c?.fields && typeof c.fields === "object" ? c.fields : {}) as Record<string, unknown>).slice(0, 20)) {
      const key = clip(k, 60).toLowerCase(), value = clip(v, 500);
      if (key && value && bytes({ ...fields, [key]: value }) <= ROW_BYTES) fields[key] = value;
    }
    const r = (c?.research && typeof c.research === "object" ? c.research : {}) as Record<string, unknown>;
    const summary = clip(r.summary, 400);
    const facts = (Array.isArray(r.facts) ? r.facts : []).map((f) => clip(f, 200)).filter(Boolean).slice(0, 5);
    const source = /^https?:\/\/\S+$/.test(clip(r.source, 300)) ? clip(r.source, 300) : "";
    return { email: clip(c?.email, 320).toLowerCase(), name: clip(c?.name, 200), fields,
      card: summary || facts.length ? { summary, facts, source } : {} };
  });
}

/** Which contacts go in and with what flags, with a line for every one left out (none dropped silently). */
export function planContacts(contacts: Contact[], have: Set<string>, blocked: Set<string>, recent: Set<string>) {
  const problems: string[] = [], rows: (Contact & { flags: string[] })[] = [], seen = new Set(have);
  for (const c of contacts) {
    if (!EMAIL.test(c.email)) { problems.push(`“${c.email.slice(0, 60) || "no email"}” isn't an email address.`); continue; }
    if (blocked.has(c.email) || blocked.has("@" + c.email.split("@")[1])) { problems.push(`${c.email} is on the do-not-mail list.`); continue; }
    if (seen.has(c.email)) { problems.push(`${c.email} is already in this bulk mail.`); continue; }
    if (seen.size >= CONTACT_LIMIT) { problems.push(`The rest didn't fit: a bulk mail holds up to ${CONTACT_LIMIT} people.`); break; }
    seen.add(c.email);
    rows.push({ ...c, flags: [...(ROLES.has(c.email.split("@")[0]) ? ["role"] : []), ...(recent.has(c.email) ? ["mailed_recently"] : [])] });
  }
  return { rows, problems };
}
