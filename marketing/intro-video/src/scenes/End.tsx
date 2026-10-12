import { interpolate, useCurrentFrame } from "remotion";
import { Eyes, Scene, Sfx, Words } from "../kinetic";
import { C, fontFamily, useIn, useUnit } from "../theme";

// 57.6–60s: lands on the track's final hit. the wordmark; one last blink.
export const End = () => {
  const u = useUnit();
  const frame = useCurrentFrame();
  const p = useIn(0);
  const sub = interpolate(frame, [36, 56], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <Scene>
      <Eyes
        width={170 * u}
        blinks={[100]}
        style={{ opacity: p, marginBottom: 16 * u }}
      />
      <Words text="Blink" size={200} />
      <div
        style={{
          fontFamily,
          fontSize: 20 * u,
          letterSpacing: "0.08em",
          color: C.gray,
          opacity: sub,
          marginTop: 2 * u,
        }}
      >
        by Pexilim
      </div>
      <div
        style={{
          fontFamily,
          fontSize: 40 * u,
          color: C.gray,
          opacity: sub,
          marginTop: 26 * u,
        }}
      >
        for Mac · <span style={{ color: C.blue }}>Coming soon</span>
      </div>
      <Sfx name="sparkle" at={36} volume={0.35} />
      <Sfx name="tick" at={100} volume={0.3} />
    </Scene>
  );
};
