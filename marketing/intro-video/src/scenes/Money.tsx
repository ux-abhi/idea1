import {Easing, interpolate, useCurrentFrame} from 'remotion';
import {Scene, Sfx, Tile, Words} from '../kinetic';
import {C, fontFamily, useUnit, useVertical} from '../theme';

const LINE = [0, 12, 18, 30, 34, 47, 52, 60, 71, 75, 84, 90];

// 45–47.5s: the balance rolls up and spending draws in.
export const Money = () => {
	const u = useUnit();
	const vertical = useVertical();
	const frame = useCurrentFrame();
	const t = interpolate(frame, [10, 70], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.out(Easing.cubic)});
	const amount = (2480.5 * t).toLocaleString('de-DE', {minimumFractionDigits: 2, maximumFractionDigits: 2});
	const w = 480;
	const h = 130;
	const d = LINE.map((v, i) => `${i ? 'L' : 'M'}${(i / (LINE.length - 1)) * w} ${h - (v / 100) * h}`).join(' ');
	return (
		<Scene>
			<Words text="Tracks your money." size={120} />
			<div style={{display: 'flex', flexDirection: vertical ? 'column' : 'row', alignItems: 'center', gap: 60 * u, marginTop: 50 * u}}>
				<div style={{fontFamily, textAlign: vertical ? 'center' : 'right'}}>
					<div style={{fontSize: 110 * u, fontWeight: 600, letterSpacing: '-0.04em', fontVariantNumeric: 'tabular-nums', color: C.text}}>€{amount}</div>
					<div style={{fontSize: 28 * u, color: C.gray}}>left this month · on track</div>
				</div>
				<svg width={w * u} height={h * u} viewBox={`0 0 ${w} ${h}`} style={{overflow: 'visible'}}>
					<path d={d} fill="none" stroke={C.blue} strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - t} />
				</svg>
			</div>
			<div style={{display: 'flex', gap: 14 * u, marginTop: 36 * u}}>
				{['Food €312', 'Transport €58', 'Home €640'].map((label, i) => (
					<Tile key={label} delay={40 + i * 6} style={{fontSize: 28 * u, padding: `${12 * u}px ${22 * u}px`, borderRadius: 999}}>
						{label}
					</Tile>
				))}
			</div>
			<Sfx name="tick" at={10} volume={0.35} />
		</Scene>
	);
};
