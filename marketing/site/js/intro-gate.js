// Runs before the first paint: the welcome screen shows only when motion is allowed (main.js removes it if GSAP is missing).
if (!matchMedia("(prefers-reduced-motion: reduce)").matches) document.documentElement.classList.add("intro-on");
// If a script fails to load or throws, drop the welcome screen rather than leave the page black.
addEventListener("error", () => document.documentElement.classList.remove("intro-on"), true);
