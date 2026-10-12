import {Audio} from '@remotion/media';
import {TransitionSeries} from '@remotion/transitions';
import {staticFile, useVideoConfig} from 'remotion';
import {Ask} from './scenes/Ask';
import {Burst} from './scenes/Burst';
import {Clipboard} from './scenes/Clipboard';
import {Day} from './scenes/Day';
import {End} from './scenes/End';
import {Habits} from './scenes/Habits';
import {Hook} from './scenes/Hook';
import {Ideas} from './scenes/Ideas';
import {Mail} from './scenes/Mail';
import {Meet} from './scenes/Meet';
import {Money} from './scenes/Money';
import {NotchWake} from './scenes/NotchWake';
import {Private} from './scenes/Private';
import {Search} from './scenes/Search';
import {Send} from './scenes/Send';
import {Tagline} from './scenes/Tagline';

// 60 s at 60 fps = 3600 frames. Cuts land on the beat (30 frames); the music's sections follow these
// lengths (sound/make_sounds.py → SECTIONS), so change both together.
export const BlinkIntro = () => {
	const {fps} = useVideoConfig();
	return (
		<>
			<Audio src={staticFile('sfx/music.wav')} volume={0.6} />
			<TransitionSeries>
				<TransitionSeries.Sequence name="Notch wakes" durationInFrames={210} premountFor={fps}>
					<NotchWake />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Hook" durationInFrames={210} premountFor={fps}>
					<Hook />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Meet Blink" durationInFrames={150} premountFor={fps}>
					<Meet />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Tagline" durationInFrames={150} premountFor={fps}>
					<Tagline />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Ask" durationInFrames={300} premountFor={fps}>
					<Ask />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Mail" durationInFrames={300} premountFor={fps}>
					<Mail />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Send" durationInFrames={270} premountFor={fps}>
					<Send />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Clipboard" durationInFrames={450} premountFor={fps}>
					<Clipboard />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Search" durationInFrames={270} premountFor={fps}>
					<Search />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Day" durationInFrames={180} premountFor={fps}>
					<Day />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Money" durationInFrames={270} premountFor={fps}>
					<Money />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Habits" durationInFrames={210} premountFor={fps}>
					<Habits />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Ideas" durationInFrames={150} premountFor={fps}>
					<Ideas />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Much more" durationInFrames={150} premountFor={fps}>
					<Burst />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Private" durationInFrames={150} premountFor={fps}>
					<Private />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="End card" durationInFrames={180} premountFor={fps}>
					<End />
				</TransitionSeries.Sequence>
			</TransitionSeries>
		</>
	);
};
