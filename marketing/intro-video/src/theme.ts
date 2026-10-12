// Colours come from design/tokens.json (apple.* dark values, blink.*). Motion springs from tokens → motion.spring.
import {loadFont} from '@remotion/google-fonts/Inter';
import {spring, useCurrentFrame, useVideoConfig} from 'remotion';

export const {fontFamily} = loadFont('normal', {weights: ['400', '600', '800'], subsets: ['latin']});

export const C = {
	notch: '#000000',
	bg: '#000000',
	text: '#FFFFFF',
	dim: '#8E8E93', // systemGray
	tile: '#1C1C1E', // systemGray6 dark
	tileEdge: '#2C2C2E', // systemGray5 dark
	red: '#FF453A',
	mint: '#63E6E2',
	indigo: '#5E5CE6',
	green: '#30D158',
	orange: '#FF9F0A',
	yellow: '#FFD60A',
	pink: '#FF375F',
	cyan: '#64D2FF',
	brown: '#AC8E68',
	purple: '#BF5AF2',
};

// 120 BPM at 60 fps: one beat is 30 frames. Key hits land on beats.
export const BEAT = 30;

// Token springs are (response, dampingRatio); Remotion wants stiffness and damping for mass 1.
const tokenSpring = (response: number, ratio: number) => ({
	mass: 1,
	stiffness: (2 * Math.PI / response) ** 2,
	damping: (4 * Math.PI * ratio) / response,
});
export const SPRING = {
	content: tokenSpring(0.3, 0.9),
	open: tokenSpring(0.45, 0.78),
	cardIn: tokenSpring(0.4, 0.82),
	close: tokenSpring(0.38, 0.9),
	// Video-only: the rapid-fire words must be sharp within a few frames.
	snap: tokenSpring(0.16, 0.95),
};

/** 0→1 spring that starts `delay` frames into the current sequence. */
export const useIn = (delay = 0, config = SPRING.content) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	return spring({frame: frame - delay, fps, config});
};

/** Size unit: 1 at 1920×1080; scales with the narrow side so the 9:16 cut keeps type big. */
export const useUnit = () => {
	const {width, height} = useVideoConfig();
	return width >= height ? height / 1080 : width / 1200;
};

export const useVertical = () => {
	const {width, height} = useVideoConfig();
	return height > width;
};
