import {Scene, Sub, Words} from '../kinetic';
import {C} from '../theme';

// 9.5–12s: what it is, in one line.
export const Tagline = () => (
	<Scene>
		<Words text="A personal assistant" size={110} />
		<Words text="that lives in your notch." size={110} delay={10} accent={{'notch.': C.blue}} />
		<Sub text="Powered by Claude." delay={40} />
	</Scene>
);
