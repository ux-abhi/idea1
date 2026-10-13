// © Pexilim
import { corsFor, parseSignup } from "./input.ts";

Deno.test("signups need a real-looking email and consent; the honeypot catches bots", () => {
  const ok = parseSignup({ email: "  Sam@Example.COM ", consent: true, website: "" });
  if (typeof ok === "string" || ok.email !== "sam@example.com" || ok.source !== "site") throw new Error(JSON.stringify(ok));
  if (parseSignup({ email: "sam@example.com", consent: true, website: "http://spam" }) !== "bot") throw new Error("honeypot");
  for (const bad of [{ email: "sam@example.com" }, { email: "sam@example.com", consent: "yes" }, { email: "nope", consent: true },
                     { email: "a@b", consent: true }, { email: `${"a".repeat(250)}@x.com`, consent: true }, null]) {
    if (typeof parseSignup(bad) !== "string" || parseSignup(bad) === "bot") throw new Error(`accepted ${JSON.stringify(bad)}`);
  }
  const src = parseSignup({ email: "a@b.co", consent: true, source: "Product Hunt!" });
  if (typeof src === "string" || src.source !== "site") throw new Error("source not cleaned");
});

Deno.test("only our own site gets CORS", () => {
  if (corsFor("https://blink.pexilim.com")["Access-Control-Allow-Origin"] !== "https://blink.pexilim.com") throw new Error("site");
  if (corsFor("https://evil.example")["Access-Control-Allow-Origin"] !== "https://blink.pexilim.com") throw new Error("other");
});
