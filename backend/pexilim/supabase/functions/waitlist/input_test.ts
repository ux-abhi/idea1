// © Pexilim
import { corsFor, parseAction, parseAnswer, parseSignup, sameSecret } from "./input.ts";

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

Deno.test("survey answers keep only known choices, need a confirm code, and cap the note", () => {
  const token = "12345678-1234-1234-1234-123456789abc";
  const got = parseAnswer({ action: "answer", token: token.toUpperCase(), answers: {
    slips: ["missed-emails", "missed-emails", "<script>", 4], uses: ["notion"], first: "meet", pay: "month-3-5",
    beta: "yes", notch: true, note: `  ${"x".repeat(2000)}  ` } });
  if (!got || got.token !== token) throw new Error("token");
  if (JSON.stringify(got.answers.slips) !== '["missed-emails"]') throw new Error(JSON.stringify(got.answers.slips));
  if (got.answers.first_feature !== "meet" || got.answers.pay !== "month-3-5" || got.answers.beta !== "yes") throw new Error("choices");
  if (got.answers.note?.length !== 1000) throw new Error("note cap");
  const odd = parseAnswer({ action: "answer", token, answers: { pay: "a million", beta: "sure", first: "teleport", notch: "yes" } });
  if (!odd || odd.answers.pay !== null || odd.answers.beta !== null || odd.answers.first_feature !== null || odd.answers.notch !== null) {
    throw new Error("unknown choices kept");
  }
  if (parseAnswer({ action: "answer", token: "nope", answers: {} }) !== null) throw new Error("bad token accepted");
  if (parseAnswer({ action: "confirm", token }) !== null) throw new Error("other action");
});
