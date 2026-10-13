# Blink website

Static site for https://www.blinkk.app. Plain HTML, CSS and JS: no build step, no framework. Not deployed yet.

## Preview

```sh
cd marketing/site
python3 -m http.server 8765
```

Open http://localhost:8765. Use a server rather than opening the file: the install page checks the DMG with a request.

## What's where

| Path | What |
|---|---|
| `index.html` | Home, alternating light and dark bands: hero notch, film, a five-tile bento of everyday demos (Ask, Mail, Clipboard, ⌘K, Touch ID), a tabbed showcase for one feature at a time (Day, Money, Habits, Content, Moods), privacy diagram, setup, FAQ, waitlist form |
| `install.html` | Waitlist note (the download button appears by itself once `downloads/Blink.dmg` exists), first-open steps, setup, SHA-256 check |
| `privacy.html`, `terms.html` | Plain-English policy (with the Waitlist section) and terms, "Last updated 13 October 2026" |
| `css/site.css` | All styles. Bands set `--bg/--fg/--muted/--link` via `.light`, `.mist`, `.dark`; mood colours from `design/tokens.json` are fills only (no purple or indigo) |
| `js/main.js` | Eyes (follow the pointer, blink, peek over the Mail tile), hero notch scroll, demos, showcase tabs (arrow keys, Home, End), GSAP reveals |
| `js/config.js`, `js/waitlist.js`, `api/waitlist.mjs` | Waitlist form, and the Vercel function it posts to (stores on Supabase, emails through Resend). Tests: `node --test marketing/site/tests/*.js marketing/site/tests/*.mjs` |
| `js/install.js` | Shows the download button and size once `downloads/Blink.dmg` exists |
| `assets/` | Eyes exported from the app (320×160), favicon, web film (`blink-film.mp4`, H.264 1280 wide, CRF 26) and its poster |
| `downloads/` | Put `Blink.dmg` here (not in git yet) |

## Before going live

- Add `downloads/Blink.dmg`, then replace the line in `install.html` with id `dmg-sha` with the real `shasum -a 256` output.
- GSAP 3.13.0, ScrollTrigger and Inter are self-hosted. The waitlist form posts to this site's own `/api/waitlist`; only the confirm and leave pages call Supabase directly (`connect-src` in the CSP).
- The film's music is the licensed Pixabay track; fine on our own site.

## Motion and accessibility

- Without GSAP, or with Reduce Motion on, every section shows its final state: the notch is open with the answer, the inbox is sorted, charts are drawn. The eyes don't follow or blink.
- Reveals use opacity (not visibility), so keyboard users can Tab into demos before they've scrolled to them.
- Demos that are real controls: mood buttons, model picker, mail rows (teach a sender), clipboard search and drag, habit tick, Touch ID approve.
- The showcase never advances by itself: visitors read and play with each demo at their own pace. Without JS its panels show one under the other.

## Re-encode the film

From `marketing/intro-video`:

```sh
npx remotion ffmpeg -y -i out/blink-intro-60s-16x9.mp4 -vf scale=1280:-2 -c:v libx264 -crf 26 -preset slow -pix_fmt yuv420p -c:a aac -b:a 96k -movflags +faststart ../site/assets/blink-film.mp4
npx remotion ffmpeg -y -ss 8.6 -i out/blink-intro-60s-16x9.mp4 -frames:v 1 -vf scale=1280:-2 -q:v 4 ../site/assets/blink-film-poster.jpg
```
