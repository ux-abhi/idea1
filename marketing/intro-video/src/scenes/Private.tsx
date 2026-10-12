import {Icon, Scene, Sub, Words} from '../kinetic';
import {BEAT, C, useIn, useUnit} from '../theme';

// 53–56s: the trust promise.
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
		</Scene>
	);
};
