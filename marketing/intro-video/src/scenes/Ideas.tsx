import {Eyes, Scene, Tile, Words} from '../kinetic';
import {C, fontFamily, SPRING, useIn, useUnit} from '../theme';

const IDEAS = ['3 tools I use every day', 'Building an app in a week', 'Student budget, honestly'];

// 20–22.5s: idea cards fan out; the notch says it's done without opening anything.
export const Ideas = () => {
	const u = useUnit();
	const notch = useIn(80, SPRING.open);
	return (
		<Scene>
			<div
				style={{
					position: 'absolute',
					top: 0,
					height: 120 * u,
					width: 560 * u,
					background: C.notch,
					borderRadius: `0 0 ${34 * u}px ${34 * u}px`,
					border: `${2 * u}px solid ${C.tileEdge}`,
					borderTop: 'none',
					display: 'flex',
					alignItems: 'center',
					justifyContent: 'center',
					gap: 20 * u,
					translate: `0 ${(notch - 1) * 130 * u}px`,
					fontFamily,
					fontSize: 34 * u,
					fontWeight: 600,
					color: C.green,
				}}
			>
				<Eyes mood="done" width={150 * u} />
				5 ideas ready
			</div>
			<Words text="Writes your ideas." size={140} />
			<div style={{display: 'flex', gap: 24 * u, marginTop: 70 * u}}>
				{IDEAS.map((idea, i) => (
					<Fan key={idea} i={i} idea={idea} />
				))}
			</div>
		</Scene>
	);
};

const Fan: React.FC<{i: number; idea: string}> = ({i, idea}) => {
	const u = useUnit();
	const p = useIn(16 + i * 6, SPRING.cardIn);
	return (
		<Tile delay={16 + i * 6} style={{width: 340 * u, height: 220 * u, rotate: `${(i - 1) * 6 * p}deg`, display: 'flex', flexDirection: 'column', justifyContent: 'space-between'}}>
			<div style={{fontSize: 22 * u, color: [C.purple, C.mint, C.orange][i], fontWeight: 600}}>{['Reel', 'Carousel', 'Post'][i]}</div>
			<div style={{fontSize: 36 * u, fontWeight: 600, lineHeight: 1.15}}>{idea}</div>
		</Tile>
	);
};
