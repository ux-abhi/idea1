import {interpolate, useCurrentFrame} from 'remotion';
import {Scene, Sfx, Words} from '../kinetic';
import {C, fontFamily, SPRING, useIn, useUnit} from '../theme';

const BLOCKS = [
	{label: 'Standup', start: 9.5, end: 10, color: C.mint},
	{label: 'Deep work', start: 10, end: 12, color: C.blue},
	{label: 'Lunch', start: 12.5, end: 13.25, color: C.orange},
	{label: 'Thesis', start: 14, end: 16, color: C.yellow},
	{label: 'Gym', start: 17.5, end: 18.5, color: C.green},
];
const FROM = 9;
const TO = 19;

// 41.4–43.8s: the day snaps into a timeline; today's rings fill.
export const Day = () => {
	const u = useUnit();
	const width = 1100 * u;
	return (
		<Scene>
			<Words text="Plans your day." size={120} />
			<div style={{position: 'relative', width, height: 100 * u, marginTop: 60 * u, borderRadius: 20 * u, background: C.tile}}>
				{BLOCKS.map((b, i) => (
					<Block key={b.label} {...b} i={i} left={((b.start - FROM) / (TO - FROM)) * width} w={((b.end - b.start) / (TO - FROM)) * width} />
				))}
			</div>
			<div style={{display: 'flex', justifyContent: 'space-between', width, fontFamily, fontSize: 22 * u, color: C.gray, marginTop: 12 * u}}>
				{['9', '11', '13', '15', '17', '19'].map((h) => (
					<span key={h}>{h}:00</span>
				))}
			</div>
			<div style={{display: 'flex', gap: 70 * u, marginTop: 50 * u}}>
				<DayRing label="Tasks" value="4 of 6" share={4 / 6} delay={50} color={C.green} />
				<DayRing label="Focus" value="2 h 10 m" share={0.65} delay={56} color={C.blue} />
				<DayRing label="Habits" value="2 of 3" share={2 / 3} delay={62} color={C.yellow} />
			</div>
			<Sfx name="swoosh" at={0} volume={0.5} />
			{[0, 1, 2, 3, 4].map((i) => (
				<Sfx key={i} name="pop" at={20 + i * 6} volume={0.3} />
			))}
			<Sfx name="rise" at={50} volume={0.4} />
		</Scene>
	);
};

const DayRing: React.FC<{label: string; value: string; share: number; delay: number; color: string}> = ({label, value, share, delay, color}) => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const t = interpolate(frame, [delay, delay + 50], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	const r = 40;
	return (
		<div style={{display: 'flex', alignItems: 'center', gap: 18 * u, fontFamily, opacity: Math.min(1, t * 3)}}>
			<svg width={96 * u} height={96 * u} viewBox="-50 -50 100 100">
				<circle r={r} fill="none" stroke={C.line} strokeWidth={10} />
				<circle r={r} fill="none" stroke={color} strokeWidth={10} strokeLinecap="round" strokeDasharray={2 * Math.PI * r} strokeDashoffset={2 * Math.PI * r * (1 - share * t)} transform="rotate(-90)" />
			</svg>
			<div>
				<div style={{fontSize: 22 * u, color: C.gray}}>{label}</div>
				<div style={{fontSize: 32 * u, fontWeight: 600, color: C.text}}>{value}</div>
			</div>
		</div>
	);
};

const Block: React.FC<{label: string; color: string; i: number; left: number; w: number}> = ({label, color, i, left, w}) => {
	const u = useUnit();
	const p = useIn(20 + i * 6, SPRING.content);
	return (
		<div
			style={{
				position: 'absolute',
				left,
				top: 12 * u,
				bottom: 12 * u,
				width: w - 6 * u,
				borderRadius: 12 * u,
				background: color,
				scale: `${p} 1`,
				transformOrigin: 'left',
				opacity: Math.min(1, p * 2),
				display: 'flex',
				alignItems: 'flex-end',
				padding: 10 * u,
				fontFamily,
				fontWeight: 600,
				fontSize: 22 * u,
				color: '#000',
				overflow: 'hidden',
				whiteSpace: 'nowrap',
			}}
		>
			{w > 90 * u ? label : ''}
		</div>
	);
};
