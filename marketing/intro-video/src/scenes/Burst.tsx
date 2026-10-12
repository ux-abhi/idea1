import { Sequence, useCurrentFrame } from "remotion";
import { Scene, Sfx, Words } from "../kinetic";
import { C, SPRING, useUnit } from "../theme";

// 53.4–55.8s: everything else, one word per half-beat, then all of it at once.
const MORE = [
  { word: "Reminders", color: C.mint },
  { word: "Focus timer", color: C.text },
  { word: "Calendar", color: C.orange },
  { word: "Post insights", color: C.pink },
  { word: "Spaces", color: C.text },
  { word: "Quick commands", color: C.blue },
];
const EACH = 15;

export const Burst = () => {
  const u = useUnit();
  const frame = useCurrentFrame();
  const all = MORE.length * EACH;
  return (
    <Scene>
      {MORE.map(({ word, color }, i) => (
        <Sequence
          key={word}
          from={i * EACH}
          durationInFrames={EACH}
          layout="none"
        >
          <Words
            text={word}
            size={170}
            stagger={1}
            color={color}
            config={SPRING.snap}
          />
          <Sfx name="tick" at={0} volume={0.3} />
        </Sequence>
      ))}
      {frame >= all && (
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            justifyContent: "center",
            gap: `${8 * u}px ${34 * u}px`,
            width: 1400 * u,
          }}
        >
          {MORE.map(({ word, color }, i) => (
            <Words
              key={word}
              text={word}
              size={60}
              weight={500}
              color={color}
              delay={all + i}
              stagger={0}
              config={SPRING.content}
            />
          ))}
        </div>
      )}
    </Scene>
  );
};
