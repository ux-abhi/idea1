// © Pexilim
import { fetchPage, pageText, parseCard, privateAddress, safeHost, siteFor } from "./research.ts";

Deno.test("the site comes from a website column, else a company email's domain, never Gmail", () => {
  if (siteFor("ana@studio.com", {}) !== "https://studio.com/") throw new Error("domain");
  if (siteFor("ana@gmail.com", {}) !== null) throw new Error("gmail");
  if (siteFor("ana@gmail.com", { website: "http://www.Ana.design/work?x=1" }) !== "https://www.ana.design/") throw new Error("column");
});

Deno.test("only public host names are read, never the server's own network", () => {
  for (const bad of ["localhost", "10.0.0.1", "printer.local", "db.internal", "studio.com:8080", "intranet"]) {
    if (safeHost(bad)) throw new Error(bad);
  }
  if (!safeHost("studio.com") || !safeHost("www.studio.co.uk")) throw new Error("public");
  for (const ip of ["127.0.0.1", "10.1.2.3", "172.20.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "::1", "fd00::1", "fe80::1"]) {
    if (!privateAddress(ip)) throw new Error(ip);
  }
  if (privateAddress("93.184.216.34") || privateAddress("2606:4700::1")) throw new Error("public ip");
});

Deno.test("a name that resolves to a private address is never fetched", async () => {
  const page = await fetchPage("https://rebind.example.com/", (() => Promise.resolve(["10.0.0.5"])) as unknown as typeof Deno.resolveDns);
  if (page !== null) throw new Error("fetched a private address");
});

Deno.test("page text drops scripts and tags, keeps the words", () => {
  const text = pageText(`<title>Studio &amp; Co</title><meta name="description" content="Brand design"><script>alert(1)</script><p>We made the <b>museum</b> identity.</p>`);
  if (text !== "Studio & Co Brand design We made the museum identity.") throw new Error(text);
});

Deno.test("a card keeps at most 5 short facts, and nothing found is no card", () => {
  const card = parseCard(JSON.stringify({ summary: "Brand studio", facts: ["a", "b", "c", "d", "e", "f"] }), "https://studio.com/");
  if (card?.facts.length !== 5 || card.source !== "https://studio.com/") throw new Error(JSON.stringify(card));
  if (parseCard(JSON.stringify({ summary: "", facts: [] }), "x") !== null) throw new Error("empty card kept");
});

Deno.test("a name that doesn't exist is skipped without fetching", async () => {
  const missing = (() => Promise.reject(new Deno.errors.NotFound("no such name"))) as unknown as typeof Deno.resolveDns;
  if (await fetchPage("https://no-such-studio.example/", missing) !== null) throw new Error("fetched a name that doesn't exist");
});
