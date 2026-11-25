// © Pexilim
import { parseCall } from "./input.ts";
import { dateCell, newColumns, parseContacts, parseMails, planContacts, toCells } from "./tables.ts";

let n = 0;
const id = () => `c${n++}`;

Deno.test("rows by column name become checked cells, and a new Category value becomes an option", () => {
  const columns = newColumns([{ name: "Name", kind: "text" }, { name: "Status", kind: "category", options: ["New"] },
    { name: "Email", kind: "email" }, { name: "Due", kind: "date" }, { name: "Done", kind: "checkbox" }, { name: "Site", kind: "link" },
    { name: "Tags", kind: "tags" }, { name: "name", kind: "text" }, { name: "Deck", kind: "file" }], id);
  if (typeof columns === "string" || columns.length !== 8 || columns[7].kind !== "text") throw new Error("a duplicate name is dropped, a File column becomes text: " + JSON.stringify(columns));
  const { cells, columns: out, problems } = toCells([
    { name: "Studio North", status: "Contacted", Email: " Ana@North.Studio ", Due: "2026-11-24T15:00", Done: "yes", Site: "north.studio", Tags: ["#warm", "berlin"] },
    { Name: "Bad", Email: "not an email", Due: "2026-02-30", Site: "two words", Phone: "123" },
    { Phone: "only unknown" },
  ], columns, id);
  const status = out.find((c) => c.name === "Status")!;
  if (status.options?.map((o) => o.name).join() !== "New,Contacted") throw new Error("new option added");
  const first = cells[0];
  const byName = (name: string) => first[out.find((c) => c.name === name)!.id];
  if (byName("Status") !== status.options![1].id) throw new Error("category holds the option id");
  if (byName("Email") !== "ana@north.studio" || byName("Due") !== "2026-11-24 15:00" || byName("Done") !== "true") throw new Error(JSON.stringify(first));
  if (byName("Site") !== "https://north.studio" || byName("Tags") !== "warm, berlin") throw new Error(JSON.stringify(first));
  if (cells.length !== 2 || Object.keys(cells[1]).length !== 1) throw new Error("bad values left out, empty rows dropped: " + JSON.stringify(cells));
  if (problems.length !== 4 || !problems.at(-1)!.includes("Phone")) throw new Error(JSON.stringify(problems));
  if (columns.find((c) => c.name === "Status")!.options!.length !== 1) throw new Error("the table's own columns aren't changed in place");
});

Deno.test("dates are real days, with an optional time", () => {
  if (dateCell("2026-11-24") !== "2026-11-24" || dateCell("2026-11-24 09:05") !== "2026-11-24 09:05") throw new Error("good dates");
  for (const bad of ["2026-02-30", "2026-11-24 24:00", "24.11.2026", "tomorrow", "2026-11-24 9:00"]) if (dateCell(bad) !== null) throw new Error(bad);
});

Deno.test("contacts: real addresses, no do-not-mail, no duplicates, the 500 limit, and flags", () => {
  const contacts = parseContacts([
    { email: "Ana@North.Studio", name: "Ana", fields: { Company: "North" }, research: { summary: "Brand studio", facts: ["a", "b", "c", "d", "e", "f"], source: "javascript:x" } },
    { email: "ana@north.studio" }, { email: "info@west.com" }, { email: "bo@blocked.com" }, { email: "cy@old.com" }, { email: "nope" },
    { email: "dee@have.com" },
  ]);
  if (typeof contacts === "string") throw new Error(contacts);
  if (contacts[0].fields.company !== "North" || (contacts[0].card.facts as string[]).length !== 5 || contacts[0].card.source !== "") throw new Error(JSON.stringify(contacts[0]));
  if (Object.keys(contacts[2].card).length) throw new Error("no research, no card");
  const { rows, problems } = planContacts(contacts, new Set(["dee@have.com"]), new Set(["@blocked.com"]), new Set(["cy@old.com"]));
  if (rows.map((r) => r.email).join() !== "ana@north.studio,info@west.com,cy@old.com") throw new Error(JSON.stringify(rows));
  if (rows[1].flags.join() !== "role" || rows[2].flags.join() !== "mailed_recently" || problems.length !== 4) throw new Error(JSON.stringify({ rows, problems }));
  const many = Array.from({ length: 499 }, (_, i) => `p${i}@x.com`);
  if (planContacts(parseContacts([{ email: "a@b.com" }, { email: "c@d.com" }]) as never, new Set(many), new Set(), new Set()).rows.length !== 1) throw new Error("500 at most");
  if (typeof parseContacts([]) !== "string" || typeof parseContacts(Array(501).fill({ email: "a@b.com" })) !== "string") throw new Error("1–500");
});

Deno.test("table and bulk mail calls need real ids and say what's wrong", () => {
  const uuid = "6f1c1e9a-2b4d-4c8e-9a1f-0e2d3c4b5a69";
  if (typeof parseCall("get_table", { table_id: "Leads" }) !== "string") throw new Error("a name isn't an id");
  if (typeof parseCall("add_rows", { table_id: uuid, rows: Array(151).fill({ a: 1 }) }) !== "string") throw new Error("150 a call");
  if (typeof parseCall("create_table", { space_id: uuid, name: "Leads", columns: [] }) !== "string") throw new Error("needs a column");
  const made = parseCall("create_table", { space_id: uuid.toUpperCase(), name: " Leads ", columns: [{ name: "Name", kind: "text" }] });
  if (typeof made === "string" || made.tool !== "create_table" || made.space !== uuid || made.rows.length !== 0) throw new Error(JSON.stringify(made));
  if (typeof parseCall("add_bulk_mail_contacts", { bulk_mail_id: uuid, contacts: "ana@x.com" }) !== "string") throw new Error("a list");
});

Deno.test("written mails: one per contact, complete, at most 50 a call", () => {
  const uuid = "6f1c1e9a-2b4d-4c8e-9a1f-0e2d3c4b5a69";
  const call = parseCall("write_bulk_mails", { bulk_mail_id: uuid, mails: [
    { contact_id: uuid, subject: " Your\nstudio ", body: "Hi Ana,\r\n\r\nShort note." }, { contact_id: uuid, subject: "Again", body: "Twice" },
    { contact_id: "x", subject: "", body: "no subject" },
  ] });
  if (typeof call === "string" || call.tool !== "write_bulk_mails" || call.mails.length !== 1) throw new Error(JSON.stringify(call));
  if (call.mails[0].subject !== "Your studio" || call.mails[0].body !== "Hi Ana,\n\nShort note.") throw new Error(JSON.stringify(call.mails[0]));
  if (typeof parseCall("write_bulk_mails", { bulk_mail_id: uuid, mails: [{ contact_id: "ana", subject: "s", body: "b" }] }) !== "string") throw new Error("ids only");
  if (typeof parseMails(Array(51).fill({ contact_id: uuid, subject: "s", body: "b" })) !== "string") throw new Error("50 a call");
});
