// Blink site: the eyes, the hero notch and the small demos.
// Every demo works without GSAP; motion runs only when GSAP loaded and the visitor allows motion.
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const motion = !reduce && window.gsap && window.ScrollTrigger;
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
      for (const img of $$(".eyes-look img")) {
        img.animate([{ transform: "scaleY(1)" }, { transform: "scaleY(.08)" }, { transform: "scaleY(1)" }],
          { duration: 170, easing: "cubic-bezier(.4, 0, .2, 1)" });
      }
    }
    setTimeout(blink, 2600 + Math.random() * 3600);
  };
  setTimeout(blink, 1600);
}

/* ---------- Film: click to play, with sound ---------- */
const video = $("#film-video"), playBtn = $("#film-play");
const playFilm = () => {
  playBtn.hidden = true;
  video.controls = true;
  video.play().catch(() => {}); // the visitor can still press play in the controls
};
playBtn.addEventListener("click", playFilm);
$("[data-play-film]").addEventListener("click", playFilm);

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

/* ---------- Clipboard: real search, real drag ---------- */
const clipInput = $("#clip-search"), clipRows = $$("#clip-list li");
const filterClips = () => {
  const q = clipInput.value.trim().toLowerCase();
  let shown = 0;
  for (const li of clipRows) {
    const hit = li.textContent.toLowerCase().includes(q);
    li.hidden = !hit;
    shown += hit;
  }
  $("#clip-count").textContent = q ? `${shown} of ${clipRows.length} match “${q}”.` : `${clipRows.length} items. Try dragging one out.`;
};
clipInput.addEventListener("input", filterClips);
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

