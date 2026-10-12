import {Eyes, Notch, Scene, Sfx, Tile, Words} from '../kinetic';
import {C, SPRING, useIn, useUnit} from '../theme';

const IDEAS = ['3 tools I use every day', 'Building an app in a week', 'Student budget, honestly'];

// 47.5–50s: idea cards fan out; the notch says it's done without opening anything.
export const Ideas = () => {
	const u = useUnit();
	const notch = useIn(80, SPRING.open);
	return (
		<Scene>
			<Notch open={notch} width={400} height={78} top={0} edge>
				<div style={{display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 14 * u, marginTop: -6 * u, fontSize: 28 * u, fontWeight: 600, color: C.blue}}>
					<Eyes width={80 * u} />5 ideas ready
				</div>
			</Notch>
			<Words text="Writes your ideas." size={120} />
			<div style={{display: 'flex', gap: 22 * u, marginTop: 60 * u}}>
				{IDEAS.map((idea, i) => (
					<Fan key={idea} i={i} idea={idea} />
				))}
			</div>
			<Sfx name="chime" at={80} volume={0.4} />
		</Scene>
	);
};

const Fan: React.FC<{i: number; idea: string}> = ({i, idea}) => {
	const u = useUnit();
	const p = useIn(16 + i * 6, SPRING.cardIn);
	return (
		<Tile delay={16 + i * 6} style={{width: 320 * u, height: 200 * u, rotate: `${(i - 1) * 4 * p}deg`, display: 'flex', flexDirection: 'column', justifyContent: 'space-between'}}>
			<div style={{fontSize: 22 * u, color: C.blue, fontWeight: 600}}>{['Reel', 'Carousel', 'Post'][i]}</div>
			<div style={{fontSize: 32 * u, fontWeight: 600, lineHeight: 1.15}}>{idea}</div>
		</Tile>
	);
};
