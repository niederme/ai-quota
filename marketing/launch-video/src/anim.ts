export type Key = [frame: number, value: number];
export type Ease = (t: number) => number;

export const smooth: Ease = (t) => t * t * (3 - 2 * t);
// Close to Apple's default ease-in-out curve.
export const easeInOut: Ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
export const easeOut: Ease = (t) => 1 - Math.pow(1 - t, 3);

export function keyframes(frame: number, keys: Key[], ease: Ease = smooth): number {
  if (frame <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [f1, v1] = keys[i];
    if (frame <= f1) {
      const [f0, v0] = keys[i - 1];
      return v0 + (v1 - v0) * ease((frame - f0) / (f1 - f0));
    }
  }
  return keys[keys.length - 1][1];
}

// 0→1 ramp between two frames.
export const ramp = (frame: number, from: number, to: number, ease: Ease = easeInOut) =>
  keyframes(frame, [[from, 0], [to, 1]], ease);
