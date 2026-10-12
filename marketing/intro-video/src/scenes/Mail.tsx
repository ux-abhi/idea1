import {interpolate, useCurrentFrame} from 'remotion';
import {Eyes, Scene, Sfx, Sub, Tile, Words} from '../kinetic';
import {C, useUnit} from '../theme';

const MAIL = [
	{from: 'Job Alerts', subject: '25 new jobs picked for you', spam: true},
	{from: 'Prof. Weber', subject: 'Thesis meeting moved to Friday', spam: false},
	{from: 'StreamBox', subject: 'Your plan renews in 3 days', spam: true},
	{from: 'Weekly Digest', subject: 'This week in design', spam: true},
];

// 16.8–21.6s: mail triage. The noise steps back; the one that matters comes forward in red (mood.important).
export const Mail = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const sort = interpolate(frame, [120, 140], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<Scene>
			<Words text="It reads your mail." size={110} />
			<div style={{display: 'flex', flexDirection: 'column', gap: 12 * u, marginTop: 50 * u, width: 860 * u}}>
				{MAIL.map((m, i) => (
					<Tile
						key={m.from}
						delay={30 + i * 6}
						style={{
							display: 'flex',
							alignItems: 'center',
							opacity: m.spam ? 1 - sort * 0.65 : 1,
							outline: m.spam ? undefined : `${2 * u}px solid rgba(255,69,58,${sort})`,
							boxShadow: m.spam ? undefined : `0 0 ${40 * u * sort}px rgba(255,69,58,${0.45 * sort})`,
							scale: m.spam ? String(1 - sort * 0.02) : String(1 + sort * 0.03),
						}}
					>
						<div style={{flex: 1}}>
							<div style={{fontSize: 28 * u, fontWeight: 600}}>{m.from}</div>
							<div style={{fontSize: 32 * u, color: C.gray}}>{m.subject}</div>
						</div>
						{m.spam ? (
							<div style={{fontSize: 24 * u, fontWeight: 600, color: C.gray, opacity: sort}}>Not important</div>
						) : (
							<Eyes mood="important" width={90 * u} style={{opacity: sort}} />
						)}
					</Tile>
				))}
			</div>
			<Sub text="And tells you what matters." delay={170} />
			<Sfx name="swoosh" at={0} volume={0.5} />
			{[0, 1, 2, 3].map((i) => (
				<Sfx key={i} name="pop" at={30 + i * 6} volume={0.4} />
			))}
			<Sfx name="rise" at={112} volume={0.4} />
			<Sfx name="sparkle" at={124} volume={0.3} />
			<Sfx name="swoosh" at={168} volume={0.35} />
		</Scene>
	);
};
