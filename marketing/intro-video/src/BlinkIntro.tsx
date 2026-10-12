import {TransitionSeries} from '@remotion/transitions';
import {useVideoConfig} from 'remotion';
import {Burst} from './scenes/Burst';
import {Day} from './scenes/Day';
import {End} from './scenes/End';
import {Hook} from './scenes/Hook';
import {Ideas} from './scenes/Ideas';
import {Mail} from './scenes/Mail';
import {Meet} from './scenes/Meet';
import {Money} from './scenes/Money';
import {NotchWake} from './scenes/NotchWake';
import {Private} from './scenes/Private';
import {Send} from './scenes/Send';

// 30 s at 60 fps = 1800 frames. Hard cuts on the beat (30 frames); every scene settles out on its own.
export const BlinkIntro = () => {
	const {fps} = useVideoConfig();
	return (
		<TransitionSeries>
			<TransitionSeries.Sequence name="Notch wakes" durationInFrames={180} premountFor={fps}>
				<NotchWake />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Hook" durationInFrames={210} premountFor={fps}>
				<Hook />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Meet Blink" durationInFrames={150} premountFor={fps}>
				<Meet />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Mail" durationInFrames={180} premountFor={fps}>
				<Mail />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Send" durationInFrames={180} premountFor={fps}>
				<Send />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Day" durationInFrames={150} premountFor={fps}>
				<Day />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Money" durationInFrames={150} premountFor={fps}>
				<Money />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Ideas" durationInFrames={150} premountFor={fps}>
				<Ideas />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Much more" durationInFrames={180} premountFor={fps}>
				<Burst />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="Private" durationInFrames={150} premountFor={fps}>
				<Private />
			</TransitionSeries.Sequence>
			<TransitionSeries.Sequence name="End card" durationInFrames={120} premountFor={fps}>
				<End />
			</TransitionSeries.Sequence>
		</TransitionSeries>
	);
};
