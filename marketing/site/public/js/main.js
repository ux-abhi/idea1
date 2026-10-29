// Blink site: the eyes, the hero notch and the small demos.
// Every demo works without GSAP; motion runs only when GSAP loaded and the visitor allows motion.
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const motion = !reduce && window.gsap && window.ScrollTrigger;
if (!motion) document.documentElement.classList.remove("intro-on"); // no GSAP: no welcome screen, the page as it is
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const POP = "cubic-bezier(.34, 1.56, .64, 1)";

/* ---------- Eyes: look toward the pointer, blink now and then ---------- */
if (!reduce) {
  let raf = 0, px = 0, py = 0;
  const aim = () => {
    raf = 0;
    for (const el of $$(".eyes-look")) {
      const r = el.getBoundingClientRect();
      if (r.bottom < 0 || r.top > innerHeight || !r.width) continue;
      const dx = px - (r.left + r.width / 2), dy = py - (r.top + r.height / 2);
      const d = Math.hypot(dx, dy) || 1, k = Math.min(1, d / 360);
      el.style.transform = `translate(${(dx / d) * k * r.width * 0.06}px, ${(dy / d) * k * r.height * 0.1}px)`;
    }
  };
  addEventListener("pointermove", (e) => {
    px = e.clientX; py = e.clientY;
    if (!raf) raf = requestAnimationFrame(aim);
  }, { passive: true });

  const blink = () => {
    if (!document.hidden) {
      for (const img of $$(".eyes-look img:not(.css-blink)")) { // the footer's eyes blink in CSS
        img.animate([{ transform: "scaleY(1)" }, { transform: "scaleY(.08)" }, { transform: "scaleY(1)" }],
          { duration: 170, easing: "cubic-bezier(.4, 0, .2, 1)" });
      }
    }
    setTimeout(blink, 2600 + Math.random() * 3600);
  };
  setTimeout(blink, 1600);
}

/* ---------- Film: click to play, with sound; the browser's controls pause it ---------- */
const video = $("#film-video"), playBtn = $("#film-play");
const playLabel = playBtn.querySelector("span:last-child");
const playFilm = () => {
  playBtn.hidden = true;
  video.controls = true;
  video.play().catch(() => {}); // the visitor can still press play in the controls
};
playBtn.addEventListener("click", playFilm);
$("[data-play-film]").addEventListener("click", playFilm);
// At the end: back to the poster with "Play again".
video.addEventListener("ended", () => {
  video.controls = false;
  video.currentTime = 0;
  playLabel.textContent = "Play again";
  playBtn.hidden = false;
});
// Scrolled away while playing: pause (the controls resume it); sound shouldn't follow you down the page.
new IntersectionObserver(([entry]) => {
  if (!entry.isIntersecting && !video.paused) video.pause();
}, { threshold: 0.25 }).observe(video);

/* ---------- Moods ---------- */
const moods = $$(".mood");
for (const m of moods) new Image().src = `assets/eyes-${m.dataset.mood}.png`; // no flash on switch
for (const b of moods) {
  b.addEventListener("click", () => {
    for (const o of moods) o.setAttribute("aria-pressed", String(o === b));
    const idle = b.dataset.mood === "idle";
    const colour = getComputedStyle(b).getPropertyValue("--c").trim();
    const img = $("#peek-eyes");
    img.src = `assets/eyes-${b.dataset.mood}.png`;
    $("#peek-text").textContent = b.dataset.text;
    $("#peek-text").style.color = idle ? "" : colour;
    $("#peek").style.setProperty("--mood-glow", idle ? "" : colour);
    if (!reduce) img.animate([{ transform: "scale(.85)" }, { transform: "scale(1)" }], { duration: 420, easing: POP });
  });
}

/* ---------- Ask: model picker ---------- */
const models = $$(".model");
for (const b of models) {
  b.addEventListener("click", () => {
    for (const o of models) o.setAttribute("aria-pressed", String(o === b));
    $("#model-note").textContent = b.dataset.note;
  });
}

