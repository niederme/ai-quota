import {describe, expect, it} from 'vitest';
import {AGENT_VIEW, agentAt, PROMPT} from './agent';
import {BEATS, DURATION} from './timeline';

describe('agentAt', () => {
  it('types the prompt into the composer before sending', () => {
    const a = agentAt(BEATS.promptSent - 20);
    expect(a.composer.length).toBeGreaterThan(0);
    expect(a.composer.length).toBeLessThan(PROMPT.length);
    expect(a.items).toHaveLength(0);
  });
  it('moves the prompt into the transcript once sent', () => {
    const a = agentAt(BEATS.promptSent + 2);
    expect(a.composer).toBe('');
    expect(a.items[0].kind).toBe('prompt');
  });
  it('keeps the newest line inside the viewport', () => {
    for (let f = BEATS.promptSent; f < DURATION; f += 7) {
      const a = agentAt(f);
      expect(a.scroll).toBeGreaterThanOrEqual(0);
      expect(a.focusY - a.scroll).toBeLessThanOrEqual(AGENT_VIEW.h);
      expect(a.focusY - a.scroll).toBeGreaterThanOrEqual(0);
    }
  });
  it('is still streaming when the camera zooms out', () => {
    expect(agentAt(BEATS.zoomOut).streaming).toBe(true);
  });
});
