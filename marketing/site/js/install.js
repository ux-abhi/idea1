// Once downloads/Blink.dmg is on the server, show the download button and its size and hide the waitlist note.
const link = document.querySelector("#dmg-link");
const size = document.querySelector("#dmg-size");
fetch(link.getAttribute("href"), { method: "HEAD" })
  .then((r) => {
    const bytes = Number(r.headers.get("content-length"));
    if (!r.ok || !bytes || r.headers.get("content-type")?.includes("html")) throw new Error("missing"); // some hosts answer missing files with a page
    size.textContent = `Blink.dmg, ${(bytes / 1e6).toFixed(1)} MB`;
    size.hidden = false;
    document.querySelector("#download").hidden = false;
    document.querySelector("#waitlist-note").hidden = true;
  })
  .catch(() => {}); // no file yet: the waitlist note stays
