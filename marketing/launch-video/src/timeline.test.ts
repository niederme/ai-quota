import {describe, expect, it} from 'vitest';
import {BEATS, DURATION, gaugeColor, tokensAt, usageAt} from './timeline';
import {theme} from './theme';

describe('gaugeColor', () => {
  it('matches app thresholds', () => {
    expect(gaugeColor(84)).toBe(theme.accent);
    expect(gaugeColor(85)).toBe(theme.warning);
    expect(gaugeColor(94.9)).toBe(theme.warning);
    expect(gaugeColor(95)).toBe(theme.critical);
  });
});

describe('usageAt', () => {
  it('is below warning when the popover first opens', () => {
    const u = usageAt(BEATS.macOpen);
    expect(Math.max(u.codex.h5, u.claude.h5)).toBeLessThan(85);
  });
  it('peaks Claude 5h into critical', () => {
    expect(usageAt(BEATS.peak).claude.h5).toBeGreaterThanOrEqual(95);
  });
  it('notifies once Claude 5h is past the 85% threshold', () => {
    expect(usageAt(BEATS.notify).claude.h5).toBeGreaterThanOrEqual(85);
  });
  it('resets Claude 5h after the peak', () => {
    expect(usageAt(BEATS.reset + 30).claude.h5).toBeLessThan(20);
  });
  it('climbs monotonically until the peak', () => {
    let prev = -1;
    for (let f = BEATS.macOpen; f <= BEATS.peak; f++) {
      const v = usageAt(f).claude.h5;
      expect(v).toBeGreaterThanOrEqual(prev);
      prev = v;
    }
  });
  it('is defined for every frame', () => {
    for (let f = 0; f < DURATION; f++) {
      const u = usageAt(f);
      for (const n of [u.codex.h5, u.codex.d7, u.claude.h5, u.claude.d7]) {
        expect(n).toBeGreaterThanOrEqual(0);
        expect(n).toBeLessThanOrEqual(100);
      }
    }
  });
});

describe('tokensAt', () => {
  it('counts up from the prompt and never decreases', () => {
    expect(tokensAt(BEATS.promptSent)).toBe(0);
    let prev = 0;
    for (let f = BEATS.promptSent; f < DURATION; f++) {
      expect(tokensAt(f)).toBeGreaterThanOrEqual(prev);
      prev = tokensAt(f);
    }
    expect(prev).toBeGreaterThan(50000);
  });
});
