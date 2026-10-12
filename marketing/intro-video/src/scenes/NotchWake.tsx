import {Easing, interpolate, useCurrentFrame} from 'remotion';
import {Eyes, Scene} from '../kinetic';
import {C, SPRING, useIn, useUnit} from '../theme';

// 0–3s: a MacBook screen edge; the notch wakes, widens, and Blink opens its eyes.
export const NotchWake = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const screen = interpolate(frame, [0, 40], [0, 1], {extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic)});
	const open = useIn(60, SPRING.open);
	const w = (300 + 260 * open) * u;
	const h = (70 + 80 * open) * u;
	return (
		<Scene style={{justifyContent: 'flex-start'}}>
			{/* The display: graphite glass so the pure-black notch reads against it. */}
			<div
				style={{
					position: 'absolute',
					inset: 40 * u,
					borderRadius: 36 * u,
					// A Tahoe-like wallpaper glow in Blink's mood colours (indigo, mint) so the black notch stands out.
					background: `radial-gradient(70% 80% at 30% 10%, ${C.indigo}99 0%, transparent 70%), radial-gradient(60% 70% at 75% 20%, ${C.mint}66 0%, transparent 70%), #1C1C1E`,
					opacity: screen,
				}}
			/>
			<div
				style={{
					position: 'relative',
					marginTop: 40 * u,
					width: w,
					height: h,
					background: C.notch,
					borderRadius: `0 0 ${34 * u}px ${34 * u}px`,
					display: 'flex',
					alignItems: 'center',
					justifyContent: 'center',
					opacity: screen,
					boxShadow: `0 ${20 * u}px ${80 * u}px rgba(0,0,0,0.8)`,
				}}
			>
				<Eyes
					mood="idle"
					width={300 * u}
					blinks={[130]}
					style={{opacity: interpolate(frame, [80, 100], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}), marginTop: 10 * u}}
				/>
			</div>
		</Scene>
	);
};
