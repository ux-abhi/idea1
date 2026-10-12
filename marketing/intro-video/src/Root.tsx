import { Composition, Folder } from "remotion";
import { BlinkCut15, BlinkCut30 } from "./BlinkCuts";
import { BlinkIntro } from "./BlinkIntro";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="BlinkIntro"
        component={BlinkIntro}
        durationInFrames={3600}
        fps={60}
        width={1920}
        height={1080}
      />
      <Composition
        id="BlinkIntroVertical"
        component={BlinkIntro}
        durationInFrames={3600}
        fps={60}
        width={1080}
        height={1920}
      />
      <Folder name="Cuts">
        <Composition
          id="BlinkCut30"
          component={BlinkCut30}
          durationInFrames={1800}
          fps={60}
          width={1920}
          height={1080}
        />
        <Composition
          id="BlinkCut30Vertical"
          component={BlinkCut30}
          durationInFrames={1800}
          fps={60}
          width={1080}
          height={1920}
        />
        <Composition
          id="BlinkCut15"
          component={BlinkCut15}
          durationInFrames={900}
          fps={60}
          width={1920}
          height={1080}
        />
        <Composition
          id="BlinkCut15Vertical"
          component={BlinkCut15}
          durationInFrames={900}
          fps={60}
          width={1080}
          height={1920}
        />
      </Folder>
    </>
  );
};
