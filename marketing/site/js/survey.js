// © Pexilim
// survey.html: five quick questions, one at a time (Typeform-style). A one-choice question moves on by itself; tap-all
// questions and the note move on with OK or Enter; number keys pick. Answers are saved after every step, with the code
// from the person's confirm link (?t=…), so stopping halfway still counts. Every question is optional.
(() => {
  const form = document.getElementById("survey");
  if (!form) return;
  const status = document.getElementById("survey-status"), next = document.getElementById("survey-next");
  const back = document.getElementById("survey-back"), bar = document.querySelector(".survey .bar");
  const done = document.getElementById("survey-done");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const token = new URLSearchParams(location.search).get("t");
  const all = [...form.querySelectorAll(".q")];
  if (!token) {
    all.forEach((s) => { s.hidden = true; });
    document.querySelector(".survey-nav").hidden = true;
    status.textContent = "This page needs the link from your email. Confirm your email first, or join on the home page.";
    return;
  }

  // The notch question only for people who want to test.
  const steps = () => all.filter((s) => s.id !== "notch-step" || form.elements.beta.value === "yes");
  let at = 0;

  const answers = () => {
    const picked = (name) => [...form.querySelectorAll(`input[name="${name}"]:checked`)].map((i) => i.value);
    const notch = form.elements.beta.value === "yes" ? form.elements.notch.value : "";
    return {
      slips: picked("slips"), uses: picked("uses"), first: form.elements.first.value || null, pay: form.elements.pay.value || null,
      beta: form.elements.beta.value || null, notch: notch === "" ? null : notch === "true", note: form.elements.note.value.trim(),
    };
  };

  // Saved quietly after each step; the last save waits for the answer so the thank-you only shows when it's stored.
  let saving = Promise.resolve(true);
  const save = () => (saving = saving.then(async () => {
    try {
      const res = await fetch(window.BLINK_WAITLIST_ACTIONS_URL, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "answer", token, answers: answers() }) });
      const body = await res.json().catch(() => ({}));
      if (res.ok && body.ok) return true;
      status.textContent = body.error || "That didn't save. Try again in a minute.";
    } catch {
      status.textContent = "Can't reach Blink's server. Check your connection and try again.";
    }
    return false;
  }));

  const animate = (el, frames, ms) => reduce ? Promise.resolve() : el.animate(frames, { duration: ms, easing: "cubic-bezier(.22, 1, .36, 1)", fill: "both" }).finished;

  function paint() {
    const list = steps(), step = list[at];
    all.forEach((s) => { s.hidden = s !== step; });
    const multi = step.dataset.multi === "true";
    const chosen = step.querySelector("input:checked") || (step.dataset.name === "note" && form.elements.note.value.trim());
    next.textContent = at === list.length - 1 ? "Send" : chosen || !multi ? "OK" : "Skip";
    next.hidden = !multi && at !== list.length - 1 && !chosen;
    back.hidden = at === 0;
    const pct = Math.round((at / list.length) * 100);
    bar.style.setProperty("--p", `${pct}%`);
    bar.setAttribute("aria-valuenow", String(pct));
    (step.querySelector("textarea") || step.querySelector("legend")).focus({ preventScroll: true });
  }

  // One move at a time: a double tap, or a tap during the auto-advance, never skips a question.
  let busy = false;
  async function go(dir) {
    if (busy) return;
    busy = true;
    try {
      const list = steps();
      const from = list[at];
      if (dir > 0 && at === list.length - 1) return await finish();
      if (dir > 0) save();
      await animate(from, [{ opacity: 1, transform: "none" }, { opacity: 0, transform: `translateY(${dir > 0 ? -18 : 18}px)` }], 180);
      at = Math.max(0, Math.min(steps().length - 1, at + dir));
      paint();
      await animate(steps()[at], [{ opacity: 0, transform: `translateY(${dir > 0 ? 28 : -28}px)` }, { opacity: 1, transform: "none" }], 420);
    } finally {
      busy = false;
    }
  }

  async function finish() {
    next.disabled = true;
    status.textContent = "Sending…";
    save();
    if (!(await saving)) { next.disabled = false; return; }
    bar.style.setProperty("--p", "100%");
    document.getElementById("survey-done-text").textContent = form.elements.beta.value === "yes"
      ? "You're on the beta list. We'll email you when your copy is ready."
      : "This really helps. We'll email you when Blink is ready.";
    await animate(form, [{ opacity: 1 }, { opacity: 0 }], 200);
    form.hidden = true;
    done.hidden = false;
    done.focus({ preventScroll: true });
    await animate(done, [{ opacity: 0, transform: "scale(.96)" }, { opacity: 1, transform: "none" }], 500);
  }

  // A one-choice answer moves on by itself, after the chip has had a moment to light up. Only for a tap or a number key:
  // arrow keys also change a radio, and someone listening through the options must not be moved on.
  let advancing = 0, picked = false;
  form.addEventListener("pointerdown", (event) => { picked = Boolean(event.target.closest(".choice")); });
  form.addEventListener("change", (event) => {
    paint();
    const tapped = picked;
    picked = false;
    if (event.target.type === "radio" && tapped) {
      clearTimeout(advancing);
      advancing = setTimeout(() => go(1), reduce ? 0 : 380);
    }
  });
  next.addEventListener("click", () => go(1));
  back.addEventListener("click", () => go(-1));
  form.addEventListener("submit", (event) => { event.preventDefault(); go(1); });

  // Keys: 1–9 pick an answer on this step, Enter goes on (Shift+Enter makes a new line in the note).
  document.addEventListener("keydown", (event) => {
    if (form.hidden || event.metaKey || event.ctrlKey || event.altKey) return;
    const step = steps()[at];
    if (event.target.closest("a, button")) return;   // Enter on Back, a link or the skip link does its own thing
    const typing = event.target.tagName === "TEXTAREA";
    if (event.key === "Enter" && !(typing && event.shiftKey)) { event.preventDefault(); go(1); return; }
    if (!typing && /^[1-9]$/.test(event.key)) {
      const input = step.querySelectorAll("input")[Number(event.key) - 1];
      if (input) { picked = true; input.checked = input.type === "radio" ? true : !input.checked; input.dispatchEvent(new Event("change", { bubbles: true })); }
    }
  });

  paint();
})();
