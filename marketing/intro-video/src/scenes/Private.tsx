import {Icon, Scene, Sfx, Sub, Words} from '../kinetic';
import {BEAT, C, useIn, useUnit} from '../theme';

// 54.5–57s: the trust promise.
export const Private = () => {
	const u = useUnit();
	const lock = useIn(0);
	return (
		<Scene>
			<div style={{opacity: lock, marginBottom: 24 * u}}>
				<Icon name="lock" size={90 * u} color={C.blue} />
			</div>
			<Words text="Your server. Your keys." size={110} />
			<Sub text="Nothing is sent without your OK." delay={2 * BEAT} />
			<Sfx name="clunk" at={4} volume={0.7} />
			<Sfx name="swoosh" at={2 * BEAT} volume={0.35} />
		</Scene>
	);
};
