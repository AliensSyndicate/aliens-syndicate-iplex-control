import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";

// Reference: assets/images/app.png (1254x1254). Text box measured on it.
const S = 0.514; // logo.png (launcher.png) scale so it overlays the engraved text exactly
const LEFT = 309.7;
const TOP = 287.6;
const SIZE = 1254 * S;
const ORIGIN_X = 633 - LEFT;
const ORIGIN_Y = 624.5 - TOP;

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

export const SplashAnimation: React.FC = () => {
  const frame = useCurrentFrame();

  // 1) text hidden (flat paper) -> 2) pops forward -> 3) holds -> 4) goes back, ending engraved (the reference image)
  const forward = interpolate(frame, [30, 56], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const back = interpolate(frame, [86, 124], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });

  const lift = forward * (1 - back); // 0 flat .. 1 fully forward
  const scale = 0.97 + 0.11 * lift;
  const shadow = 34 * lift;

  return (
    <AbsoluteFill style={{ backgroundColor: "#202020" }}>
      <Img src={staticFile("hidden.png")} style={{ position: "absolute", inset: 0, width: 1254, height: 1254 }} />
      {/* engraved final state, revealed at the end */}
      <Img src={staticFile("final.png")} style={{ position: "absolute", inset: 0, width: 1254, height: 1254, opacity: back }} />
      <Img
        src={staticFile("logo.png")}
        style={{
          position: "absolute",
          left: LEFT,
          top: TOP,
          width: SIZE,
          height: SIZE,
          opacity: Math.min(1, lift * 1.6),
          transformOrigin: `${ORIGIN_X}px ${ORIGIN_Y}px`,
          transform: `scale(${scale})`,
          filter: `drop-shadow(0 ${shadow * 0.6}px ${shadow}px rgba(0,0,0,0.75))`,
        }}
      />
    </AbsoluteFill>
  );
};
