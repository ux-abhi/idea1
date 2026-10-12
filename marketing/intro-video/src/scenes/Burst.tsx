import {Sequence, useCurrentFrame} from 'remotion';
import {Scene, Sfx, Words} from '../kinetic';
import {C, SPRING, useUnit} from '../theme';

// 50–53s: everything else, one word per half-beat, then all of it at once.
const MORE = ['Reminders', 'Habits', 'Streaks', 'Focus timer', 'Calendar', 'Post insights', 'Spaces', 'Quick commands'];
const EACH = 15;

export const Burst = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const all = MORE.length * EACH;
	return (
		<Scene>
			{MORE.map((word, i) => (
				<Sequence key={word} from={i * EACH} durationInFrames={EACH} layout="none">
					<Words text={word} size={170} stagger={1} config={SPRING.snap} />
					<Sfx name="tick" at={0} volume={0.3} />
				</Sequence>
			))}
			{frame >= all && (
				<div style={{display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: `${8 * u}px ${34 * u}px`, width: 1400 * u}}>
					{MORE.map((word, i) => (
						<Words key={word} text={word} size={60} weight={500} color={i % 3 === 1 ? C.blue : C.text} delay={all + i} stagger={0} config={SPRING.content} />
					))}
				</div>
			)}
		</Scene>
	);
};
