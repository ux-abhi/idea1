import {interpolate, useCurrentFrame} from 'remotion';
import {Eyes, Scene, Words} from '../kinetic';
import {C, fontFamily, useIn, useUnit} from '../theme';

// 56–60s: the wordmark; one last blink.
export const End = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const p = useIn(0);
	const sub = interpolate(frame, [36, 56], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<Scene>
			<Eyes width={170 * u} blinks={[110]} style={{opacity: p, marginBottom: 16 * u}} />
			<Words text="Blink" size={200} />
			<div style={{fontFamily, fontSize: 40 * u, color: C.gray, opacity: sub, marginTop: 14 * u}}>
				for Mac · <span style={{color: C.blue}}>Coming soon</span>
			</div>
		</Scene>
	);
};
