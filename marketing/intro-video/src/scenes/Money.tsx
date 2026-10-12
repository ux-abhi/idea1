import {Easing, interpolate, useCurrentFrame} from 'remotion';
import {Scene, Tile, Words} from '../kinetic';
import {C, fontFamily, useIn, useUnit, useVertical} from '../theme';

const LINE = [0, 12, 18, 30, 34, 47, 52, 60, 71, 75, 84, 90];

// 17.5–20s: the balance rolls up, spending draws in, categories pop.
export const Money = () => {
	const u = useUnit();
	const vertical = useVertical();
	const frame = useCurrentFrame();
	const t = interpolate(frame, [10, 70], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic)});
	const amount = (2480.5 * t).toLocaleString('de-DE', {minimumFractionDigits: 2, maximumFractionDigits: 2});
	const w = 520;
	const h = 140;
	const d = LINE.map((v, i) => `${i ? 'L' : 'M'}${(i / (LINE.length - 1)) * w} ${h - (v / 100) * h}`).join(' ');
	return (
		<Scene>
			<Words text="Tracks your money." size={140} />
			<div style={{display: 'flex', flexDirection: vertical ? 'column' : 'row', alignItems: 'center', gap: 60 * u, marginTop: 60 * u}}>
				<div style={{fontFamily, textAlign: vertical ? 'center' : 'right'}}>
					<div style={{fontSize: 120 * u, fontWeight: 800, letterSpacing: '-0.04em', fontVariantNumeric: 'tabular-nums', color: C.text}}>€{amount}</div>
					<div style={{fontSize: 30 * u, color: C.dim}}>left this month · on track</div>
				</div>
				<svg width={w * u} height={h * u} viewBox={`0 0 ${w} ${h}`} style={{overflow: 'visible'}}>
					<path d={d} fill="none" stroke={C.green} strokeWidth={6} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - t} />
				</svg>
			</div>
			<div style={{display: 'flex', gap: 16 * u, marginTop: 40 * u}}>
				<Chip delay={40} color={C.pink} label="Food €312" />
				<Chip delay={46} color={C.cyan} label="Transport €58" />
				<Chip delay={52} color={C.brown} label="Home €640" />
			</div>
		</Scene>
	);
};

const Chip: React.FC<{delay: number; color: string; label: string}> = ({delay, color, label}) => {
	const u = useUnit();
	const p = useIn(delay);
	return (
		<Tile delay={delay} style={{display: 'flex', alignItems: 'center', gap: 12 * u, fontSize: 30 * u, padding: `${14 * u}px ${24 * u}px`, borderRadius: 999}}>
			<span style={{width: 16 * u, height: 16 * u, borderRadius: 99, background: color, scale: String(p)}} />
			{label}
		</Tile>
	);
};
