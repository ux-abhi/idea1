import {Eyes, Scene, Words} from '../kinetic';
import {BEAT, C, useIn, useUnit} from '../theme';

// 25.5–28s: the trust promise, stacked like a lock closing.
export const Private = () => {
	const u = useUnit();
	const eyes = useIn(0);
	return (
		<Scene>
			<Eyes mood="thinking" width={220 * u} style={{opacity: eyes, marginBottom: 20 * u}} />
			<Words text="Your server." size={120} />
			<Words text="Your keys." size={120} delay={BEAT} />
			<Words text="Nothing leaves without your OK." size={72} weight={600} delay={2 * BEAT} stagger={3} accent={{OK: C.green, 'OK.': C.green}} style={{marginTop: 20 * u}} />
		</Scene>
	);
};
