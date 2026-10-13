// Show the DMG's size once the file is on the server.
const link = document.querySelector("#dmg-link");
const size = document.querySelector("#dmg-size");
fetch(link.getAttribute("href"), { method: "HEAD" })
  .then((r) => {
    const bytes = Number(r.headers.get("content-length"));
    if (!r.ok || !bytes) throw new Error("missing");
    size.textContent = `Blink.dmg, ${(bytes / 1e6).toFixed(1)} MB`;
    size.hidden = false;
  })
  .catch(() => {}); // no file yet: the size line stays hidden
