import {interpolate, useCurrentFrame} from 'remotion';
import {Scene, Words} from '../kinetic';
import {BEAT, C} from '../theme';

// 3–6.5s: the promise in two lines; "brain." lands on the beat.
export const Hook = () => {
	const frame = useCurrentFrame();
	const firstAway = interpolate(frame, [3 * BEAT, 3 * BEAT + 12], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<Scene>
			<div style={{position: 'absolute', opacity: firstAway, translate: `0 ${(1 - firstAway) * -60}px`}}>
				<Words text="Your Mac has a notch." />
			</div>
			<Words text="Now it has a brain." delay={3 * BEAT + 6} stagger={6} accent={{'brain.': C.indigo}} />
		</Scene>
	);
};
