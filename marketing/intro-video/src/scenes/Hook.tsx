import {interpolate, useCurrentFrame} from 'remotion';
import {Scene, Sfx, Words} from '../kinetic';
import {BEAT, C} from '../theme';

// 3.5–7s: the promise in two lines.
export const Hook = () => {
	const frame = useCurrentFrame();
	const firstAway = interpolate(frame, [3 * BEAT, 3 * BEAT + 12], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<Scene>
			<div style={{position: 'absolute', opacity: firstAway, translate: `0 ${(1 - firstAway) * -40}px`}}>
				<Words text="Your Mac has a notch." />
			</div>
			<Words text="Now it has a brain." delay={3 * BEAT + 6} stagger={5} accent={{'brain.': C.blue}} />
			<Sfx name="swoosh" at={0} volume={0.5} />
			<Sfx name="swoosh" at={3 * BEAT + 2} volume={0.5} />
			<Sfx name="sparkle" at={3 * BEAT + 26} volume={0.3} />
		</Scene>
	);
};
