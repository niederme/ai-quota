// A generic AI coding-agent session shown on the Mac. Pure layout model: every
// item has a deterministic height so the transcript can auto-scroll and the
// camera can follow the newest line without measuring the DOM.
import {BEATS} from './timeline';

export const PROMPT = 'Add offline sync to the notes app: queue edits locally and replay them when the connection comes back. Keep the tests green.';

export const AGENT_VIEW = {w: 700, h: 468};
export const LINE = 23;
const CODE_LINE = 20;
const GAP = 14;

type Script =
  | {kind: 'text'; at: number; lines: string[]}
  | {kind: 'tool'; at: number; verb: string; target: string; detail?: string}
  | {kind: 'code'; at: number; file: string; lines: string[]};

const SCRIPT: Script[] = [
  {kind: 'text', at: 64, lines: ['I’ll start by tracing how edits reach the server today.']},
  {kind: 'tool', at: 84, verb: 'Read', target: 'src/store/notes.ts'},
  {kind: 'tool', at: 94, verb: 'Read', target: 'src/sync/client.ts'},
  {kind: 'tool', at: 104, verb: 'Search', target: '"saveNote("', detail: '14 matches'},
  {kind: 'text', at: 118, lines: ['Every edit calls the API directly, so nothing survives a', 'dropped connection. I’ll put a persistent queue in front of it:']},
  {kind: 'code', at: 150, file: 'src/sync/queue.ts', lines: [
    'export class EditQueue {',
    '  private pending: Edit[] = load(\'edits\') ?? [];',
    '',
    '  enqueue(edit: Edit) {',
    '    this.pending.push(edit);',
    '    persist(\'edits\', this.pending);',
    '  }',
    '',
    '  async flush(client: SyncClient) {',
    '    while (this.pending.length > 0) {',
    '      await client.save(this.pending[0]);',
    '      this.pending.shift();',
    '      persist(\'edits\', this.pending);',
    '    }',
    '  }',
    '}',
  ]},
  {kind: 'tool', at: 214, verb: 'Edit', target: 'src/sync/queue.ts', detail: '+48'},
  {kind: 'tool', at: 232, verb: 'Edit', target: 'src/store/notes.ts', detail: '+12 −5'},
  {kind: 'tool', at: 252, verb: 'Run', target: 'npm test', detail: '128 passed'},
  {kind: 'text', at: 300, lines: ['Queue is in. Now wiring reconnect events so pending edits', 'flush the moment you’re back online…']},
  {kind: 'tool', at: 350, verb: 'Read', target: 'src/sync/network.ts'},
  {kind: 'tool', at: 380, verb: 'Edit', target: 'src/sync/network.ts', detail: '+21'},
  {kind: 'tool', at: 420, verb: 'Run', target: 'npm test -- sync', detail: '31 passed'},
  {kind: 'text', at: 470, lines: ['Adding a replay test that drops the connection mid-edit…']},
  {kind: 'tool', at: 520, verb: 'Edit', target: 'test/sync/replay.test.ts', detail: '+64'},
];

const CHARS_PER_FRAME = 2.6;
const CODE_LINES_PER_FRAME = 0.45;
const TOOL_RUN = 8;
const PROMPT_START = 4;

export type Item =
  | {kind: 'prompt'; y: number; h: number}
  | {kind: 'text'; y: number; h: number; lines: string[]}
  | {kind: 'tool'; y: number; h: number; verb: string; target: string; detail?: string; done: boolean}
  | {kind: 'code'; y: number; h: number; file: string; lines: string[]};

export type AgentState = {
  composer: string;
  items: Item[];
  scroll: number;
  focusY: number; // transcript y of the newest content (before scroll)
  streaming: boolean;
};

const PROMPT_H = 3 * LINE + 22;

export function agentAt(frame: number): AgentState {
  const typed = Math.max(0, Math.min(PROMPT.length, Math.floor((frame - PROMPT_START) * (PROMPT.length / (BEATS.promptSent - PROMPT_START - 6)))));
  if (frame < BEATS.promptSent) {
    return {composer: PROMPT.slice(0, typed), items: [], scroll: 0, focusY: AGENT_VIEW.h, streaming: false};
  }
  const items: Item[] = [{kind: 'prompt', y: 0, h: PROMPT_H}];
  let y = PROMPT_H + GAP;
  let streaming = false;
  for (const s of SCRIPT) {
    if (frame < s.at) { streaming = true; break; }
    if (s.kind === 'text') {
      let budget = Math.floor((frame - s.at) * CHARS_PER_FRAME);
      const lines: string[] = [];
      for (const l of s.lines) {
        if (budget <= 0) break;
        lines.push(l.slice(0, budget));
        budget -= l.length;
      }
      if (budget < 0) streaming = true;
      const h = s.lines.length * LINE;
      items.push({kind: 'text', y, h, lines});
      y += h + GAP;
      if (budget < 0) break;
    } else if (s.kind === 'tool') {
      const done = frame - s.at >= TOOL_RUN;
      if (!done) streaming = true;
      items.push({kind: 'tool', y, h: LINE + 4, verb: s.verb, target: s.target, detail: s.detail, done});
      y += LINE + 4 + GAP;
      if (!done) break;
    } else {
      const shown = Math.min(s.lines.length, Math.floor((frame - s.at) * CODE_LINES_PER_FRAME) + 1);
      const h = 34 + s.lines.length * CODE_LINE + 12;
      items.push({kind: 'code', y, h, file: s.file, lines: s.lines.slice(0, shown)});
      y += h + GAP;
      if (shown < s.lines.length) { streaming = true; break; }
    }
  }
  if (!streaming && frame < SCRIPT[SCRIPT.length - 1].at + 40) streaming = true;
  const last = items[items.length - 1];
  let focusY = last.y + last.h;
  if (last.kind === 'code') focusY = last.y + 34 + last.lines.length * CODE_LINE;
  const scroll = Math.max(0, focusY - AGENT_VIEW.h + 24);
  return {composer: '', items, scroll, focusY, streaming};
}
