import {describe, expect, it} from 'vitest';
import {agentAt, MAC_SESSION, PHONE_SESSION, sessionTokens, smoothScroll, type Session} from './agent';
import {BEATS, DURATION} from './timeline';

const firstPrompt = (s: Session) => s.script.find((i) => i.kind === 'prompt')!;

describe.each([
  ['mac', MAC_SESSION],
  ['phone', PHONE_SESSION],
])('agentAt (%s)', (_name, session) => {
  const p = firstPrompt(session);

  it('types the first prompt into the composer before sending', () => {
    const a = agentAt(session, p.at - 10);
    expect(a.composer.length).toBeGreaterThan(0);
    expect(a.items).toHaveLength(0);
  });

  it('moves the prompt into the transcript once sent', () => {
    const a = agentAt(session, p.at + 1);
    expect(a.composer).toBe('');
    expect(a.items[0].kind).toBe('prompt');
  });

  it('keeps the newest line inside the viewport', () => {
    for (let f = p.at; f < DURATION; f += 7) {
      const a = agentAt(session, f);
      expect(a.scroll).toBeGreaterThanOrEqual(0);
      expect(a.focusY - a.scroll).toBeLessThanOrEqual(session.view.h);
      expect(a.focusY - a.scroll).toBeGreaterThanOrEqual(0);
    }
  });

  it('fans out to sub-agents', () => {
    const block = session.script.find((i) => i.kind === 'agents')!;
    expect(agentAt(session, block.at + 20).items.some((i) => i.kind === 'agents')).toBe(true);
  });
});

describe('mac session', () => {
  const session = MAC_SESSION;
  it('has a back-and-forth: a second prompt after replies', () => {
    const prompts = session.script.filter((i) => i.kind === 'prompt');
    expect(prompts.length).toBeGreaterThanOrEqual(2);
    const a = agentAt(session, prompts[1].at + 1);
    expect(a.items.filter((i) => i.kind === 'prompt')).toHaveLength(2);
    expect(a.items.some((i) => i.kind === 'agents')).toBe(true);
  });
});

describe('session timing', () => {
  it('mac is still streaming when the camera zooms out', () => {
    expect(agentAt(MAC_SESSION, BEATS.zoomOut).streaming).toBe(true);
  });
  it('mac follow-up lands on its beat', () => {
    expect(MAC_SESSION.script.filter((i) => i.kind === 'prompt')[1].at).toBe(BEATS.followUp);
  });
  it('phone prompt is sent on its beat', () => {
    expect(firstPrompt(PHONE_SESSION).at).toBe(BEATS.phonePrompt);
  });
});

describe('sub-agents', () => {
  it('run in parallel with rising token counts, then finish', () => {
    const block = MAC_SESSION.script.find((i) => i.kind === 'agents')!;
    if (block.kind !== 'agents') throw new Error();
    const early = agentAt(MAC_SESSION, block.at + 20).items.find((i) => i.kind === 'agents');
    const later = agentAt(MAC_SESSION, block.at + 80).items.find((i) => i.kind === 'agents');
    if (early?.kind !== 'agents' || later?.kind !== 'agents') throw new Error('missing agents block');
    expect(early.rows.filter((r) => !r.done).length).toBeGreaterThan(1);
    early.rows.forEach((r, i) => expect(later.rows[i].tokens).toBeGreaterThanOrEqual(r.tokens));
    const done = agentAt(MAC_SESSION, Math.max(...block.agents.map((g) => g.doneAt)) + 1).items.find((i) => i.kind === 'agents');
    if (done?.kind !== 'agents') throw new Error();
    expect(done.rows.every((r) => r.done)).toBe(true);
  });
  it('plan steps tick off over time', () => {
    const block = MAC_SESSION.script.find((i) => i.kind === 'plan')!;
    if (block.kind !== 'plan') throw new Error();
    const at = (f: number) => agentAt(MAC_SESSION, f).items.find((i) => i.kind === 'plan');
    const a = at(block.at + 1), b = at(Math.max(...block.doneAt) + 1);
    if (a?.kind !== 'plan' || b?.kind !== 'plan') throw new Error();
    expect(a.done.filter(Boolean).length).toBe(0);
    expect(b.done.every(Boolean)).toBe(true);
  });
});

describe('sessionTokens', () => {
  it.each([['mac', MAC_SESSION], ['phone', PHONE_SESSION]] as const)('%s never decreases and gets large', (_n, s) => {
    let prev = 0;
    for (let f = 0; f < DURATION; f++) {
      const t = sessionTokens(s, f);
      expect(t).toBeGreaterThanOrEqual(prev);
      prev = t;
    }
    expect(prev).toBeGreaterThan(150000);
  });
});

describe('transcript motion', () => {
  it.each([['mac', MAC_SESSION], ['phone', PHONE_SESSION]] as const)('%s scroll glides without jolts', (_n, s) => {
    const ys = Array.from({length: DURATION}, (_, f) => smoothScroll(s, f));
    for (let f = 2; f < DURATION; f++) expect(Math.abs(ys[f] - 2 * ys[f - 1] + ys[f - 2]), `frame ${f}`).toBeLessThan(1.5);
  });
  it('stamps every item and agent row with the frame it appeared', () => {
    const a = agentAt(MAC_SESSION, BEATS.followUp + 100);
    for (const item of a.items) {
      expect(item.at).toBeLessThanOrEqual(BEATS.followUp + 100);
      if (item.kind === 'agents') item.rows.slice(0, item.reveal).forEach((r) => expect(r.at).toBeLessThanOrEqual(BEATS.followUp + 100));
    }
  });
  it('holds on the empty composer for a beat, then starts typing', () => {
    for (let f = 0; f < BEATS.hold; f++) expect(agentAt(MAC_SESSION, f).composer).toBe('');
    expect(agentAt(MAC_SESSION, BEATS.hold + 6).composer.length).toBeGreaterThan(0);
  });
});
