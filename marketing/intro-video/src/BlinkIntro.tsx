import { TransitionSeries } from "@remotion/transitions";
import { useVideoConfig } from "remotion";
import { Music } from "./Music";
import { Ask } from "./scenes/Ask";
import { Burst } from "./scenes/Burst";
import { Clipboard } from "./scenes/Clipboard";
import { Day } from "./scenes/Day";
import { End } from "./scenes/End";
import { Habits } from "./scenes/Habits";
import { Hook } from "./scenes/Hook";
import { Ideas } from "./scenes/Ideas";
import { Mail } from "./scenes/Mail";
import { Meet } from "./scenes/Meet";
import { Money } from "./scenes/Money";
import { NotchWake } from "./scenes/NotchWake";
import { Private } from "./scenes/Private";
import { Search } from "./scenes/Search";
import { Send } from "./scenes/Send";
import { Tagline } from "./scenes/Tagline";

// 60 s at 60 fps = 3600 frames = 100 beats of the 100 BPM track. Every scene is a whole number of beats (36 frames).
// The track breaks down at 31.5 s and drops at 36.3 s: here the clipboard title, then ⌃⌥V. Music jumps at 52.8 s so its
// final hit lands on the end card (57.6 s); see Music.tsx.
export const BlinkIntro = () => {
  const { fps } = useVideoConfig();
  return (
    <>
      <Music jumpAt={3168} />
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
          name="Tagline"
          durationInFrames={144}
          premountFor={fps}
        >
          <Tagline />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Ask"
          durationInFrames={288}
          premountFor={fps}
        >
          <Ask />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Mail"
          durationInFrames={288}
          premountFor={fps}
        >
          <Mail />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Send"
          durationInFrames={288}
          premountFor={fps}
        >
          <Send />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Search"
          durationInFrames={288}
          premountFor={fps}
        >
          <Search />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Clipboard"
          durationInFrames={612}
          premountFor={fps}
        >
          <Clipboard />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Day"
          durationInFrames={144}
          premountFor={fps}
        >
          <Day />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Money"
          durationInFrames={252}
          premountFor={fps}
        >
          <Money />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Habits"
          durationInFrames={180}
          premountFor={fps}
        >
          <Habits />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Ideas"
          durationInFrames={144}
          premountFor={fps}
        >
          <Ideas />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Much more"
          durationInFrames={144}
          premountFor={fps}
        >
          <Burst />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="Private"
          durationInFrames={108}
          premountFor={fps}
        >
          <Private />
        </TransitionSeries.Sequence>
        <TransitionSeries.Sequence
          name="End card"
          durationInFrames={144}
          premountFor={fps}
        >
          <End />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </>
  );
};