/* ---------- Mail: click a row to teach Blink about the sender ---------- */
const mail = $("#mail-list");
for (const row of $$(".row", mail)) {
  row.addEventListener("click", () => {
    const imp = !row.classList.contains("imp");
    row.classList.toggle("imp", imp);
    row.setAttribute("aria-pressed", String(imp));
    $(".verdict", row).textContent = imp ? "Important from now on" : "Not important from now on";
    mail.classList.add("sorted");
  });
}

/* ---------- Clipboard and search: real search boxes (at most `max` rows show, so the tile never grows) ---------- */
const finder = (input, rows, count, max, text = (r) => r.textContent) => {
  const list = rows[0].parentElement;
  // announce: only for the visitor's own typing; the auto-demo stays silent for screen readers.
  const filter = (announce = true) => {
    const q = input.value.trim().toLowerCase();
    let shown = 0, matches = 0;
    for (const r of rows) {
      const m = text(r).toLowerCase().includes(q);
      r.hidden = !(m && shown < max);
      shown += !r.hidden;
      matches += m;
    }
    if (announce) count.textContent = q ? `${matches} match “${q}”.` : "";
    list.toggleAttribute("data-none", !shown);
    return shown;
  };
  filter(false);
  list.style.minHeight = `${list.offsetHeight}px`; // keep the height of a full list
  input.addEventListener("input", () => filter());
  return filter;
};
const clipInput = $("#clip-search"), clipRows = $$("#clip-list li");
const filterClips = finder(clipInput, clipRows, $("#clip-count"), 3);

const findInput = $("#find-search"), findRows = $$("#find-list .hit");
const selectHit = (dir) => {
  const shown = findRows.filter((r) => !r.hidden);
  const at = shown.findIndex((r) => r.classList.contains("on"));
  for (const r of findRows) r.classList.remove("on");
  shown[dir === 0 ? 0 : (at + dir + shown.length) % shown.length]?.classList.add("on");
};
const filterFind = finder(findInput, findRows, $("#find-count"), 4, (r) => r.dataset.k);
findInput.addEventListener("input", () => selectHit(0));
findInput.addEventListener("keydown", (e) => {
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    selectHit(e.key === "ArrowDown" ? 1 : -1);
    $("#find-count").textContent = $("#find-list .hit.on .t")?.textContent ?? "";
  }
});

// While a tile is on screen, its box types a few searches by itself, like someone using it. Anything the visitor
// does in the tile (click, drag, key, Tab in) stops it for good.
const typeLoop = (input, words, apply, hold) => {
  let alive = true, onScreen = false, timer = 0;
  const stop = () => { alive = false; clearTimeout(timer); };
  const tile = input.closest(".tile");
  for (const type of ["pointerdown", "keydown", "focusin"]) tile.addEventListener(type, stop);
  new IntersectionObserver(([e]) => (onScreen = e.isIntersecting), { threshold: 0.5 }).observe(tile);
  const wait = (ms) => new Promise((r) => (timer = setTimeout(r, ms)));
  const set = (v) => { if (alive) { input.value = v; apply(); } };
  (async () => {
    for (let i = 0; alive; i++) {
      while (alive && (!onScreen || document.hidden)) await wait(400);
      const w = words[i % words.length];
      for (let n = input.value.length; n > 0 && alive; n--) { set(input.value.slice(0, n - 1)); await wait(45); }
      await wait(250);
      for (let n = 1; n <= w.length && alive; n++) { set(w.slice(0, n)); await wait(110); }
      await (hold ? hold(wait, () => alive) : wait(2200));
    }
  })();
};
if (!reduce) {
  typeLoop(clipInput, ["invoice", "notes", "pdf"], () => filterClips(false));
  typeLoop(findInput, ["thesis", "weber", "launch"], () => { filterFind(false); selectHit(0); }, async (wait, alive) => {
    await wait(700);
    for (let k = 0; k < 2 && alive(); k++) { selectHit(1); await wait(650); } // ↓ ↓, as if with the arrow keys
    await wait(900);
  });
}
for (const li of clipRows) {
  li.addEventListener("dragstart", (e) => e.dataTransfer.setData("text/plain", $(".t", li).textContent));
}

