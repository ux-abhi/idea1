import {interpolate, useCurrentFrame} from 'remotion';
import {Eyes, Scene, Words} from '../kinetic';
import {C, fontFamily, SPRING, useIn, useUnit} from '../theme';

// 28–30s: the wordmark; one last blink.
export const End = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const p = useIn(0, SPRING.open);
	const sub = interpolate(frame, [30, 50], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<Scene>
			<Eyes mood="idle" width={360 * u} blinks={[80]} style={{scale: String(1.3 - 0.3 * p), opacity: p}} />
			<Words text="Blink" size={230} />
			<div style={{fontFamily, fontSize: 44 * u, color: C.dim, opacity: sub, marginTop: 10 * u}}>
				for Mac · Coming soon
			</div>
		</Scene>
	);
};
