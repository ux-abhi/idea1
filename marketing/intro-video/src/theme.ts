// Colours from design/tokens.json (apple.* dark values, blink.mood.*). Apple-style film: black, white and grey with
// Blink's mood colours as accents. No purple or indigo (owner's call); thinking uses blue.
// Motion springs from tokens → motion.spring.
import { loadFont } from "@remotion/google-fonts/Inter";
import { spring, useCurrentFrame, useVideoConfig } from "remotion";

export const { fontFamily } = loadFont("normal", {
  weights: ["400", "500", "600", "700"],
  subsets: ["latin"],
});

export const C = {
  bg: "#000000",
  notch: "#000000", // blink.notch.hardware
  text: "#FFFFFF",
  gray: "#8E8E93", // systemGray
  tile: "#1C1C1E", // systemGray6 dark
  tileEdge: "#2C2C2E", // systemGray5 dark
  line: "#3A3A3C", // systemGray4 dark
  blue: "#0A84FF", // systemBlue: accent, and Blink's thinking colour in this film
  red: "#FF453A", // mood.important
  mint: "#63E6E2", // mood.headsUp
  green: "#30D158", // mood.done
  orange: "#FF9F0A", // mood.attention
  yellow: "#FFD60A", // mood.celebrate
  pink: "#FF375F", // money.food
  cyan: "#64D2FF", // money.transport
  brown: "#AC8E68", // money.home
};

// The music runs at 100 BPM: at 60 fps one beat is 36 frames, a bar 144. Scene lengths and key hits land on beats.
export const BEAT = 36;

// Token springs are (response, dampingRatio); Remotion wants stiffness and damping for mass 1.
const tokenSpring = (response: number, ratio: number) => ({
  mass: 1,
  stiffness: ((2 * Math.PI) / response) ** 2,
  damping: (4 * Math.PI * ratio) / response,
});
export const SPRING = {
  smooth: tokenSpring(0.5, 1.0), // motion.spring.focus: no overshoot, the Apple-film default
  content: tokenSpring(0.3, 0.9),
  open: tokenSpring(0.45, 0.78),
  cardIn: tokenSpring(0.4, 0.82),
  // Video-only: the rapid-fire words must be sharp within a few frames.
  snap: tokenSpring(0.16, 0.95),
};
export type Spring = typeof SPRING.smooth;

/** 0→1 spring that starts `delay` frames into the current sequence. */
export const useIn = (delay = 0, config: Spring = SPRING.smooth) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config });
};

/** Size unit: 1 at 1920×1080; scales with the narrow side so the 9:16 cut keeps type big. */
export const useUnit = () => {
  const { width, height } = useVideoConfig();
  return width >= height ? height / 1080 : width / 1200;
};

export const useVertical = () => {
  const { width, height } = useVideoConfig();
  return height > width;
};
