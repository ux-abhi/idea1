// © Pexilim
import { corsFor, parseAction, parseSignup, sameSecret } from "./input.ts";

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
  if (corsFor("https://www.blinkk.app")["Access-Control-Allow-Origin"] !== "https://www.blinkk.app") throw new Error("site");
  if (corsFor("https://evil.example")["Access-Control-Allow-Origin"] !== "https://www.blinkk.app") throw new Error("other");
});

Deno.test("confirm and leave need a real token", () => {
  const id = "3f2a6c1e-8b4d-4e5f-9a7b-1c2d3e4f5a6b";
  if (parseAction({ action: "confirm", token: id.toUpperCase() })?.token !== id) throw new Error("confirm");
  if (parseAction({ action: "leave", token: id })?.kind !== "leave") throw new Error("leave");
  if (parseAction({ action: "delete", token: id }) || parseAction({ action: "confirm", token: "x' or 1=1" }) || parseAction(null)) throw new Error("accepted junk");
});

Deno.test("only the site's mailer gets the links", () => {
  const secret = "s".repeat(64);
  if (!sameSecret(secret, secret)) throw new Error("same");
  if (sameSecret("t".repeat(64), secret) || sameSecret(null, secret) || sameSecret(secret, undefined) || sameSecret("short", "short")) throw new Error("accepted");
});