/* ---------- Habits: tick today's circle ---------- */
// base = streak before today; today's tick adds one. Milestones match the app: 7, 30, 100.
const HABITS = [
  { name: "Read 20 minutes", week: [1, 1, 1, 1, 1, 1], today: true, base: 20 },
  { name: "Gym", week: [1, 1, 1, 0, 1, 1], today: true, base: 2 },
  { name: "No phone after 11", week: [1, 1, 1, 1, 1, 1], today: false, base: 6 },
];
const CHECK = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 6.2 5 8.6 9.5 3.6"/></svg>';
const habitsEl = $("#habits");
habitsEl.innerHTML = HABITS.map((h, i) => `
  <div class="habit">
    <span class="name">${h.name}</span>
    <span class="week">${h.week.map((d) => `<span class="dot${d ? " on" : ""}">${d ? CHECK : ""}</span>`).join("")}<button type="button" class="dot" data-i="${i}" aria-label="${h.name}, done today"></button></span>
    <span class="streak" aria-live="polite"></span>
  </div>`).join("");
const renderHabit = (i, celebrate) => {
  const h = HABITS[i], btn = $(`button[data-i="${i}"]`), streak = btn.closest(".habit").querySelector(".streak");
  const n = h.base + (h.today ? 1 : 0), milestone = h.today && [7, 30, 100].includes(n);
  btn.classList.toggle("on", h.today);
  btn.setAttribute("aria-pressed", String(h.today));
  btn.innerHTML = h.today ? CHECK : "";
  streak.textContent = `${n} days`;
  streak.classList.toggle("gold", milestone);
  if (milestone && celebrate && !reduce) burst(streak);
};
const burst = (el) => {
  for (let k = 0; k < 10; k++) {
    const s = document.createElement("span");
    s.className = "spark";
    el.append(s);
    const a = (k / 10) * Math.PI * 2, r = 26 + Math.random() * 16;
    s.animate([{ transform: "translate(0,0) scale(1)", opacity: 1 }, { transform: `translate(${Math.cos(a) * r}px, ${Math.sin(a) * r}px) scale(.3)`, opacity: 0 }],
      { duration: 700, easing: "cubic-bezier(.22, 1, .36, 1)" }).onfinish = () => s.remove();
  }
  el.animate([{ transform: "scale(1)" }, { transform: "scale(1.25)" }, { transform: "scale(1)" }], { duration: 450, easing: POP });
};
HABITS.forEach((_, i) => renderHabit(i, false));
habitsEl.addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-i]");
  if (!btn) return;
  const h = HABITS[btn.dataset.i];
  h.today = !h.today;
  renderHabit(+btn.dataset.i, true);
});

/* ---------- Money charts ---------- */
const DAYS = [32, 18, 45, 12, 60, 28, 22, 38, 15, 52, 26, 30, 19, 41]; // the film's numbers
const BUDGET = 40, TOP = 64;
$("#bars").innerHTML = DAYS.map((v) => `<span class="${v > BUDGET ? "over" : ""}" style="height:${(v / TOP) * 100}%"></span>`).join("")
  + `<div class="budget-line" style="bottom:${(BUDGET / TOP) * 100}%"><em>€${BUDGET} a day</em></div>`;

