import {Eyes, Scene, Words} from '../kinetic';
import {SPRING, useIn, useUnit} from '../theme';

// 6.5–9s: the name, with the eyes above it.
export const Meet = () => {
	const u = useUnit();
	const eyes = useIn(0, SPRING.open);
	return (
		<Scene>
			<Eyes mood="idle" width={420 * u} blinks={[95]} style={{scale: String(0.6 + 0.4 * eyes), opacity: eyes, marginBottom: 10 * u}} />
			<Words text="Meet Blink." delay={10} size={210} stagger={8} />
		</Scene>
	);
};
