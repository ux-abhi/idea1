import {interpolate, useCurrentFrame} from 'remotion';
import {Scene, Tile, Words} from '../kinetic';
import {BEAT, C, fontFamily, SPRING, useIn, useUnit} from '../theme';

const ASK = 'Send it on the 15th.';

// 12–15s: the owner says when; Touch ID approves; the ring turns green.
export const Send = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const typed = Math.round(interpolate(frame, [20, 70], [0, ASK.length], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}));
	const ring = interpolate(frame, [3 * BEAT, 4 * BEAT + 10], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	const done = useIn(4 * BEAT + 12, SPRING.open);
	const r = 70 * u;
	const tint = done > 0.5 ? C.green : C.text;
	return (
		<Scene>
			<Words text="Drafts the reply." size={120} />
			<Words text="Sends it when you say." size={120} delay={2 * BEAT} accent={{'say.': C.mint}} />
			<div style={{display: 'flex', alignItems: 'center', gap: 40 * u, marginTop: 60 * u}}>
				<Tile delay={10} style={{fontSize: 40 * u, minWidth: 560 * u}}>
					{ASK.slice(0, typed)}
					<span style={{opacity: frame % 30 < 15 ? 1 : 0, color: C.mint}}>|</span>
				</Tile>
				<svg width={r * 2.4} height={r * 2.4} viewBox="-60 -60 120 120" style={{overflow: 'visible'}}>
					<circle r={50} fill="none" stroke={C.tileEdge} strokeWidth={6} />
					<circle
						r={50}
						fill="none"
						stroke={tint}
						strokeWidth={6}
						strokeLinecap="round"
						strokeDasharray={2 * Math.PI * 50}
						strokeDashoffset={2 * Math.PI * 50 * (1 - ring)}
						transform="rotate(-90)"
					/>
					{/* Fingerprint arcs, then a check once approved. */}
					<g stroke={tint} strokeWidth={4} fill="none" strokeLinecap="round" opacity={1 - done}>
						<path d="M-18 14 A22 22 0 0 1 -22 0 A22 22 0 0 1 22 0" />
						<path d="M-10 20 A14 14 0 0 1 -14 4 A14 14 0 0 1 14 4 L14 14" />
						<path d="M0 22 L0 6" />
					</g>
					<path d="M-20 2 L-6 16 L22 -14" stroke={C.green} strokeWidth={8} fill="none" strokeLinecap="round" strokeLinejoin="round" opacity={done} />
				</svg>
			</div>
			<div style={{fontFamily, fontSize: 30 * u, color: C.green, marginTop: 24 * u, opacity: done}}>Approved with Touch ID</div>
		</Scene>
	);
};
