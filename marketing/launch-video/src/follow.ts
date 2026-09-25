// Critically damped spring that follows a (possibly step-wise) target over time.
// Simulated from frame 0 and memoised, so any frame can be rendered in any order
// and still get the same smooth, continuous value.
const cache = new Map<string, {x: number[]; v: number[]}>();

export function springFollow(key: string, frame: number, target: (f: number) => number, omega = 0.1): number {
  const f = Math.max(0, Math.floor(frame));
  let s = cache.get(key);
  if (!s) {
    s = {x: [target(0)], v: [0]};
    cache.set(key, s);
  }
  for (let i = s.x.length; i <= f; i++) {
    const x = s.x[i - 1], v = s.v[i - 1];
    const a = omega * omega * (target(i) - x) - 2 * omega * v;
    s.v.push(v + a);
    s.x.push(x + v + a);
  }
  return s.x[f];
}
