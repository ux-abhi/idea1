import {interpolate, useCurrentFrame} from 'remotion';
import {Eyes, Notch, Scene, Screen, Sfx} from '../kinetic';
import {SPRING, useIn, useUnit} from '../theme';

// 0–3.5s: a Mac display; the notch wakes, widens a little, and Blink opens its eyes.
export const NotchWake = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const open = useIn(50, SPRING.open);
	return (
		<Scene>
			<Screen />
			<Notch open={open} width={340} height={78} rest={{width: 230, height: 40}}>
				<div style={{display: 'flex', justifyContent: 'center', marginTop: -6 * u}}>
					<Eyes width={130 * u} blinks={[140]} style={{opacity: interpolate(frame, [70, 90], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}} />
				</div>
			</Notch>
			<Sfx name="tap" at={50} volume={0.7} />
		</Scene>
	);
};
