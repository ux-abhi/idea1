import { interpolate, useCurrentFrame } from "remotion";
import {
  Icon,
  Keys,
  Scene,
  Screen,
  Sfx,
  Sub,
  TitleOut,
  Typed,
  Words,
} from "../kinetic";
import { C, fontFamily, SPRING, useIn, useUnit } from "../theme";

const HITS = [
  { icon: "note", title: "Thesis outline", kind: "Note" },
  { icon: "check", title: "Send thesis draft to Prof. Weber", kind: "Task" },
  { icon: "bell", title: "Thesis meeting, Friday 10:00", kind: "Reminder" },
  { icon: "space", title: "Thesis", kind: "Space" },
] as const;

// 26.4–31.2s: ⌘K finds notes, tasks, reminders, posts and spaces.
export const Search = () => {
  const u = useUnit();
  const frame = useCurrentFrame();
  const sheet = useIn(110, SPRING.cardIn);
  const selected = frame < 200 ? 0 : frame < 222 ? 1 : 2;
  return (
    <Scene>
      <TitleOut at={70}>
        <Words text="Find anything." />
        <Sub text="Notes, tasks, reminders, posts and spaces." />
      </TitleOut>
      {frame >= 80 && (
        <>
          <Screen delay={80} />
          <Keys
            keys={["⌘", "K"]}
            delay={86}
            press={106}
            style={{
              position: "absolute",
              bottom: 150 * u,
              opacity: interpolate(frame, [86, 98, 116, 130], [0, 1, 1, 0], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
              }),
            }}
          />
          <div
            style={{
              width: 900 * u,
              borderRadius: 28 * u,
              background: "rgba(28,28,30,0.92)",
              border: `${1.5 * u}px solid ${C.line}`,
              boxShadow: `0 ${40 * u}px ${100 * u}px rgba(0,0,0,0.6)`,
              fontFamily,
              color: C.text,
              opacity: sheet,
              scale: String(0.96 + 0.04 * sheet),
              transformOrigin: "top center", // grows from where ⌘K summons it
              filter:
                sheet < 1
                  ? `blur(${(1 - Math.min(1, sheet)) * 8}px)`
                  : undefined,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 16 * u,
                padding: `${24 * u}px ${28 * u}px`,
                fontSize: 36 * u,
                borderBottom: `${1.5 * u}px solid ${C.line}`,
              }}
            >
              <Icon name="search" size={34 * u} color={C.gray} />
              <Typed text="thesis" from={124} every={5} caret={frame < 180} />
            </div>
            <div style={{ padding: 12 * u }}>
              {HITS.map((h, i) => (
                <Hit key={h.title} {...h} i={i} on={i === selected} />
              ))}
            </div>
          </div>
          <Sfx name="swoosh" at={0} volume={0.5} />
          <Sfx name="tap" at={106} volume={0.7} />
          <Sfx name="open" at={108} volume={0.5} />
          {[0, 1, 2, 3].map((i) => (
            <Sfx key={i} name="pop" at={160 + i * 5} volume={0.35} />
          ))}
          <Sfx name="tick" at={200} volume={0.35} />
          <Sfx name="tick" at={222} volume={0.35} />
          <Sfx name="tap" at={245} volume={0.5} />
        </>
      )}
    </Scene>
  );
};

const Hit: React.FC<{
  icon: "note" | "check" | "bell" | "space";
  title: string;
  kind: string;
  i: number;
  on: boolean;
}> = ({ icon, title, kind, i, on }) => {
  const u = useUnit();
  const p = useIn(160 + i * 5, SPRING.content);
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 18 * u,
        padding: `${16 * u}px ${18 * u}px`,
        borderRadius: 16 * u,
        background: on ? C.blue : "transparent",
        opacity: p,
        translate: `0 ${(1 - p) * 16 * u}px`,
      }}
    >
      <Icon name={icon} size={34 * u} color={on ? C.text : C.blue} />
      <div style={{ flex: 1, fontSize: 30 * u, fontWeight: 500 }}>{title}</div>
      <div style={{ fontSize: 24 * u, color: on ? C.text : C.gray }}>
        {kind}
      </div>
    </div>
  );
};
