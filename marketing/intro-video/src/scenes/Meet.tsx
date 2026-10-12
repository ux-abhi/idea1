import {Eyes, Scene, Sfx, Words} from '../kinetic';
import {useIn, useUnit} from '../theme';

// 7–9.5s: the name, with the eyes above it.
export const Meet = () => {
	const u = useUnit();
	const eyes = useIn(0);
	return (
		<Scene>
			<Eyes width={200 * u} blinks={[100]} style={{scale: String(0.8 + 0.2 * eyes), opacity: eyes, marginBottom: 24 * u}} />
			<Words text="Meet Blink." delay={8} size={180} stagger={6} />
			<Sfx name="whoosh" at={0} volume={0.35} />
		</Scene>
	);
};
