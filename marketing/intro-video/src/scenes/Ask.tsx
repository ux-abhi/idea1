import {interpolate, useCurrentFrame} from 'remotion';
import {Caption, Eyes, Keys, Notch, Scene, Screen, Sfx, Sub, Typed, Words} from '../kinetic';
import {C, SPRING, useIn, useUnit} from '../theme';

const REPLY = 'Thesis review at 2 pm, gym at 6. Two emails need you.';

// 12–17s: ⌃⌥Space opens a chat right in the notch.
export const Ask = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const title = interpolate(frame, [70, 86], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	const open = useIn(116, SPRING.open);
	const words = REPLY.split(' ');
	const shown = Math.max(0, Math.floor((frame - 200) / 3));
	return (
		<Scene>
			<div style={{opacity: title, position: 'absolute'}}>
				<Words text="Ask anything." />
				<Sub text="Right from the notch." />
			</div>
			{frame >= 80 && (
				<>
					<Screen delay={80} />
					<Keys keys={['⌃', '⌥', 'Space']} delay={86} press={110} style={{position: 'absolute', bottom: 150 * u, opacity: interpolate(frame, [86, 98, 124, 140], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}} />
					<Notch open={open} width={860} height={250}>
						<div style={{display: 'flex', alignItems: 'center', gap: 16 * u}}>
							<Eyes width={80 * u} />
							<div style={{fontSize: 24 * u, color: C.gray}}>Ask Blink</div>
						</div>
						<div style={{marginTop: 18 * u, fontSize: 34 * u, fontWeight: 500}}>
							<Typed text="What's left today?" from={134} every={3} caret={frame < 196} />
						</div>
						<div style={{marginTop: 18 * u, fontSize: 32 * u, color: C.gray, lineHeight: 1.35}}>
							{words.slice(0, shown).join(' ')}
						</div>
					</Notch>
					<Caption text="Your day, in one answer." from={220} to={300} />
					<Sfx name="swoosh" at={0} volume={0.5} />
					<Sfx name="tap" at={110} volume={0.7} />
					<Sfx name="whoosh" at={112} volume={0.45} />
					<Sfx name="pop" at={200} volume={0.5} />
				</>
			)}
		</Scene>
	);
};
