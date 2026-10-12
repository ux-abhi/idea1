import {interpolate, useCurrentFrame} from 'remotion';
import {Caption, Eyes, Keys, Notch, Scene, Screen, Sfx, Sub, Typed, Words} from '../kinetic';
import {C, SPRING, useIn, useUnit} from '../theme';

const REPLY = 'Thesis review at 2 pm, gym at 6. Two emails need you.';

// 12–18s: ⌃⌥Space opens a chat right in the notch.
export const Ask = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const title = interpolate(frame, [80, 96], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	const open = useIn(130, SPRING.open);
	const words = REPLY.split(' ');
	const shown = Math.max(0, Math.floor((frame - 230) / 3));
	return (
		<Scene>
			<div style={{opacity: title, position: 'absolute'}}>
				<Words text="Ask anything." />
				<Sub text="Right from the notch." />
			</div>
			{frame >= 90 && (
				<>
					<Screen delay={90} />
					<Keys keys={['⌃', '⌥', 'Space']} delay={96} press={124} style={{position: 'absolute', bottom: 150 * u, opacity: interpolate(frame, [96, 110, 140, 156], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}} />
					<Notch open={open} width={860} height={250}>
						<div style={{display: 'flex', alignItems: 'center', gap: 16 * u}}>
							<Eyes width={80 * u} />
							<div style={{fontSize: 24 * u, color: C.gray}}>Ask Blink</div>
						</div>
						<div style={{marginTop: 18 * u, fontSize: 34 * u, fontWeight: 500}}>
							<Typed text="What's left today?" from={150} every={3} caret={frame < 210} />
						</div>
						<div style={{marginTop: 18 * u, fontSize: 32 * u, color: C.gray, lineHeight: 1.35}}>
							{words.slice(0, shown).join(' ')}
						</div>
					</Notch>
					<Caption text="Your day, in one answer." from={250} to={360} />
					<Sfx name="tap" at={124} volume={0.7} />
					<Sfx name="tick" at={230} volume={0.4} />
				</>
			)}
		</Scene>
	);
};
