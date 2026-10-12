import {Sequence, useCurrentFrame} from 'remotion';
import {Scene, Words} from '../kinetic';
import {C, SPRING, useUnit} from '../theme';

// 22.5–25.5s: everything else, one word per half-beat, then all of it at once.
const MORE = [
	{word: 'Reminders', color: C.mint},
	{word: 'Habits', color: C.text},
	{word: 'Streaks', color: C.yellow},
	{word: 'Focus timer', color: C.text},
	{word: 'Clipboard', color: C.cyan},
	{word: 'Calendar', color: C.text},
	{word: 'Post insights', color: C.purple},
	{word: 'Spaces', color: C.text},
	{word: 'Ask Claude anything', color: C.indigo},
];
const EACH = 14;

export const Burst = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const all = MORE.length * EACH;
	return (
		<Scene>
			{MORE.map((m, i) => (
				<Sequence key={m.word} from={i * EACH} durationInFrames={EACH} layout="none">
					<Words text={m.word} size={190} stagger={1} color={m.color} config={SPRING.snap} />
				</Sequence>
			))}
			{frame >= all && (
				<div style={{display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: `${10 * u}px ${36 * u}px`, width: 1500 * u}}>
					{MORE.map((m, i) => (
						<Words key={m.word} text={m.word} size={64} weight={600} color={m.color} delay={all + i} stagger={0} />
					))}
				</div>
			)}
		</Scene>
	);
};
