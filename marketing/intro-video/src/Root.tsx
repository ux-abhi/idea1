import {Composition} from 'remotion';
import {BlinkIntro} from './BlinkIntro';

export const RemotionRoot: React.FC = () => {
	return (
		<>
			<Composition id="BlinkIntro" component={BlinkIntro} durationInFrames={1800} fps={60} width={1920} height={1080} />
			<Composition id="BlinkIntroVertical" component={BlinkIntro} durationInFrames={1800} fps={60} width={1080} height={1920} />
		</>
	);
};
