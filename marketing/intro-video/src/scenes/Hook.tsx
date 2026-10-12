import { interpolate, useCurrentFrame } from "remotion";
import { Scene, Sfx, Words } from "../kinetic";
import { BEAT, C } from "../theme";

// 2.4–7.2s: line one in the music's quiet bar; "brain." lands as the groove comes in (frame 144).
export const Hook = () => {
  const frame = useCurrentFrame();
  const firstAway = interpolate(frame, [100, 112], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <Scene>
      <div
        style={{
          position: "absolute",
          opacity: firstAway,
          translate: `0 ${(1 - firstAway) * -40}px`,
        }}
      >
        <Words text="Your Mac has a notch." />
      </div>
      <Words
        text="Now it has a brain."
        delay={112}
        stagger={5}
        accent={{ "brain.": C.blue }}
      />
      <Sfx name="swoosh" at={0} volume={0.5} />
      <Sfx name="swoosh" at={108} volume={0.5} />
      <Sfx name="sparkle" at={4 * BEAT} volume={0.35} />
    </Scene>
  );
};
