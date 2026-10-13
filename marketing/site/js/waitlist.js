// Waitlist form: POSTs {email, website, source, consent} as JSON to window.BLINK_WAITLIST_URL (js/config.js).
// "You're on the list" only after a 200 with {ok: true}; anything else is an error the visitor can act on.

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// What the form says, given the server's reply. body is the parsed JSON, or null.
export function waitlistResult(status, body) {
  if (status === 200 && body?.ok === true) return { ok: true };
  const said = typeof body?.error === "string" && body.error.length <= 160 ? body.error : "";
  if (status === 429) return { ok: false, text: said || "Too many tries. Wait a minute, then try again." };
  if (status === 400) return { ok: false, text: said || "Check your email address and try again." };
  return { ok: false, text: "Couldn't reach the waitlist. Try again, or email hello@blinkk.app." };
}

// Checks before sending. Returns the field to fix and what to say, or null.
export function checkInput(email, consent) {
  if (!EMAIL.test(email)) return { field: "email", text: email ? "Enter an email address like you@example.com." : "Enter your email address." };
  if (!consent) return { field: "consent", text: "Tick the box so we can email you when Blink is ready." };
  return null;
}

const form = typeof document !== "undefined" && document.querySelector("#waitlist-form");
if (form) {
  const email = form.querySelector("#wl-email"), consent = form.querySelector("#wl-consent");
  const website = form.querySelector("#wl-website"), submit = form.querySelector("#wl-submit");
  const status = form.querySelector("#wl-status");

  const say = (text, kind) => {
    status.textContent = text;
    status.className = `wl-status ${kind}`;
  };
  const busy = (on) => {
    for (const el of [email, consent, submit]) el.disabled = on;
    submit.textContent = on ? "Joining…" : "Join the waitlist";
    form.setAttribute("aria-busy", String(on));
  };
  for (const el of [email, consent]) el.addEventListener("input", () => el.removeAttribute("aria-invalid"));

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (form.getAttribute("aria-busy") === "true") return;
    const url = window.BLINK_WAITLIST_URL;
    if (!url) {
      status.innerHTML = 'The waitlist opens soon — email <a href="mailto:hello@blinkk.app">hello@blinkk.app</a>';
      status.className = "wl-status";
      return;
    }
    const address = email.value.trim();
    const problem = checkInput(address, consent.checked);
    if (problem) {
      const field = problem.field === "email" ? email : consent;
      field.setAttribute("aria-invalid", "true");
      say(problem.text, "error");
      field.focus();
      return;
    }

    busy(true);
    say("Joining…", "");
    let result;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: address, website: website.value, source: "site", consent: true }),
        signal: AbortSignal.timeout(15000),
      });
      const body = await res.json().catch(() => null);
      result = waitlistResult(res.status, body);
    } catch {
      result = waitlistResult(0, null); // offline, blocked or timed out
    }
    busy(false);

    if (result.ok) {
      form.classList.add("done");
      say(`You're on the list. We'll email ${address} when Blink is ready.`, "ok");
      status.tabIndex = -1;
      status.focus(); // the button it replaced is gone
    } else {
      say(result.text, "error");
    }
  });
}
