import {interpolate, useCurrentFrame} from 'remotion';
import {Scene, Sfx, Tile, Typed, Words} from '../kinetic';
import {C, fontFamily, useIn, useUnit} from '../theme';

// 22–26.5s: the owner says when; Touch ID approves.
export const Send = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const ring = interpolate(frame, [150, 200], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	const done = useIn(204);
	return (
		<Scene>
			<Words text="Drafts the reply." size={110} />
			<Words text="Sends it when you say." size={110} delay={50} accent={{'say.': C.blue}} />
			<div style={{display: 'flex', alignItems: 'center', gap: 40 * u, marginTop: 60 * u}}>
				<Tile delay={80} style={{fontSize: 36 * u, minWidth: 520 * u}}>
					<Typed text="Send it on the 15th." from={95} every={3} caret={frame < 150} />
				</Tile>
				<svg width={150 * u} height={150 * u} viewBox="-60 -60 120 120" style={{overflow: 'visible', opacity: interpolate(frame, [130, 145], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}}>
					<circle r={50} fill="none" stroke={C.tileEdge} strokeWidth={5} />
					<circle r={50} fill="none" stroke={C.blue} strokeWidth={5} strokeLinecap="round" strokeDasharray={2 * Math.PI * 50} strokeDashoffset={2 * Math.PI * 50 * (1 - ring)} transform="rotate(-90)" />
					<g stroke={C.text} strokeWidth={3.5} fill="none" strokeLinecap="round" opacity={1 - done}>
						<path d="M-18 14 A22 22 0 0 1 -22 0 A22 22 0 0 1 22 0" />
						<path d="M-10 20 A14 14 0 0 1 -14 4 A14 14 0 0 1 14 4 L14 14" />
						<path d="M0 22 L0 6" />
					</g>
					<path d="M-20 2 L-6 16 L22 -14" stroke={C.blue} strokeWidth={7} fill="none" strokeLinecap="round" strokeLinejoin="round" opacity={done} />
				</svg>
			</div>
			<div style={{fontFamily, fontSize: 28 * u, color: C.gray, marginTop: 24 * u, opacity: done}}>Approved with Touch ID. Sends on the 15th.</div>
			<Sfx name="swoosh" at={0} volume={0.5} />
			<Sfx name="swoosh" at={48} volume={0.45} />
			<Sfx name="pop" at={80} volume={0.4} />
			<Sfx name="tap" at={150} volume={0.6} />
			<Sfx name="rise" at={150} volume={0.4} />
			<Sfx name="chime" at={204} volume={0.5} />
		</Scene>
	);
};
