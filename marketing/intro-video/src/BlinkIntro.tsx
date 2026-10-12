import {Audio} from '@remotion/media';
import {TransitionSeries} from '@remotion/transitions';
import {staticFile, useVideoConfig} from 'remotion';
import {Ask} from './scenes/Ask';
import {Burst} from './scenes/Burst';
import {Clipboard} from './scenes/Clipboard';
import {Day} from './scenes/Day';
import {End} from './scenes/End';
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
			<Audio src={staticFile('sfx/music.wav')} volume={0.7} />
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
				<TransitionSeries.Sequence name="Ask" durationInFrames={360} premountFor={fps}>
					<Ask />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Mail" durationInFrames={360} premountFor={fps}>
					<Mail />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Send" durationInFrames={300} premountFor={fps}>
					<Send />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Clipboard" durationInFrames={480} premountFor={fps}>
					<Clipboard />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Search" durationInFrames={300} premountFor={fps}>
					<Search />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Day" durationInFrames={180} premountFor={fps}>
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
				<TransitionSeries.Sequence name="Private" durationInFrames={180} premountFor={fps}>
					<Private />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="End card" durationInFrames={240} premountFor={fps}>
					<End />
				</TransitionSeries.Sequence>
			</TransitionSeries>
		</>
	);
};
