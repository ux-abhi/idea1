// © Pexilim
import { confirmEmail } from "./email.ts";

Deno.test("the confirmation email links both ways and escapes what it shows", () => {
  const mail = confirmEmail("https://x.example/confirm?t=a\"b", "https://x.example/unsubscribe?u=1");
  if (!mail.html.includes("https://x.example/confirm?t=a&quot;b") || mail.html.includes('t=a"b')) throw new Error("not escaped");
  if (!mail.html.includes("unsubscribe?u=1") || !mail.text.includes("Leave the waitlist: https://x.example/unsubscribe?u=1")) throw new Error("no unsubscribe");
  if (!mail.text.includes("Confirm my email: https://x.example/confirm")) throw new Error("text part");
});
