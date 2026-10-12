import {Icon, Scene, Sfx, Sub, Words} from '../kinetic';
import {BEAT, C, useIn, useUnit} from '../theme';

// 55.8–57.6s: the trust promise.
export const Private = () => {
	const u = useUnit();
	const lock = useIn(0);
	return (
		<Scene>
			<div style={{opacity: lock, marginBottom: 24 * u}}>
				<Icon name="lock" size={90 * u} color={C.green} />
			</div>
			<Words text="Your server. Your keys." size={110} />
			<Sub text="Nothing is sent without your OK." delay={BEAT} />
			<Sfx name="clunk" at={4} volume={0.7} />
			<Sfx name="swoosh" at={BEAT} volume={0.35} />
		</Scene>
	);
};
