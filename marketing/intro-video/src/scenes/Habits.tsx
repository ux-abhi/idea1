import {interpolate, useCurrentFrame} from 'remotion';
import {Icon, Scene, Sfx, Sub, Tile, Words} from '../kinetic';
import {C, useUnit} from '../theme';

const HABITS = [
	{name: 'Read 20 minutes', done: [1, 1, 1, 1, 1, 1, 1], streak: 21},
	{name: 'Gym', done: [1, 0, 1, 0, 1, 1, 1], streak: 12},
	{name: 'No phone after 11', done: [1, 1, 1, 1, 1, 1, 1], streak: 7},
];
const WEEK = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

// 46–49.5s: habits fill in day by day, streaks count up; the 7-day milestone glows.
export const Habits = () => {
	const u = useUnit();
	return (
		<Scene>
			<Words text="Keeps your streaks alive." size={110} />
			<Sub text="A nudge at the right moment, never a nag." delay={16} />
			<div style={{display: 'flex', flexDirection: 'column', gap: 14 * u, marginTop: 50 * u, width: 1100 * u}}>
				{HABITS.map((h, i) => (
					<Row key={h.name} {...h} i={i} />
				))}
			</div>
			<Sfx name="swoosh" at={0} volume={0.5} />
			{[0, 1, 2].map((i) => (
				<Sfx key={i} name="pop" at={30 + i * 8} volume={0.4} />
			))}
			{[0, 1, 2, 3, 4, 5, 6].map((k) => (
				<Sfx key={k} name="tick" at={40 + k * 5} volume={0.3} />
			))}
			<Sfx name="roll" at={50} volume={0.35} />
			<Sfx name="sparkle" at={126} volume={0.45} />
		</Scene>
	);
};

const Row: React.FC<{name: string; done: number[]; streak: number; i: number}> = ({name, done, streak, i}) => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const start = 30 + i * 8;
	const count = Math.round(interpolate(frame, [start + 20, start + 80], [0, streak], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}));
	const milestone = streak === 7 && count === 7;
	return (
		<Tile delay={start} style={{display: 'flex', alignItems: 'center', gap: 30 * u, outline: milestone ? `${2 * u}px solid ${C.blue}` : undefined}}>
			<div style={{flex: 1, fontSize: 32 * u, fontWeight: 500}}>{name}</div>
			<div style={{display: 'flex', gap: 12 * u}}>
				{done.map((d, k) => {
					const on = interpolate(frame, [start + 10 + k * 5, start + 18 + k * 5], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
					return (
						<div key={k} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 * u}}>
							<div style={{width: 40 * u, height: 40 * u, borderRadius: 99, border: `${2 * u}px solid ${C.line}`, background: d ? `rgba(10,132,255,${on})` : 'transparent', scale: String(d ? 0.85 + 0.15 * on : 1)}} />
							<div style={{fontSize: 18 * u, color: C.gray}}>{WEEK[k]}</div>
						</div>
					);
				})}
			</div>
			<div style={{display: 'flex', alignItems: 'center', gap: 8 * u, width: 210 * u, justifyContent: 'flex-end', whiteSpace: 'nowrap', fontSize: 34 * u, fontWeight: 600, fontVariantNumeric: 'tabular-nums'}}>
				<Icon name="flame" size={34 * u} color={C.blue} />
				{count} days
			</div>
		</Tile>
	);
};
