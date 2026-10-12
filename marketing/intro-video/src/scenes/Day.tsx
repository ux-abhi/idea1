import {Scene, Words} from '../kinetic';
import {C, fontFamily, SPRING, useIn, useUnit} from '../theme';

const BLOCKS = [
	{label: 'Standup', start: 9.5, end: 10, color: C.mint},
	{label: 'Deep work', start: 10, end: 12, color: C.indigo},
	{label: 'Lunch', start: 12.5, end: 13.25, color: C.orange},
	{label: 'Thesis', start: 14, end: 16, color: C.purple},
	{label: 'Gym', start: 17.5, end: 18.5, color: C.green},
];
const FROM = 9;
const TO = 19;

// 15–17.5s: the day snaps into a timeline.
export const Day = () => {
	const u = useUnit();
	const width = 1100 * u;
	return (
		<Scene>
			<Words text="Plans your day." size={140} />
			<div style={{position: 'relative', width, height: 110 * u, marginTop: 70 * u, borderRadius: 20 * u, background: C.tile}}>
				{BLOCKS.map((b, i) => (
					<Block key={b.label} {...b} i={i} left={((b.start - FROM) / (TO - FROM)) * width} w={((b.end - b.start) / (TO - FROM)) * width} />
				))}
			</div>
			<div style={{display: 'flex', justifyContent: 'space-between', width, fontFamily, fontSize: 24 * u, color: C.dim, marginTop: 12 * u}}>
				{['9', '11', '13', '15', '17', '19'].map((h) => (
					<span key={h}>{h}:00</span>
				))}
			</div>
		</Scene>
	);
};

const Block: React.FC<{label: string; color: string; i: number; left: number; w: number}> = ({label, color, i, left, w}) => {
	const u = useUnit();
	const p = useIn(14 + i * 6, SPRING.cardIn);
	return (
		<div
			style={{
				position: 'absolute',
				left,
				top: 12 * u,
				bottom: 12 * u,
				width: w - 6 * u,
				borderRadius: 14 * u,
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
