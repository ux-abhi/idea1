// © Pexilim
// The confirm and leave pages: only a click on the button calls the waitlist (mail scanners open links, they don't click).
(() => {
  const button = document.getElementById("waitlist-link");
  const status = document.getElementById("waitlist-link-status");
  if (!button || !status) return;
  const token = new URLSearchParams(location.search).get(button.dataset.param);
  if (!token) { status.textContent = button.dataset.missing; button.hidden = true; return; }
  button.addEventListener("click", async () => {
    const url = window.BLINK_WAITLIST_ACTIONS_URL;
    if (!url) { status.textContent = "Please email hello@pexilim.com."; return; }
    button.disabled = true;
    status.textContent = "One moment…";
    try {
      const res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: button.dataset.action, token }) });
      const body = await res.json().catch(() => ({}));
      if (res.ok && body.ok) { status.textContent = button.dataset.done; button.hidden = true; return; }
      status.textContent = body.error || "That didn't work. Try again in a minute.";
    } catch {
      status.textContent = "Can't reach Blink's server. Check your connection and try again.";
    }
    button.disabled = false;
  });
})();
