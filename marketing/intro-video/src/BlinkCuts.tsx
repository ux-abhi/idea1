import { TransitionSeries } from "@remotion/transitions";
import { useVideoConfig } from "remotion";
import { Music, Skip } from "./Music";
import { Clipboard } from "./scenes/Clipboard";
import { End } from "./scenes/End";
import { Habits } from "./scenes/Habits";
import { Hook } from "./scenes/Hook";
import { Mail } from "./scenes/Mail";
import { Meet } from "./scenes/Meet";
import { Money } from "./scenes/Money";
import { NotchWake } from "./scenes/NotchWake";

// Short cuts of the film, from the same scenes. Each is a whole number of beats (36 frames); end cards start on a bar
// line (multiple of 144) two bars after the music's jump, where the track's final hit lands.

// The clipboard demo without its title: from just before the panel appears.
const CLIP_SKIP = 258;

/** 30 s = 50 beats: notch, hook, meet, mail, clipboard, money, habits, end card (from 26.4 s). */
export const BlinkCut30 = () => {
  const { fps } = useVideoConfig();
  return (
    <>
      <Music jumpAt={1296} />
      <TransitionSeries>
        <TransitionSeries.Sequence
          name="Notch wakes"
          durationInFrames={144}
          premountFor={fps}
        >
          <NotchWake />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Hook"
          durationInFrames={288}
          premountFor={fps}
        >
          <Hook />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Meet Blink"
          durationInFrames={144}
          premountFor={fps}
        >
          <Meet />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Mail"
          durationInFrames={288}
          premountFor={fps}
        >
          <Mail />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Clipboard"
          durationInFrames={360}
          premountFor={fps}
        >
          <Skip skip={CLIP_SKIP} length={360}>
            <Clipboard noTitle />
          </Skip>
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Money"
          durationInFrames={216}
          premountFor={fps}
        >
          <Money />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Habits"
          durationInFrames={144}
          premountFor={fps}
        >
          <Habits />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="End card"
          durationInFrames={216}
          premountFor={fps}
        >
          <End />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </>
  );
};

/** 15 s = 25 beats: notch, meet, clipboard (search and drag), money, end card (from 12 s). */
export const BlinkCut15 = () => {
  const { fps } = useVideoConfig();
  return (
    <>
      <Music jumpAt={432} />
      <TransitionSeries>
        <TransitionSeries.Sequence
          name="Notch wakes"
          durationInFrames={144}
          premountFor={fps}
        >
          <NotchWake />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Meet Blink"
          durationInFrames={144}
          premountFor={fps}
        >
          <Meet />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Clipboard"
          durationInFrames={288}
          premountFor={fps}
        >
          <Skip skip={CLIP_SKIP} length={288}>
            <Clipboard noTitle />
          </Skip>
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Money"
          durationInFrames={144}
          premountFor={fps}
        >
          <Money />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="End card"
          durationInFrames={180}
          premountFor={fps}
        >
          <End />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </>
  );
};
