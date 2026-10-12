import {Audio} from '@remotion/media';
import React from 'react';
import {AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, fontFamily, SPRING, type Spring, useIn, useUnit} from './theme';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** Words rise in one after another with a soft focus pull, the way Apple films set type. */
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
}> = ({text, delay = 0, stagger = 4, size = 140, weight = 600, color = C.text, accent = {}, config, style}) => {
	const u = useUnit();
	return (
		<div
			style={{
				display: 'flex',
				flexWrap: 'wrap',
				justifyContent: 'center',
				columnGap: size * u * 0.25,
				fontFamily,
				fontSize: size * u,
				fontWeight: weight,
				letterSpacing: '-0.035em',
				lineHeight: 1.06,
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
				opacity: Math.min(1, p * 1.3),
				translate: `0 ${(1 - p) * 0.3}em`,
				filter: `blur(${(1 - Math.min(1, p)) * 8}px)`,
				color,
			}}
		>
			{children}
		</span>
	);
};

/** A grey supporting line under a headline. */
export const Sub: React.FC<{text: string; delay?: number; size?: number; style?: React.CSSProperties}> = ({text, delay = 12, size = 52, style}) => (
	<Words text={text} delay={delay} stagger={2} size={size} weight={500} color={C.gray} style={{marginTop: 18, ...style}} />
);

/** Blink's real eyes, exported from the app (BlinkEyes at notch size), with a blink at each frame in `blinks`. */
export const Eyes: React.FC<{width: number; blinks?: number[]; style?: React.CSSProperties}> = ({width, blinks = [], style}) => {
	const frame = useCurrentFrame();
	const lid = blinks.reduce((open, at) => Math.min(open, interpolate(frame, [at, at + 4, at + 9], [1, 0.08, 1], clamp)), 1);
	return <Img src={staticFile('eyes-idle.png')} style={{width, height: width / 2, scale: `1 ${lid}`, ...style}} />;
};

/** Every scene leaves the same way: a quick settle back and fade, so cuts feel like one continuous piece. */
export const Scene: React.FC<{children: React.ReactNode; style?: React.CSSProperties}> = ({children, style}) => {
	const frame = useCurrentFrame();
	const {durationInFrames} = useVideoConfig();
	const out = interpolate(frame, [durationInFrames - 10, durationInFrames], [0, 1], {...clamp, easing: Easing.in(Easing.cubic)});
	return (
		<AbsoluteFill
			style={{
				backgroundColor: C.bg,
				alignItems: 'center',
				justifyContent: 'center',
				flexDirection: 'column',
				opacity: 1 - out,
				// The slow camera push of Apple's product films, then a small settle on the way out.
				scale: String((1 + (frame / durationInFrames) * 0.05) * (1 - out * 0.03)),
				...style,
			}}
		>
			{children}
		</AbsoluteFill>
	);
};

/** A Mac display with a deep-blue wallpaper, so the black notch reads against it. Fades in at `delay`. */
export const Screen: React.FC<{delay?: number}> = ({delay = 0}) => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const p = interpolate(frame, [delay, delay + 24], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
	return (
		<div
			style={{
				position: 'absolute',
				inset: 36 * u,
				borderRadius: 34 * u,
				opacity: p,
				background: `radial-gradient(80% 90% at 25% 0%, rgba(10,132,255,0.55) 0%, transparent 65%), radial-gradient(70% 80% at 85% 30%, rgba(10,132,255,0.3) 0%, transparent 70%), radial-gradient(90% 60% at 50% 110%, rgba(10,132,255,0.25) 0%, transparent 70%), #05070D`,
			}}
		/>
	);
};

/** The notch, growing from its resting size into an open panel as `open` goes 0→1. Hangs from the top edge. */
export const Notch: React.FC<{
	open: number;
	width: number;
	height: number;
	rest?: {width: number; height: number};
	top?: number;
	edge?: boolean; // a hairline when the notch sits on plain black instead of a wallpaper
	children?: React.ReactNode;
}> = ({open, width, height, rest = {width: 230, height: 40}, top = 36, edge = false, children}) => {
	const u = useUnit();
	return (
		<div
			style={{
				position: 'absolute',
				top: top * u,
				left: '50%',
				translate: '-50% 0',
				width: (rest.width + (width - rest.width) * open) * u,
				height: (rest.height + (height - rest.height) * open) * u,
				background: C.notch,
				borderRadius: `0 0 ${(14 + 24 * open) * u}px ${(14 + 24 * open) * u}px`,
				boxShadow: `0 ${24 * u}px ${70 * u}px rgba(0,0,0,${0.6 * open})`,
				border: edge ? `${1.5 * u}px solid ${C.line}` : undefined,
				borderTop: 'none',
				overflow: 'hidden',
				fontFamily,
				color: C.text,
			}}
		>
			<div style={{opacity: interpolate(open, [0.6, 1], [0, 1], clamp), width: width * u, padding: `${18 * u}px ${28 * u}px`}}>{children}</div>
		</div>
	);
};