/* ---------- Scroll motion (GSAP) ---------- */
if (!motion) mail.classList.add("sorted"); // static fallback: show the sorted inbox
if (motion) {
  gsap.registerPlugin(ScrollTrigger);
  const onEnter = (trigger, fn, start = "top 72%") => ScrollTrigger.create({ trigger, start, once: true, onEnter: fn });
  const typeInto = (el, text, every = 0.05) => {
    const o = { n: 0 };
    return gsap.to(o, { n: text.length, duration: text.length * every, ease: "none", onUpdate: () => (el.textContent = text.slice(0, Math.round(o.n))) });
  };

  // Hero: one orchestrated entrance, then the notch opens as you scroll.
  gsap.from(".hero-in", { y: 24, autoAlpha: 0, filter: "blur(8px)", duration: 0.9, stagger: 0.08, ease: "power3.out" });
  gsap.from("#hero-mac", { y: 70, autoAlpha: 0, duration: 1.2, delay: 0.35, ease: "power3.out" });
  gsap.from("#hero-notch .eyes-look img", { scaleY: 0.08, duration: 0.35, delay: 1.2, ease: "power2.out" });

  const notch = $("#hero-notch"), q = $(".notch-q", notch), a = $(".notch-a", notch);
  q.textContent = "";
  a.innerHTML = a.dataset.words.split(" ").map((w) => `<span style="opacity:0">${w}</span>`).join(" ");
  let answered = false;
  gsap.fromTo(".screen", { "--p": 0 }, {
    "--p": 1, ease: "power2.inOut",
    scrollTrigger: {
      trigger: "#hero-mac", start: "top 58%", end: "top 8%", scrub: 0.6,
      onUpdate: (st) => {
        if (answered || st.progress < 0.9) return;
        answered = true;
        gsap.timeline()
          .add(typeInto(q, q.dataset.type))
          .to($$("span", a), { opacity: 1, duration: 0.25, stagger: 0.06 }, "+=0.35");
      },
    },
  });

  // Dark bands drop their notch into the next section, then Blink opens its eyes. Once each.
  for (const tab of $$(".notch-tab")) {
    gsap.timeline({ scrollTrigger: { trigger: tab, start: "top 92%", once: true } })
      .from(tab, { yPercent: -100, duration: 0.6, ease: "power3.out" })
      .from($("img", tab), { scaleY: 0.08, duration: 0.3, ease: "power2.out" }, "-=0.1");
  }

  // Bento: the tiles that enter together rise and unblur together, a short stagger apart.
  // Opacity, not autoAlpha, so demos not yet revealed stay reachable by Tab.
  gsap.set(".tile", { opacity: 0, y: 28, filter: "blur(8px)" });
  ScrollTrigger.batch(".tile", {
    start: "top 90%", once: true,
    onEnter: (tiles) => gsap.to(tiles, { opacity: 1, y: 0, filter: "blur(0px)", duration: 0.8, stagger: 0.08, ease: "power3.out", clearProps: "transform,filter" }),
  });

  // Ask: the keys press, then the answer arrives.
  const keys = $$("#ask-mock .keys kbd"), answer = $("#ask-mock .bubble-a");
  gsap.set(answer, { autoAlpha: 0, y: 6 });
  onEnter("#ask-mock", () => {
    keys.forEach((k, i) => setTimeout(() => k.classList.add("down"), 250 + i * 120));
    setTimeout(() => keys.forEach((k) => k.classList.remove("down")), 900);
    gsap.to(answer, { autoAlpha: 1, y: 0, duration: 0.5, delay: 1.3, ease: "power3.out" });
  });

  // Mail: the noise steps back, the one that matters comes forward.
  onEnter(mail, () => setTimeout(() => mail.classList.add("sorted"), 700), "top 65%");

  // Clipboard and ⌘K type their searches, unless the visitor already did.
  onEnter("#clip-mock", () => {
    if (clipInput.value || document.activeElement === clipInput) return;
    const word = "invoice", o = { n: 0 };
    gsap.to(o, { n: word.length, duration: 0.7, delay: 0.6, ease: "none", onUpdate: () => {
      if (document.activeElement === clipInput) return;
      clipInput.value = word.slice(0, Math.round(o.n));
      filterClips();
    } });
  });
  const typed = $("#palette-typed"), hits = $$("#search-mock .hit");
  typed.textContent = "";
  gsap.set(hits, { autoAlpha: 0, y: 8 });
  onEnter("#search-mock", () => {
    gsap.timeline({ delay: 0.5 }).add(typeInto(typed, "thesis", 0.09)).to(hits, { autoAlpha: 1, y: 0, duration: 0.4, stagger: 0.06, ease: "power3.out" });
  });

  // Day: the blocks snap into the timeline.
  gsap.from("#day-mock .block", { scaleX: 0, duration: 0.7, stagger: 0.08, ease: "power3.out", scrollTrigger: { trigger: "#day-mock .timeline", start: "top 80%", once: true } });

  // Money: bars grow, the balance counts up.
  gsap.from("#bars span", { scaleY: 0, duration: 0.6, stagger: 0.035, ease: "power3.out", scrollTrigger: { trigger: "#bars", start: "top 85%", once: true } });
  const bal = $("#balance"), to = +bal.dataset.to, money = { v: 0 };
  onEnter(bal, () => gsap.to(money, { v: to, duration: 1.1, ease: "power3.out",
    onUpdate: () => (bal.textContent = money.v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })) }), "top 90%");

  // Content: the idea cards deal out, then the notch says they're ready.
  gsap.from("#content-mock .idea", { y: 50, autoAlpha: 0, scale: 0.94, duration: 0.8, delay: 0.2, stagger: 0.1, ease: "back.out(1.4)", clearProps: "transform",
    scrollTrigger: { trigger: "#content-mock .ideas", start: "top 85%", once: true } });
  gsap.from("#content-mock .mini-notch", { scaleX: 0.5, autoAlpha: 0, duration: 0.6, delay: 0.9, ease: "back.out(1.6)", transformOrigin: "50% 0%",
    scrollTrigger: { trigger: "#content-mock .ideas", start: "top 85%", once: true } });

  // Privacy: the links draw between the boxes.
  gsap.from("#diagram .link", { scaleX: 0, scaleY: 0, duration: 0.6, stagger: 0.25, delay: 0.4, ease: "power2.out", scrollTrigger: { trigger: "#diagram", start: "top 75%", once: true } });

  document.fonts?.ready.then(() => ScrollTrigger.refresh());
}