/* ---------- Showcase: one feature at a time (ARIA tabs, arrow keys move and select) ---------- */
const tabs = $$('[role="tab"]');
const intros = {}; // panel id → its demo's entrance; each runs once, the first time the panel shows
const select = (tab, focus) => {
  for (const t of tabs) {
    const on = t === tab;
    t.setAttribute("aria-selected", String(on));
    t.tabIndex = on ? 0 : -1;
    $("#" + t.getAttribute("aria-controls")).hidden = !on;
  }
  if (focus) tab.focus();
  tab.scrollIntoView({ block: "nearest", inline: "nearest" }); // keeps the picked pill in view on phones
  const id = tab.getAttribute("aria-controls");
  intros[id]?.();
  delete intros[id];
};
for (const t of tabs) t.addEventListener("click", () => select(t));
$(".tabs").addEventListener("keydown", (e) => {
  const i = tabs.indexOf(document.activeElement);
  const step = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
  const next = e.key === "Home" ? 0 : e.key === "End" ? tabs.length - 1 : step ? (i + step + tabs.length) % tabs.length : -1;
  if (i < 0 || next < 0) return;
  e.preventDefault();
  select(tabs[next], true);
});
// Without JS every panel shows, one under the other; with it they share one stage.
$(".showcase").dataset.ready = "";
for (const t of tabs.slice(1)) $("#" + t.getAttribute("aria-controls")).hidden = true;

/* ---------- Ask-First: Touch ID demo ---------- */
const touch = $("#touch"), touchBtn = $("#touch-btn"), touchLabel = $("#touch-label");
touchBtn.addEventListener("click", () => {
  if (touch.classList.contains("busy")) return;
  if (touch.classList.contains("done")) {
    touch.classList.remove("done");
    touchLabel.classList.remove("ok");
    touchLabel.textContent = "Click to approve with Touch ID";
    $(".sr-only", touchBtn).textContent = "Approve with Touch ID (demo)";
    return;
  }
  touch.classList.add("busy");
  touchLabel.textContent = "Checking Touch ID…";
  setTimeout(() => {
    touch.classList.replace("busy", "done");
    touchLabel.classList.add("ok");
    touchLabel.textContent = "Approved. Sends on the 15th.";
    $(".sr-only", touchBtn).textContent = "Reset the demo";
  }, reduce ? 0 : 900);
});

