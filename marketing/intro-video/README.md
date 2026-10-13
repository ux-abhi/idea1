# Blink launch film

Remotion project for the 60-second film and its 30- and 15-second cuts, each in 16:9 and 9:16. Never shipped with the app.

- `npm i`, then `npm run dev` to preview in Remotion Studio.
- Export: `npx remotion render <id> out/<name>.mp4` with `BlinkIntro`, `BlinkIntroVertical`, `BlinkCut30`, `BlinkCut30Vertical`, `BlinkCut15` or `BlinkCut15Vertical`. `out/` is git-ignored.
- Music: put the licensed track at `public/music/product-launch.mp3` ("Product Launch" by lnplusmusic, Pixabay licence; git-ignored, never redistributed). Scenes are cut to its 100 BPM grid; `src/Music.tsx` explains the jump to its ending.
- Sound effects: Kenney CC0 in `public/sfx/kenney/`; air and motion sounds made by `sound/make_sounds.py`.
- Eyes: `public/eyes-*.png` are exported from the app's `BlinkEyes` view.
- Licence: Remotion is free for companies of up to 3 people; a company licence is needed beyond that.
