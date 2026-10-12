import React from 'react';
import {AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, fontFamily, SPRING, useIn, useUnit} from './theme';

type Spring = typeof SPRING.content;

/** Words rise in one after another, each with a short blur, like type being set on the beat. */
export const Words: React.FC<{
	text: string;
	delay?: number;
	stagger?: number;
	size?: number;
	weight?: number;
	color?: string;
	accent?: Record<string, string>; // word → colour
	config?: Spring;
	style?: React.CSSProperties;
}> = ({text, delay = 0, stagger = 5, size = 150, weight = 800, color = C.text, accent = {}, config, style}) => {
	const u = useUnit();
	return (
		<div
			style={{
				display: 'flex',
				flexWrap: 'wrap',
				justifyContent: 'center',
				columnGap: size * u * 0.26,
				fontFamily,
				fontSize: size * u,
				fontWeight: weight,
				letterSpacing: '-0.045em',
				lineHeight: 1.04,
				color,
				textAlign: 'center',
				...style,
			}}
		>
			{text.split(' ').map((word, i) => (
				<Word key={i} delay={delay + i * stagger} color={accent[word]} config={config}>
					{word}
				</Word>
			))}
		</div>
	);
};

const Word: React.FC<{delay: number; color?: string; config?: Spring; children: string}> = ({delay, color, config, children}) => {
	const p = useIn(delay, config);
	return (
		<span
			style={{
				display: 'inline-block',
				opacity: Math.min(1, p * 1.4),
				translate: `0 ${(1 - p) * 0.45}em`,
				filter: `blur(${(1 - Math.min(1, p)) * 12}px)`,
				color,
				textShadow: color ? `0 0 0.25em ${color}8C` : undefined,
			}}
		>
			{children}
		</span>
	);
};

/** Blink's real eyes, exported from the app (BlinkEyes at notch size), with a blink at each frame in `blinks`. */
export const Eyes: React.FC<{
	mood: 'idle' | 'important' | 'thinking' | 'done' | 'headsup';
	width: number;
	blinks?: number[];
	style?: React.CSSProperties;
}> = ({mood, width, blinks = [], style}) => {
	const frame = useCurrentFrame();
	const lid = blinks.reduce(
		(open, at) =>
			Math.min(open, interpolate(frame, [at, at + 4, at + 9], [1, 0.08, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})),
		1,
	);
	return (
		<Img
			src={staticFile(`eyes-${mood}.png`)}
			style={{width, height: width / 2, scale: `1 ${lid}`, ...style}}
		/>
	);
};

/** Every scene leaves the same way: a quick settle back and fade, so cuts feel like one continuous piece. */
export const Scene: React.FC<{children: React.ReactNode; style?: React.CSSProperties}> = ({children, style}) => {
	const frame = useCurrentFrame();
	const {durationInFrames} = useVideoConfig();
	const out = interpolate(frame, [durationInFrames - 10, durationInFrames], [0, 1], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
		easing: Easing.in(Easing.cubic),
	});
	return (
		<AbsoluteFill
			style={{
				backgroundColor: C.bg,
				alignItems: 'center',
				justifyContent: 'center',
				flexDirection: 'column',
				opacity: 1 - out,
				scale: String(1 - out * 0.04),
				...style,
			}}
		>
			{children}
		</AbsoluteFill>
	);
};

/** A dark tile like the app's notch tiles. */
export const Tile: React.FC<{delay?: number; children: React.ReactNode; style?: React.CSSProperties}> = ({delay = 0, children, style}) => {
	const u = useUnit();
	const p = useIn(delay, SPRING.cardIn);
	return (
		<div
			style={{
				background: `linear-gradient(${C.tileEdge}, ${C.tile})`,
				borderRadius: 26 * u,
				padding: `${22 * u}px ${30 * u}px`,
				fontFamily,
				color: C.text,
				opacity: Math.min(1, p * 1.5),
				translate: `0 ${(1 - p) * 40 * u}px`,
				scale: String(0.96 + 0.04 * p),
				...style,
			}}
		>
			{children}
		</div>
	);
};
