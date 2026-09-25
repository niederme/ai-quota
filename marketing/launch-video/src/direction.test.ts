import {describe, expect, it} from 'vitest';
import {cameraFor} from './direction';
import {BEATS, DURATION} from './timeline';

// Deliberate whip zooms may move fast; everything else must stay gentle.
const WHIPS = [[BEATS.zoomOut, BEATS.zoomOut + 64], [BEATS.reset - 6, BEATS.reset + 38]];
const inWhip = (f: number) => WHIPS.some(([a, b]) => f >= a && f <= b);

// Screen-space acceleration of the camera, in 1080p pixels per frame².
// A sudden change in camera velocity reads as a jerk or glitch on screen.
function jerks() {
  const cams = Array.from({length: DURATION}, (_, f) => cameraFor(f));
  const out: {frame: number; acc: number}[] = [];
  for (let f = 2; f < DURATION; f++) {
    const [a, b, c] = [cams[f - 2], cams[f - 1], cams[f]];
    const ax = (c.x - 2 * b.x + a.x) * c.z;
    const ay = (c.y - 2 * b.y + a.y) * c.z;
    const az = (Math.log(c.z) - 2 * Math.log(b.z) + Math.log(a.z)) * 960; // zoom about screen centre
    out.push({frame: f, acc: Math.hypot(ax, ay, az)});
  }
  return out;
}

describe('camera motion', () => {
  it('has no sudden velocity changes outside the whip zooms', () => {
    const worst = jerks().filter((j) => !inWhip(j.frame)).sort((a, b) => b.acc - a.acc).slice(0, 5);
    expect(worst[0].acc, JSON.stringify(worst)).toBeLessThan(3);
  });
  it('keeps whip zooms fast but bounded', () => {
    const worst = jerks().filter((j) => inWhip(j.frame)).sort((a, b) => b.acc - a.acc)[0];
    expect(worst.acc, JSON.stringify(worst)).toBeLessThan(8);
  });
});
