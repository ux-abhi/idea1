import { Easing, interpolate, useCurrentFrame } from "remotion";
import { Scene, Sfx, Sub, Words } from "../kinetic";
import { C, fontFamily, SPRING, useIn, useUnit, useVertical } from "../theme";

const ACCOUNTS = [
  { name: "Checking", amount: 1920 },
  { name: "Savings", amount: 460 },
  { name: "Cash", amount: 100.5 },
];
const DAYS = [32, 18, 45, 12, 60, 28, 22, 38, 15, 52, 26, 30, 19, 41]; // spent per day, last 14 days
const CATEGORIES = [
  { name: "Home", share: 0.42, color: C.brown },
  { name: "Food", share: 0.27, color: C.pink },
  { name: "Transport", share: 0.17, color: C.cyan },
  { name: "Other", share: 0.14, color: C.gray },
];

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

// 43.8–48s: the money dashboard: accounts, daily spending against the budget, and where it went.
export const Money = () => {
  const u = useUnit();
  const vertical = useVertical();
  return (
    <Scene>
      <Words text="Tracks your money." size={110} />
      <Sub text="Every expense, sorted for you." delay={16} />
      <div
        style={{
          display: "flex",
          flexDirection: vertical ? "column" : "row",
          gap: 22 * u,
          marginTop: 50 * u,
        }}
      >
        <Card title="Balance" delay={30}>
          <Balance />
        </Card>
        <Card title="Last 14 days" delay={36}>
          <Bars />
        </Card>
        <Card title="Where it went" delay={42}>
          <Ring />
        </Card>
      </div>
      <Sfx name="swoosh" at={0} volume={0.5} />
      <Sfx name="pop" at={30} volume={0.45} />
      <Sfx name="pop" at={36} volume={0.45} />
      <Sfx name="pop" at={42} volume={0.45} />
      <Sfx name="roll" at={36} volume={0.4} />
      <Sfx name="rise" at={46} volume={0.35} />
      <Sfx name="rise" at={56} volume={0.3} />
    </Scene>
  );
};

const Card: React.FC<{
  title: string;
  delay: number;
  children: React.ReactNode;
}> = ({ title, delay, children }) => {
  const u = useUnit();
  const p = useIn(delay, SPRING.cardIn);
  return (
    <div
      style={{
        width: 480 * u,
        height: 330 * u,
        borderRadius: 28 * u,
        background: `linear-gradient(${C.tileEdge}, ${C.tile})`,
        padding: 28 * u,
        fontFamily,
        color: C.text,
        opacity: Math.min(1, p * 1.5),
        translate: `0 ${(1 - p) * 40 * u}px`,
        filter: p < 1 ? `blur(${(1 - Math.min(1, p)) * 6}px)` : undefined,
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div style={{ fontSize: 24 * u, color: C.gray, fontWeight: 500 }}>
        {title}
      </div>
      {children}
    </div>
  );
};

const Balance = () => {
  const u = useUnit();
  const frame = useCurrentFrame();
  const t = interpolate(frame, [36, 100], [0, 1], {
    ...clamp,
    easing: Easing.out(Easing.cubic),
  });
  const total = ACCOUNTS.reduce((sum, a) => sum + a.amount, 0);
  return (
    <>
      <div
        style={{
          fontSize: 64 * u,
          fontWeight: 600,
          letterSpacing: "-0.03em",
          fontVariantNumeric: "tabular-nums",
          marginTop: 6 * u,
        }}
      >
        €
        {(total * t).toLocaleString("de-DE", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        })}
      </div>
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 14 * u,
          marginTop: "auto",
        }}
      >
        {ACCOUNTS.map((a, i) => (
          <div key={a.name}>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                fontSize: 22 * u,
                color: C.gray,
                marginBottom: 6 * u,
              }}
            >
              <span>{a.name}</span>
              <span>
                €
                {a.amount.toLocaleString("de-DE", { minimumFractionDigits: 2 })}
              </span>
            </div>
            <div
              style={{ height: 10 * u, borderRadius: 99, background: C.line }}
            >
              <div
                style={{
                  height: "100%",
                  borderRadius: 99,
                  background: [C.blue, C.green, C.mint][i],
                  width: `${(a.amount / total) * 100 * interpolate(frame, [50 + i * 6, 90 + i * 6], [0, 1], clamp)}%`,
                }}
              />
            </div>
          </div>
        ))}
      </div>
    </>
  );
};

const Bars = () => {
  const u = useUnit();
  const frame = useCurrentFrame();
  const max = 60;
  const budget = 40; // daily budget line
  const height = 200 * u;
  return (
    <>
      <div style={{ fontSize: 22 * u, color: C.gray, marginTop: 6 * u }}>
        <span style={{ color: C.text, fontWeight: 600, fontSize: 40 * u }}>
          €438
        </span>{" "}
        of €1,200
      </div>
      <div
        style={{
          position: "relative",
          display: "flex",
          alignItems: "flex-end",
          gap: 8 * u,
          height,
          marginTop: "auto",
        }}
      >
        {DAYS.map((d, i) => (
          <div
            key={i}
            style={{
              flex: 1,
              borderRadius: 6 * u,
              background: d > budget ? C.orange : C.blue,
              height:
                (d / max) *
                height *
                interpolate(frame, [46 + i * 2, 70 + i * 2], [0, 1], {
                  ...clamp,
                  easing: Easing.out(Easing.cubic),
                }),
            }}
          />
        ))}
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: (budget / max) * height,
            borderTop: `${2 * u}px dashed ${C.gray}`,
            opacity: interpolate(frame, [80, 95], [0, 0.8], clamp),
          }}
        />
      </div>
    </>
  );
};

const Ring = () => {
  const u = useUnit();
  const frame = useCurrentFrame();
  const t = interpolate(frame, [50, 110], [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });
  const r = 70;
  const circ = 2 * Math.PI * r;
  let start = 0;
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 28 * u,
        marginTop: "auto",
        marginBottom: "auto",
      }}
    >
      <svg width={200 * u} height={200 * u} viewBox="-100 -100 200 200">
        <circle r={r} fill="none" stroke={C.line} strokeWidth={26} />
        {CATEGORIES.map((c) => {
          const len = c.share * circ * t;
          const el = (
            <circle
              key={c.name}
              r={r}
              fill="none"
              stroke={c.color}
              strokeWidth={26}
              strokeDasharray={`${Math.max(0, len - 3)} ${circ}`}
              strokeDashoffset={-start * t}
              transform="rotate(-90)"
            />
          );
          start += c.share * circ;
          return el;
        })}
      </svg>
      <div style={{ display: "flex", flexDirection: "column", gap: 10 * u }}>
        {CATEGORIES.map((c) => (
          <div
            key={c.name}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 10 * u,
              fontSize: 22 * u,
            }}
          >
            <span
              style={{
                width: 14 * u,
                height: 14 * u,
                borderRadius: 99,
                background: c.color,
              }}
            />
            <span>{c.name}</span>
            <span style={{ color: C.gray }}>{Math.round(c.share * 100)}%</span>
          </div>
        ))}
      </div>
    </div>
  );
};
