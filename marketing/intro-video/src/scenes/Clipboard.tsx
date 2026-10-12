import {interpolate, useCurrentFrame} from 'remotion';
import {Caption, Eyes, Icon, Keys, Notch, Scene, Screen, Sfx, Sub, TitleOut, Typed, Words} from '../kinetic';
import {C, fontFamily, SPRING, useIn, useUnit} from '../theme';

const CLIPS = [
	{icon: 'doc', title: 'Q4 plan: launch on the 20th, beta first', meta: 'Text · Notes', match: false},
	{icon: 'link', title: 'example.com/invoice/2026-10', meta: 'Link · Safari', match: true},
	{icon: 'photo', title: 'Screenshot of the new onboarding', meta: 'Image · 2 min ago', match: false},
	{icon: 'file', title: 'Invoice_October.pdf', meta: 'File · Finder', match: true},
	{icon: 'doc', title: 'Booking ref KX7-224, gate B12', meta: 'Text · Mail', match: false},
] as const;

// 31.2–41.4s: the title rides the music's breakdown; ⌃⌥V lands on the drop (frame 288). Everything you copy, kept in the notch: search it, drag it anywhere, and it never leaves the Mac.
export const Clipboard = () => {
	const u = useUnit();
	const frame = useCurrentFrame();
	const open = useIn(294, SPRING.open);
	const filter = interpolate(frame, [408, 430], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	const drag = useIn(468, SPRING.smooth);
	return (
		<Scene>
			<TitleOut at={248}>
				<Words text="Everything you copy." />
				<Sub text="Kept safe in your notch." delay={144} />
			</TitleOut>
			{frame >= 258 && (
				<>
					<Screen delay={258} />
					<Keys keys={['⌃', '⌥', 'V']} delay={260} press={288} style={{position: 'absolute', bottom: 150 * u, opacity: interpolate(frame, [264, 278, 308, 324], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}} />
					<Notch open={open} width={820} height={560 - 264 * filter - 88 * drag}>
						<div style={{display: 'flex', alignItems: 'center', gap: 14 * u}}>
							<Eyes width={70 * u} />
							<div style={{flex: 1, display: 'flex', alignItems: 'center', gap: 12 * u, background: C.tile, borderRadius: 14 * u, padding: `${12 * u}px ${16 * u}px`, fontSize: 28 * u}}>
								<Icon name="search" size={28 * u} color={C.gray} />
								{frame < 378 ? <span style={{color: C.gray}}>Search clipboard</span> : <Typed text="invoice" from={378} every={4} caret={frame < 468} />}
							</div>
						</div>
						<div style={{marginTop: 14 * u}}>
							{CLIPS.map((c, i) => (
								<ClipRow key={c.title} {...c} i={i} hidden={!c.match ? filter : c.title === 'Invoice_October.pdf' && drag > 0.02 ? 1 : 0} />
							))}
						</div>
					</Notch>
					{/* The dragged file, lifted out of the notch (the panel clips its own rows). */}
					<div style={{position: 'absolute', top: 222 * u, left: '50%', translate: `${-382 * u + drag * 560 * u}px ${drag * 260 * u}px`, rotate: `${drag * 5}deg`, opacity: drag > 0.02 ? 1 : 0, fontFamily, color: C.text}}>
						<ClipRow icon="file" title="Invoice_October.pdf" meta="File · Finder" i={0} hidden={0} lifted />
					</div>
					<Caption text="Search it." from={408} to={468} />
					<Caption text="Drag it anywhere." from={468} to={548} />
					<Caption text="Never leaves your Mac." from={548} to={612} accent={{'Mac.': C.blue}} />
					<Sfx name="swoosh" at={0} volume={0.5} />
					<Sfx name="tap" at={288} volume={0.4} />
					<Sfx name="open" at={290} volume={0.5} />
					{[0, 1, 2, 3, 4].map((i) => (
						<Sfx key={i} name="pop" at={318 + i * 5} volume={0.35} />
					))}
					<Sfx name="swoosh" at={408} volume={0.4} />
					<Sfx name="whoosh" at={468} volume={0.4} />
					<Sfx name="drop" at={513} volume={0.7} />
					<Sfx name="sparkle" at={548} volume={0.4} />
				</>
			)}
		</Scene>
	);
};

const ClipRow: React.FC<{icon: 'doc' | 'link' | 'photo' | 'file'; title: string; meta: string; i: number; hidden: number; lifted?: boolean}> = ({icon, title, meta, i, hidden, lifted = false}) => {
	const u = useUnit();
	const p = useIn(318 + i * 5, SPRING.content);
	return (
		<div
			style={{
				display: 'flex',
				alignItems: 'center',
				gap: 18 * u,
				height: (1 - hidden) * 88 * u,
				opacity: lifted ? 1 : Math.min(p, 1 - hidden),
				translate: lifted ? undefined : `0 ${(1 - p) * 20 * u}px`,
			}}
		>
			<div
				style={{
					width: 60 * u,
					height: 60 * u,
					borderRadius: 14 * u,
					background: icon === 'photo' ? `linear-gradient(135deg, ${C.blue}, #003A80)` : C.tile,
					display: 'flex',
					alignItems: 'center',
					justifyContent: 'center',
					boxShadow: lifted ? `0 ${20 * u}px ${40 * u}px rgba(0,0,0,0.6)` : undefined,
				}}
			>
				<Icon name={icon} size={32 * u} color={icon === 'photo' ? C.text : C.blue} />
			</div>
			<div>
				<div style={{fontSize: 28 * u, fontWeight: 500}}>{title}</div>
				<div style={{fontSize: 22 * u, color: C.gray}}>{meta}</div>
			</div>
		</div>
	);
};
