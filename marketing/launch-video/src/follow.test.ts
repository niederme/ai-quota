import {describe, expect, it} from 'vitest';
import {springFollow} from './follow';

describe('springFollow', () => {
  const step = (f: number) => (f < 10 ? 0 : 100);
  it('starts on the target and eases toward a step without overshoot', () => {
    expect(springFollow('a', 0, step)).toBe(0);
    let prev = 0;
    for (let f = 1; f < 200; f++) {
      const x = springFollow('a', f, step);
      expect(x).toBeGreaterThanOrEqual(prev - 1e-9);
      expect(x).toBeLessThanOrEqual(100 + 1e-6);
      prev = x;
    }
    expect(prev).toBeGreaterThan(99);
  });
  it('never changes velocity abruptly', () => {
    const xs = Array.from({length: 120}, (_, f) => springFollow('b', f, step));
    for (let f = 2; f < xs.length; f++) {
      expect(Math.abs(xs[f] - 2 * xs[f - 1] + xs[f - 2])).toBeLessThan(1.5);
    }
  });
  it('is order independent', () => {
    const late = springFollow('c', 80, step);
    expect(springFollow('d', 80, step)).toBeCloseTo(late);
  });
});
