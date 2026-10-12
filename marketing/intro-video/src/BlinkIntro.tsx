import {Audio} from '@remotion/media';
import {TransitionSeries} from '@remotion/transitions';
import {interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
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

// 60 s at 60 fps = 3600 frames = 100 beats of the 100 BPM track. Every scene is a whole number of beats (36 frames).
// Music: public/music/product-launch.mp3 (git-ignored; see THIRD_PARTY_NOTICES.md). Its first beat is at 0.302 s.
// The track breaks down at 31.5 s and drops at 36.3 s (here: the clipboard title, then ⌃⌥V), and ends on a big hit at
// 115.5 s, so the film plays its first 52.8 s, then jumps a whole number of bars to 110.7 s, putting that hit on the
// end card (57.6 s).
const MUSIC_START = 0.302;
const JUMP_AT = 3168; // 52.8 s, on a bar line
const ENDING_FROM = 110.702; // the track's bar 46

export const BlinkIntro = () => {
	const {fps} = useVideoConfig();
	const frame = useCurrentFrame();
	const fade = (from: number, to: number, a: number, b: number) => interpolate(frame, [from, to], [a, b], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	return (
		<>
			<Audio name="Music" src={staticFile('music/product-launch.mp3')} trimBefore={Math.round(MUSIC_START * fps)} durationInFrames={JUMP_AT + 6} volume={0.75 * fade(JUMP_AT - 6, JUMP_AT + 6, 1, 0)} />
			<Audio name="Music ending" src={staticFile('music/product-launch.mp3')} from={JUMP_AT - 6} trimBefore={Math.round(ENDING_FROM * fps) - 6} volume={0.75 * fade(JUMP_AT - 6, JUMP_AT + 6, 0, 1) * fade(3540, 3600, 1, 0)} premountFor={fps} />
			<TransitionSeries>
				<TransitionSeries.Sequence name="Notch wakes" durationInFrames={144} premountFor={fps}>
					<NotchWake />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Hook" durationInFrames={288} premountFor={fps}>
					<Hook />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Meet Blink" durationInFrames={144} premountFor={fps}>
					<Meet />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Tagline" durationInFrames={144} premountFor={fps}>
					<Tagline />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Ask" durationInFrames={288} premountFor={fps}>
					<Ask />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Mail" durationInFrames={288} premountFor={fps}>
					<Mail />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Send" durationInFrames={288} premountFor={fps}>
					<Send />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Search" durationInFrames={288} premountFor={fps}>
					<Search />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Clipboard" durationInFrames={612} premountFor={fps}>
					<Clipboard />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Day" durationInFrames={144} premountFor={fps}>
					<Day />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Money" durationInFrames={252} premountFor={fps}>
					<Money />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Habits" durationInFrames={180} premountFor={fps}>
					<Habits />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Ideas" durationInFrames={144} premountFor={fps}>
					<Ideas />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Much more" durationInFrames={144} premountFor={fps}>
					<Burst />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="Private" durationInFrames={108} premountFor={fps}>
					<Private />
				</TransitionSeries.Sequence>
				<TransitionSeries.Sequence name="End card" durationInFrames={144} premountFor={fps}>
					<End />
				</TransitionSeries.Sequence>
			</TransitionSeries>
		</>
	);
};
