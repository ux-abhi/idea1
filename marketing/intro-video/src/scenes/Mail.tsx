import {interpolate, useCurrentFrame} from 'remotion';
import {Eyes, Scene, Tile, Words} from '../kinetic';
import {BEAT, C, fontFamily, useUnit} from '../theme';

const MAIL = [
	{from: 'Job Alerts', subject: '25 new jobs picked for you', spam: true},
	{from: 'Prof. Weber', subject: 'Thesis meeting moved to Friday', spam: false},
	{from: 'StreamBox', subject: 'Your plan renews in 3 days', spam: true},
	{from: 'Weekly Digest', subject: 'This week in design', spam: true},
];

// 9–12s: mail triage — noise fades out, the one that matters lights up red.
export const Mail = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const sort = interpolate(frame, [2 * BEAT, 2 * BEAT + 16], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<Scene>
			<Words text="It reads your mail." size={120} />
			<div style={{display: 'flex', flexDirection: 'column', gap: 14 * u, marginTop: 50 * u, width: 900 * u}}>
				{MAIL.map((m, i) => (
					<Tile
						key={m.from}
						delay={8 + i * 5}
						style={{
							display: 'flex',
							alignItems: 'center',
							gap: 24 * u,
							opacity: m.spam ? 1 - sort * 0.7 : 1,
							boxShadow: m.spam ? undefined : `0 0 ${50 * u * sort}px ${C.red}${Math.round(sort * 140).toString(16).padStart(2, '0')}`,
							outline: m.spam ? undefined : `${3 * u}px solid rgba(255,69,58,${sort})`,
							scale: m.spam ? String(1 - sort * 0.03) : String(1 + sort * 0.04),
						}}
					>
						<div style={{flex: 1}}>
							<div style={{fontSize: 30 * u, fontWeight: 600}}>{m.from}</div>
							<div style={{fontSize: 34 * u, color: C.dim, textDecoration: m.spam && sort > 0.5 ? 'line-through' : undefined}}>{m.subject}</div>
						</div>
						{m.spam ? (
							<div style={{fontFamily, fontSize: 24 * u, color: C.dim, opacity: sort}}>Not important</div>
						) : (
							<Eyes mood="important" width={120 * u} style={{opacity: sort}} />
						)}
					</Tile>
				))}
			</div>
			<Words text="…and tells you what matters." size={64} weight={600} delay={3 * BEAT + 10} stagger={3} style={{marginTop: 40 * u}} accent={{'matters.': C.red}} />
		</Scene>
	);
};