/* ---------- Hero: the notch shows one moment of the day after another; the buttons under the Mac pick one ---------- */
// Mood colours from tokens.json. Example people and places only, nothing personal.
const MOMENTS = [
  { tab: "Calendar", mood: "var(--blue-fill)", kind: "Next up", when: "in 10 min", q: "Design review with Sam",
    a: "The call link is on your clipboard. Your notes from last week are open.", acts: ["Join call", "Snooze 5 min"] },
  { tab: "Mail", mood: "var(--red)", kind: "Needs you", when: "2 min ago", q: "Your landlord replied",
    a: "Wants to confirm the Friday visit. I drafted a yes; nothing is sent until you say so.", acts: ["Review draft", "Later"] },
  { tab: "Clipboard", mood: "var(--mint)", kind: "Clipboard", when: "⌃⌥V", q: "“invoice” · 3 matches",
    a: "INV-2041.pdf, copied yesterday at 16:02. Press Return to paste it.", acts: ["Paste", "Show all"] },
  { tab: "Money", mood: "var(--orange)", kind: "Spent", when: "Apple Pay", q: "€12.40 at Café Lumen",
    a: "Food is at 80% of this week's limit, with three days to go.", acts: ["OK", "Change category"] },
  { tab: "Habits", mood: "var(--green)", kind: "Habit", when: "18:00", q: "Gym · day 6 in a row",
    a: "You usually go at six. Your evening is free until eight.", acts: ["Done", "Skip today"] },
];
const heroNotch = $("#hero-notch"), momentEl = $(".moment", heroNotch), momentBar = $("#hero-moments");
let momentAt = 0, picked = false;
const fillMoment = (m) => {
  heroNotch.style.setProperty("--mood", m.mood);
  $(".m-kind", momentEl).textContent = m.kind;
  $(".m-when", momentEl).textContent = m.when;
  $(".notch-q", momentEl).textContent = m.q;
  $(".notch-a", momentEl).textContent = m.a;
  $$(".m-act", momentEl).forEach((el, i) => (el.textContent = m.acts[i]));
};
const showMoment = (i) => {
  momentAt = i;
  $$(".moment-btn", momentBar).forEach((b, j) => b.setAttribute("aria-pressed", String(j === i)));
  if (!motion) return fillMoment(MOMENTS[i]);
  gsap.timeline()
    .to(momentEl, { autoAlpha: 0, y: -6, filter: "blur(4px)", duration: 0.18, ease: "power2.in", onComplete: () => fillMoment(MOMENTS[i]) })
    .fromTo(momentEl, { y: 8 }, { autoAlpha: 1, y: 0, filter: "blur(0px)", duration: 0.4, ease: "power3.out" })
    .fromTo($(".eyes-look img", heroNotch), { scaleY: 1 }, { scaleY: 0.08, duration: 0.08, yoyo: true, repeat: 1, ease: "power2.inOut" }, 0.05);
};
for (const [i, m] of MOMENTS.entries()) {
  const b = document.createElement("button");
  b.type = "button"; b.className = "moment-btn"; b.style.setProperty("--mood", m.mood);
  b.innerHTML = `<i aria-hidden="true"></i>${m.tab}`;
  b.setAttribute("aria-pressed", String(i === 0));
  // A pick stops the tour, so the visitor can read it.
  b.addEventListener("click", () => { picked = true; momentBar.classList.remove("auto"); momentEl.setAttribute("aria-live", "polite"); if (i !== momentAt) showMoment(i); });
  momentBar.append(b);
}
// The bar's CSS fill sets the pace (paused on hover and focus); when it is full, the next moment comes.
momentBar.addEventListener("animationend", () => showMoment((momentAt + 1) % MOMENTS.length));
// Off screen, the tour waits (no repaints nobody sees).
new IntersectionObserver(([e]) => momentBar.classList.toggle("away", !e.isIntersecting)).observe($("#hero-mac"));
function startMoments() { if (!reduce && !picked) momentBar.classList.add("auto"); }
fillMoment(MOMENTS[0]);
if (!motion) startMoments();

