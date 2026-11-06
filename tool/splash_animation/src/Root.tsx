import { Composition } from "remotion";
import { SplashAnimation } from "./Composition";

export const RemotionRoot: React.FC = () => (
  <Composition id="SplashAnimation" component={SplashAnimation} durationInFrames={150} fps={30} width={1254} height={1254} />
);
