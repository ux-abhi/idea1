# Blink website

Static site for https://blink.pexilim.com. Plain HTML, CSS and JS: no build step, no framework. Not deployed yet.

## Preview

```sh
cd marketing/site
python3 -m http.server 8765
```

Open http://localhost:8765. Use a server rather than opening the file: the install page checks the DMG with a request.

## What's where

| Path | What |
|---|---|
| `index.html` | Home: hero notch, film, moods, Ask, Mail, Clipboard + ⌘K, Day + habits, Money, Content, Ask-First, privacy diagram, setup, FAQ |
| `install.html` | Download, first-open steps (not notarized yet), setup, SHA-256 check |
| `privacy.html`, `terms.html` | Plain-English policy and terms, "Last updated 13 October 2026" |
| `css/site.css` | All styles. Colours are the dark values from `design/tokens.json` (no purple or indigo) |
| `js/main.js` | Eyes (follow the pointer, blink), hero notch scroll, demos, GSAP reveals |
| `js/install.js` | Shows the DMG size once `downloads/Blink.dmg` exists |
| `assets/` | Eyes exported from the app (320×160), favicon, web film (`blink-film.mp4`, H.264 1280 wide, CRF 26) and its poster |
| `downloads/` | Put `Blink.dmg` here (not in git yet) |

## Before going live

- Add `downloads/Blink.dmg`, then replace the line in `install.html` with id `dmg-sha` with the real `shasum -a 256` output.
- GSAP 3.13.0 and ScrollTrigger load from cdnjs with SRI hashes; Inter loads from Google Fonts. Both are named on the privacy page.
- The film's music is the licensed Pixabay track; fine on our own site.

## Motion and accessibility

- Without GSAP, or with Reduce Motion on, every section shows its final state: the notch is open with the answer, the inbox is sorted, charts are drawn. The eyes don't follow or blink.
- Reveals use opacity (not visibility), so keyboard users can Tab into demos before they've scrolled to them.
- Demos that are real controls: mood buttons, model picker, mail rows (teach a sender), clipboard search and drag, habit tick, Touch ID approve.

## Re-encode the film

From `marketing/intro-video`:

```sh
npx remotion ffmpeg -y -i out/blink-intro-60s-16x9.mp4 -vf scale=1280:-2 -c:v libx264 -crf 26 -preset slow -pix_fmt yuv420p -c:a aac -b:a 96k -movflags +faststart ../site/assets/blink-film.mp4
npx remotion ffmpeg -y -ss 8.6 -i out/blink-intro-60s-16x9.mp4 -frames:v 1 -vf scale=1280:-2 -q:v 4 ../site/assets/blink-film-poster.jpg
```