/* ---------- Scroll motion (GSAP) ---------- */
if (!motion) mail.classList.add("sorted"); // static fallback: show the sorted inbox
if (motion) {
  gsap.registerPlugin(ScrollTrigger);
  const onEnter = (trigger, fn, start = "top 72%") => ScrollTrigger.create({ trigger, start, once: true, onEnter: fn });


  // Welcome → notch → page, scrubbed by the scroll while the hero holds still:
  // the black screen shrinks into the menu bar's notch and Blink's eyes fly in with it; then the hero comes up
  // under it, the Mac's notch opens and the highlights are drawn. Positions are measured, so any screen size lines up.
  const intro = $("#intro"), headNotch = $(".head-notch"), introEyes = $(".intro-eyes", intro);
  const header = $(".site-head");
  const box = (el) => el.getBoundingClientRect();
  gsap.set(".hero mark.hl", { "--hl": "0%" });
  const welcome = gsap.timeline({
    defaults: { ease: "none" },
    scrollTrigger: {
      trigger: ".hero", start: () => `top ${header.offsetHeight}px`, end: "+=150%", pin: true, scrub: 0.8,
      invalidateOnRefresh: true,
      onUpdate: (st) => { if (st.progress > 0.97) startMoments(); },
    },
  })
    // The words lift, blur and fade; the eyes stay, they are about to fly.
    .to(".intro-scroll", { autoAlpha: 0, duration: 0.1 }, 0)
    .to(".intro-hi-words", { autoAlpha: 0, y: -24, filter: "blur(6px)", duration: 0.18 }, 0)
    .to(".intro-name, .intro-what", { autoAlpha: 0, y: -24, filter: "blur(6px)", duration: 0.18 }, 0.06)
    .to(intro, {
      "--ix": () => `${box(headNotch).left}px`,
      "--ib": () => `${innerHeight - box(headNotch).bottom}px`,
      "--ir": "16px", duration: 0.5, ease: "power2.inOut",
    }, 0.1)
    .to(introEyes, {
      x: () => { const a = box(introEyes), b = box($(".eyes-look", headNotch)); return b.left + b.width / 2 - (a.left + a.width / 2); },
      y: () => { const a = box(introEyes), b = box($(".eyes-look", headNotch)); return b.top + b.height / 2 - (a.top + a.height / 2); },
      scale: () => box($(".eyes-look", headNotch)).width / box(introEyes).width,
      duration: 0.5, ease: "power2.inOut",
    }, 0.1)
    .set(intro, { autoAlpha: 0 }, 0.6)
    .from(".hero-in", { y: 40, opacity: 0, filter: "blur(10px)", duration: 0.25, stagger: 0.04, ease: "power2.out" }, 0.5)
    .from("#hero-mac, #hero-moments", { y: 120, scale: 0.94, opacity: 0, duration: 0.35, ease: "power2.out" }, 0.6)
    .fromTo(".screen", { "--p": 0 }, { "--p": 1, duration: 0.15, ease: "power2.inOut" }, 0.82)
    .to(".hero mark.hl", { "--hl": "100%", duration: 0.12, stagger: 0.06, ease: "power1.inOut" }, 0.8);
  // Opacity, not autoAlpha, above: the hero stays in the accessibility tree. Keyboard users don't scroll, so the first
  // Tab skips the welcome (the overlay would hide the focus ring).
  addEventListener("focusin", () => { const st = welcome.scrollTrigger; if (st.progress < 1) scrollTo(0, st.end); }, { once: true });

  // Section titles arrive word by word, once. The words stay one text run for screen readers.
  for (const h of $$(".head h2, .end h2")) {
    h.innerHTML = h.textContent.trim().split(/\s+/).map((w) => `<span class="word">${w}</span>`).join(" ");
    gsap.from($$(".word", h), { opacity: 0, yPercent: 40, filter: "blur(6px)", duration: 0.7, stagger: 0.05, ease: "power3.out",
      clearProps: "all", scrollTrigger: { trigger: h, start: "top 85%", once: true } });
  }

  // The film grows to full size as it comes up.
  gsap.fromTo(".film-frame", { scale: 0.9 }, { scale: 1, ease: "none", scrollTrigger: { trigger: ".film-frame", start: "top bottom", end: "top 30%", scrub: 0.6 } });

  // Bento: the tiles that enter together rise and unblur together, a short stagger apart.
  // Opacity, not autoAlpha, so demos not yet revealed stay reachable by Tab.
  gsap.set(".tile", { opacity: 0, y: 28, filter: "blur(8px)" });
  ScrollTrigger.batch(".tile", {
    start: "top 90%", once: true,
    onEnter: (tiles) => gsap.to(tiles, { opacity: 1, y: 0, filter: "blur(0px)", duration: 0.8, stagger: 0.08, ease: "power3.out", clearProps: "transform,filter" }),
  });

  // Ask: the answer arrives a beat after the tile.
  const answer = $("#ask-mock .bubble-a");
  gsap.set(answer, { autoAlpha: 0, y: 6 });
  onEnter("#ask-mock", () => gsap.to(answer, { autoAlpha: 1, y: 0, duration: 0.5, delay: 0.8, ease: "power3.out" }));

  // Mail: the noise steps back, the one that matters comes forward.
  onEnter(mail, () => setTimeout(() => mail.classList.add("sorted"), 700), "top 65%");

  // Showcase demos play once, when their panel first shows (Day when the section scrolls in).
  const dayIn = () => gsap.from("#day-mock .block", { scaleX: 0, duration: 0.7, delay: 0.15, stagger: 0.08, ease: "power3.out" });
  onEnter(".showcase", () => { if (intros.day) { delete intros.day; dayIn(); } });
  intros.day = dayIn;
  intros.money = () => {
    gsap.from("#bars span", { scaleY: 0, duration: 0.6, delay: 0.15, stagger: 0.035, ease: "power3.out" });
    const bal = $("#balance"), money = { v: 0 };
    gsap.to(money, { v: +bal.dataset.to, duration: 1.1, ease: "power3.out",
      onUpdate: () => (bal.textContent = money.v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })) });
  };
  intros.content = () => gsap.from("#content-mock .idea", { y: 16, opacity: 0, duration: 0.5, delay: 0.15, stagger: 0.07, ease: "power3.out", clearProps: "transform,opacity" });

  // Privacy: the Mac, the server and the AI come up in order, then the wires draw between them.
  gsap.timeline({ scrollTrigger: { trigger: "#diagram", start: "top 75%", once: true } })
    .from("#diagram .v-node", { y: 24, opacity: 0, duration: 0.6, stagger: 0.18, ease: "power3.out" })
    .from("#diagram .wire", matchMedia("(max-width: 820px)").matches   // the wires run down on phones
      ? { scaleY: 0, transformOrigin: "top", duration: 0.5, stagger: 0.2, ease: "power2.out" }
      : { scaleX: 0, transformOrigin: "left", duration: 0.5, stagger: 0.2, ease: "power2.out" }, 0.3)
    .from("#diagram .key", { scale: 0, rotate: -90, duration: 0.5, ease: "back.out(2)" }, 0.7);

  // Setup: the rail draws as you read down it; each step's card rises as the rail gets there.
  const mm = gsap.matchMedia();
  mm.add({ wide: "(min-width: 821px)", narrow: "(max-width: 820px)" }, ({ conditions: c }) => {
    gsap.fromTo("#flow .rail i", c.wide ? { scaleX: 0, scaleY: 1 } : { scaleY: 0, scaleX: 1 }, { scaleX: 1, scaleY: 1, ease: "none",
      scrollTrigger: { trigger: "#flow", start: c.wide ? "top 80%" : "top 70%", end: c.wide ? "top 30%" : "bottom 70%", scrub: 0.5 } });
  });
  gsap.set(".step", { opacity: 0, y: 28, filter: "blur(8px)" });
  ScrollTrigger.batch(".step", {
    start: "top 85%", once: true,
    onEnter: (steps) => gsap.to(steps, { opacity: 1, y: 0, filter: "blur(0px)", duration: 0.8, stagger: 0.15, ease: "power3.out", clearProps: "transform,filter" }),
  });
  // The installer ticks through its steps, and the meeting drops into the notch.
  gsap.from(".art-server .progress li", { opacity: 0, x: -8, duration: 0.4, stagger: 0.25, delay: 0.5, ease: "power2.out",
    scrollTrigger: { trigger: ".art-server", start: "top 80%", once: true } });
  gsap.from(".art-notch .mini-notch", { yPercent: -100, duration: 0.6, delay: 0.6, ease: "power3.out",
    scrollTrigger: { trigger: ".art-notch", start: "top 80%", once: true } });

  // Footer: the name rises into the screen's bottom edge as the page ends.
  gsap.fromTo(".wordmark", { yPercent: 45 }, { yPercent: 0, ease: "none", scrollTrigger: { trigger: ".site-foot", start: "top bottom", end: "bottom bottom", scrub: 0.6 } });

  // The header notch's eyes glance the way you scroll, then settle.
  const glancers = $$(".head-notch img");
  let settle = 0;
  ScrollTrigger.create({ start: 0, end: "max", onUpdate: (st) => {
    for (const img of glancers) img.style.translate = `0 ${st.direction * 9}%`;
    clearTimeout(settle);
    settle = setTimeout(() => { for (const img of glancers) img.style.translate = ""; }, 260);
  } });

  // The pin adds space above the content after the browser jumped to #waitlist etc.; jump again once laid out.
  document.fonts?.ready.then(() => { ScrollTrigger.refresh(); if (location.hash) document.getElementById(decodeURIComponent(location.hash.slice(1)))?.scrollIntoView(); });
}
