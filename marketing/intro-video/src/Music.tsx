import { Audio } from "@remotion/media";
import {
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

// public/music/product-launch.mp3 ("Product Launch" by lnplusmusic, Pixabay; git-ignored). 100 BPM, first beat at
// 0.302 s, so film bars (every 144 frames) line up with the track's bars. It ends on a big hit at 115.5 s.
// Every cut plays the track from the start until `jumpAt` (a bar line), then continues from bar 46 (110.7 s), so
// the final hit lands two bars later, which is where each cut puts its end card.
const MUSIC_START = 0.302;
const ENDING_FROM = 110.702;
const X = 6; // crossfade frames around the jump

export const Music: React.FC<{ jumpAt: number }> = ({ jumpAt }) => {
  const { fps, durationInFrames } = useVideoConfig();
  const frame = useCurrentFrame();
  const fade = (from: number, to: number, a: number, b: number) =>
    interpolate(frame, [from, to], [a, b], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
  return (
    <>
      <Audio
        name="Music"
        src={staticFile("music/product-launch.mp3")}
        trimBefore={Math.round(MUSIC_START * fps)}
        durationInFrames={jumpAt + X}
        volume={0.75 * fade(jumpAt - X, jumpAt + X, 1, 0)}
      />
      <Audio
        name="Music ending"
        src={staticFile("music/product-launch.mp3")}
        from={jumpAt - X}
        trimBefore={Math.round(ENDING_FROM * fps) - X}
        volume={
          0.75 *
          fade(jumpAt - X, jumpAt + X, 0, 1) *
          fade(durationInFrames - 60, durationInFrames, 1, 0)
        }
        premountFor={fps}
      />
    </>
  );
};

/** Starts a scene `skip` frames in, for the short cuts (e.g. the clipboard demo without its title). */
export const Skip: React.FC<{
  skip: number;
  length: number;
  children: React.ReactNode;
}> = ({ skip, length, children }) => (
  <Sequence from={-skip} durationInFrames={skip + length}>
    {children}
  </Sequence>
);
