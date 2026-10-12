import {Scene, Sfx, Words} from '../kinetic';
import {C, fontFamily, SPRING, useIn, useUnit} from '../theme';

// One blue, several strengths: the Apple-film palette.
const BLOCKS = [
	{label: 'Standup', start: 9.5, end: 10, alpha: 0.45},
	{label: 'Deep work', start: 10, end: 12, alpha: 1},
	{label: 'Lunch', start: 12.5, end: 13.25, alpha: 0.35},
	{label: 'Thesis', start: 14, end: 16, alpha: 0.8},
	{label: 'Gym', start: 17.5, end: 18.5, alpha: 0.55},
];
const FROM = 9;
const TO = 19;

// 42–45s: the day snaps into a timeline.
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
			<Sfx name="tick" at={20} volume={0.35} />
		</Scene>
	);
};

const Block: React.FC<{label: string; alpha: number; i: number; left: number; w: number}> = ({label, alpha, i, left, w}) => {
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
				background: `rgba(10,132,255,${alpha})`,
				scale: `${p} 1`,
				transformOrigin: 'left',
				opacity: Math.min(1, p * 2),
				display: 'flex',
				alignItems: 'flex-end',
				padding: 10 * u,
				fontFamily,
				fontWeight: 600,
				fontSize: 22 * u,
				color: C.text,
				overflow: 'hidden',
				whiteSpace: 'nowrap',
			}}
		>
			{w > 90 * u ? label : ''}
		</div>
	);
};