/** Keycaps that press down at `press`. */
export const Keys: React.FC<{keys: string[]; delay?: number; press: number; style?: React.CSSProperties}> = ({keys, delay = 0, press, style}) => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const p = useIn(delay);
	const down = interpolate(frame, [press, press + 3, press + 10], [0, 1, 0], clamp);
	return (
		<div style={{display: 'flex', gap: 14 * u, opacity: p, translate: `0 ${(1 - p) * 20 * u}px`, ...style}}>
			{keys.map((k) => (
				<div
					key={k}
					style={{
						minWidth: 92 * u,
						height: 92 * u,
						padding: `0 ${22 * u}px`,
						borderRadius: 18 * u,
						background: `linear-gradient(${C.tileEdge}, ${C.tile})`,
						border: `${2 * u}px solid ${down > 0.3 ? C.blue : C.line}`,
						boxShadow: `0 ${(6 - 4 * down) * u}px 0 #000`,
						translate: `0 ${4 * down * u}px`,
						display: 'flex',
						alignItems: 'center',
						justifyContent: 'center',
						fontFamily: `${fontFamily}, -apple-system, system-ui`,
						fontSize: 40 * u,
						fontWeight: 500,
						color: C.text,
					}}
				>
					{k}
				</div>
			))}
		</div>
	);
};

/** Text typed one character every `every` frames from `from`, with a key sound for each. */
export const Typed: React.FC<{text: string; from: number; every?: number; caret?: boolean}> = ({text, from, every = 4, caret = true}) => {
	const frame = useCurrentFrame();
	const shown = Math.max(0, Math.min(text.length, Math.floor((frame - from) / every) + 1));
	return (
		<>
			{text.slice(0, frame < from ? 0 : shown)}
			{caret && <span style={{color: C.blue, opacity: frame % 30 < 16 ? 1 : 0}}>|</span>}
			{text.split('').map((ch, i) => (ch === ' ' ? null : <Sfx key={i} name="key" at={from + i * every} volume={0.35} />))}
		</>
	);
};

/** A dark tile like the app's notch tiles. */
export const Tile: React.FC<{delay?: number; children: React.ReactNode; style?: React.CSSProperties}> = ({delay = 0, children, style}) => {
	const u = useUnit();
	const p = useIn(delay, SPRING.content);
	return (
		<div
			style={{
				background: `linear-gradient(${C.tileEdge}, ${C.tile})`,
				borderRadius: 22 * u,
				padding: `${20 * u}px ${28 * u}px`,
				fontFamily,
				color: C.text,
				opacity: Math.min(1, p * 1.5),
				translate: `0 ${(1 - p) * 30 * u}px`,
				...style,
			}}
		>
			{children}
		</div>
	);
};

/** One of the soundtrack's interface sounds (public/sfx, made by sound/make_sounds.py). */
export const Sfx: React.FC<{name: 'tick' | 'key' | 'whoosh' | 'tap' | 'chime'; at: number; volume?: number}> = ({name, at, volume = 0.6}) => {
	const {fps} = useVideoConfig();
	return <Audio src={staticFile(`sfx/${name}.wav`)} from={at} volume={volume} premountFor={fps} />;
};

/** Small line icons in the style of SF Symbols. */
export const Icon: React.FC<{name: 'doc' | 'link' | 'photo' | 'file' | 'note' | 'check' | 'bell' | 'space' | 'lock' | 'search'; size: number; color?: string}> = ({
	name,
	size,
	color = C.blue,
}) => {
	const paths: Record<string, React.ReactNode> = {
		doc: <path d="M6 3h8l4 4v14H6z M14 3v4h4 M9 12h6 M9 16h6" />,
		link: <path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1 M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" />,
		photo: <path d="M4 5h16v14H4z M4 16l5-5 4 4 3-3 4 4 M15.5 9a1 1 0 1 0 0 .01" />,
		file: <path d="M6 3h8l4 4v14H6z M14 3v4h4 M8.5 15h7" />,
		note: <path d="M5 4h14v16H5z M8 8h8 M8 12h8 M8 16h5" />,
		check: <path d="M4 12a8 8 0 1 0 16 0a8 8 0 1 0-16 0 M8.5 12l2.5 2.5 4.5-5" />,
		bell: <path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z M10 20.5a2 2 0 0 0 4 0" />,
		space: <path d="M4 5h7v6H4z M13 5h7v6h-7z M4 13h7v6H4z M13 13h7v6h-7z" />,
		lock: <path d="M6 11h12v9H6z M8.5 11V8a3.5 3.5 0 0 1 7 0v3" />,
		search: <path d="M10.5 4a6.5 6.5 0 1 0 0 13a6.5 6.5 0 1 0 0-13 M15.5 15.5L20 20" />,
	};
	return (
		<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" style={{flexShrink: 0}}>
			{paths[name]}
		</svg>
	);
};

/** A one-line caption near the bottom of the frame, shown between `from` and `to`. */
export const Caption: React.FC<{text: string; from: number; to: number; accent?: Record<string, string>}> = ({text, from, to, accent}) => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const {width} = useVideoConfig();
	const o = interpolate(frame, [from, from + 14, to - 10, to], [0, 1, 1, 0], clamp);
	return (
		<div style={{position: 'absolute', bottom: 110 * u, left: 0, width, display: 'flex', justifyContent: 'center', opacity: o}}>
			<Words text={text} size={76} delay={from} accent={accent} />
		</div>
	);
};
