# Blink website

The site for https://www.blinkk.app: Next.js (App Router, plain JavaScript). The pages are server-rendered on each
request so every page gets a fresh nonce for its Content Security Policy (`proxy.js`). Each page's own behaviour (the
eyes, demos, forms) is plain JS in `public/js`, loaded after React has taken over the page (`components/PageScripts.jsx`).

## Preview

```sh
cd marketing/site
npm install
npm run dev        # http://localhost:3000
npm test           # the waitlist, survey and follow-up handlers
```

## What's where

| Path | What |
|---|---|
| `app/page.jsx` | Home, alternating light and dark bands: hero notch, film, a five-tile bento of everyday demos (Ask, Mail, Clipboard, ⌘K, Touch ID), a tabbed showcase (Day, Money, Habits, Content, Moods), privacy diagram, setup, FAQ, waitlist form |
| `app/install`, `app/privacy`, `app/terms` | Install guide, plain-English privacy policy (with the Waitlist section) and terms |
| `app/confirm`, `app/leave`, `app/survey` | Waitlist confirm and leave pages, and the five-question survey |
| `app/layout.jsx` | The shared `<html>`: styles, the welcome-screen gate, Vercel Analytics and Speed Insights |
| `components/` | `SiteHeader`, `SiteFooter`, `PageScripts` |
| `app/api/*/route.js` → `lib/*.mjs` | The waitlist, survey and daily follow-up endpoints (the handlers live in `lib/` so the tests call them directly) |
| `next.config.mjs` | Redirects the old `*.html` addresses (in sent emails and the installer) to the new pages |
| `proxy.js` | The Content Security Policy with a per-request nonce |
| `public/css/site.css` | All styles. Bands set `--bg/--fg/--muted/--link` via `.light`, `.mist`, `.dark`; mood colours from `design/tokens.json` are fills only (no purple or indigo) |
| `public/js/main.js` | Eyes, hero lid and notch scroll, demos, showcase tabs, GSAP reveals |
| `public/assets/` | Eyes exported from the app, favicon, the web film and its poster, fonts |
| `public/downloads/` | Put `Blink.dmg` here (not in git) |

## Before going live

- Add `public/downloads/Blink.dmg`, then replace the line in `app/install/page.jsx` with id `dmg-sha` with the real `shasum -a 256` output.
- GSAP 3.13.0, ScrollTrigger and Inter are self-hosted. The waitlist form posts to this site's own `/api/waitlist`; only the confirm and leave pages call Supabase directly (`connect-src` in the CSP).
- The film's music is the licensed Pixabay track; fine on our own site.

## Motion and accessibility

- Without GSAP, or with Reduce Motion on, every section shows its final state: the notch is open with the answer, the inbox is sorted, charts are drawn. The eyes don't follow or blink.
- Reveals use opacity (not visibility), so keyboard users can Tab into demos before they've scrolled to them.
- Scroll motion (all set up from JS, so the page is complete without it): the hero lid opens on its hinge, section titles arrive word by word, the film grows to size, the setup rail draws and its steps rise, the footer's "Blink" rises into view, and the notches' eyes glance the way you scroll. The footer's eyes blink in CSS, so they also blink on pages that run no script.
- Demos that are real controls: mood buttons, model picker, mail rows (teach a sender), clipboard search and drag, habit tick, Touch ID approve.
- The showcase never advances by itself: visitors read and play with each demo at their own pace. Without JS its panels show one under the other.

## Re-encode the film

From `marketing/intro-video`:

```sh
npx remotion ffmpeg -y -i out/blink-intro-60s-16x9.mp4 -vf scale=1280:-2 -c:v libx264 -crf 26 -preset slow -pix_fmt yuv420p -c:a aac -b:a 96k -movflags +faststart ../site/assets/blink-film.mp4
npx remotion ffmpeg -y -ss 8.6 -i out/blink-intro-60s-16x9.mp4 -frames:v 1 -vf scale=1280:-2 -q:v 4 ../site/assets/blink-film-poster.jpg
```
