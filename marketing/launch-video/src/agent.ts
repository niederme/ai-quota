// Generic AI coding-agent sessions shown on the Mac and the iPhone. Heavy,
// token-hungry work (plans, parallel sub-agents) so the quota story is obvious.
// Pure layout model: every item has a deterministic height so the transcript
// can auto-scroll and the camera can follow the newest line without measuring the DOM.
import {smooth} from './anim';
import {BEATS} from './timeline';

type SubAgent = {name: string; tasks: string[]; tokens: number; doneAt: number};

export type ScriptItem =
  | {kind: 'prompt'; at: number; lines: string[]} // `at` = send frame; typed in the composer before it
  | {kind: 'text'; at: number; lines: string[]}
  | {kind: 'plan'; at: number; steps: string[]; doneAt: number[]}
  | {kind: 'agents'; at: number; title: string; agents: SubAgent[]};

export type Session = {
  script: ScriptItem[];
  view: {w: number; h: number};
  line: number;
  row: number;
  gap: number;
  charsPerFrame: number;
  typeFrames: number;
};

const P = BEATS.promptSent;
const F = BEATS.followUp;
export const MAC_SESSION: Session = {
  view: {w: 700, h: 468}, line: 23, row: 25, gap: 14, charsPerFrame: 3, typeFrames: 40,
  script: [
    {kind: 'prompt', at: P, lines: ['Build a marketing site for our new iOS app: landing page, pricing,', 'docs and a blog. One agent per section, Lighthouse above 95.']},
    {kind: 'text', at: P + 6, lines: ['Big one. Here’s the plan, then I’ll fan out to parallel agents:']},
    {kind: 'plan', at: P + 26, steps: ['Design tokens and shared layout', 'Build each section in parallel', 'Wire docs search and blog feed', 'Performance and accessibility pass'],
      doneAt: [P + 60, P + 200, P + 218, 9999]},
    {kind: 'agents', at: P + 64, title: 'Running 4 agents', agents: [
      {name: 'landing', tasks: ['Reading brand assets', 'Writing hero + features', 'Tuning animations'], tokens: 48200, doneAt: P + 196},
      {name: 'pricing', tasks: ['Drafting plans table', 'Building FAQ', 'Wiring checkout links'], tokens: 31700, doneAt: P + 160},
      {name: 'docs', tasks: ['Indexing 142 source files', 'Writing API reference', 'Generating examples'], tokens: 86400, doneAt: P + 214},
      {name: 'blog', tasks: ['Scaffolding MDX', 'Writing launch post', 'Building RSS feed'], tokens: 39900, doneAt: P + 182},
    ]},
    {kind: 'text', at: P + 222, lines: ['All 4 agents done: 61 pages, Lighthouse 98.']},
    {kind: 'prompt', at: F, lines: ['Now make it responsive, add dark mode, and have agents review', 'every page for accessibility.']},
    {kind: 'text', at: F + 6, lines: ['On it. Spinning up 5 reviewers alongside the build:']},
    {kind: 'agents', at: F + 26, title: 'Running 5 agents', agents: [
      {name: 'responsive', tasks: ['Auditing 61 pages', 'Rewriting grid breakpoints', 'Testing 9 viewports'], tokens: 72300, doneAt: F + 560},
      {name: 'dark-mode', tasks: ['Extracting color tokens', 'Theming components', 'Checking contrast'], tokens: 54800, doneAt: F + 420},
      {name: 'a11y-review', tasks: ['Scanning landmarks', 'Fixing focus order', 'Writing alt text'], tokens: 91200, doneAt: F + 700},
      {name: 'docs-review', tasks: ['Reading 38 guides', 'Checking code samples', 'Fixing broken links'], tokens: 66100, doneAt: F + 640},
      {name: 'perf', tasks: ['Profiling bundles', 'Splitting routes', 'Compressing images'], tokens: 43500, doneAt: F + 480},
    ]},
  ],
};

const PP = BEATS.phonePrompt;
export const PHONE_SESSION: Session = {
  view: {w: 364, h: 600}, line: 22, row: 24, gap: 12, charsPerFrame: 2.8, typeFrames: 34,
  script: [
    {kind: 'prompt', at: PP, lines: ['Make a 20-second launch video', 'for the app: device mockups,', 'motion, and a beat. 4K master.']},
    {kind: 'text', at: PP + 6, lines: ['Love it. Splitting the work:']},
    {kind: 'agents', at: PP + 22, title: 'Running 4 agents', agents: [
      {name: 'storyboard', tasks: ['Writing shot list', 'Timing beats'], tokens: 28400, doneAt: PP + 70},
      {name: 'ui-rebuild', tasks: ['Reading SwiftUI views', 'Rebuilding screens'], tokens: 63100, doneAt: PP + 118},
      {name: 'motion', tasks: ['Keyframing camera', 'Adding 3D tilt'], tokens: 45700, doneAt: PP + 132},
      {name: 'soundtrack', tasks: ['Sketching drums', 'Mixing'], tokens: 22900, doneAt: PP + 104},
    ]},
    {kind: 'text', at: PP + 136, lines: ['First cut rendered: 4K, 20s.']},
    {kind: 'prompt', at: PP + 166, lines: ['Great. More dynamic zooms,', 'and make the music hit harder.']},
    {kind: 'agents', at: PP + 178, title: 'Running 2 agents', agents: [
      {name: 'motion', tasks: ['Adding whip zooms', 'Retiming to the beat'], tokens: 51200, doneAt: PP + 420},
      {name: 'soundtrack', tasks: ['Programming breakbeat', 'Adding a tape stop'], tokens: 37800, doneAt: PP + 380},
    ]},
  ],
};

export type AgentRow = {name: string; task: string; tokens: number; done: boolean};

export type Item =
  | {kind: 'prompt'; y: number; h: number; lines: string[]}
  | {kind: 'text'; y: number; h: number; lines: string[]}
  | {kind: 'plan'; y: number; h: number; steps: string[]; done: boolean[]}
  | {kind: 'agents'; y: number; h: number; title: string; rows: AgentRow[]; reveal: number};

export type AgentState = {
  composer: string;
  items: Item[];
  scroll: number;
  focusY: number; // transcript y of the newest content (before scroll)
  streaming: boolean;
};

const ROW_STAGGER = 5;

function agentRows(frame: number, block: Extract<ScriptItem, {kind: 'agents'}>): AgentRow[] {
  return block.agents.map((g, i) => {
    const start = block.at + i * ROW_STAGGER;
    const t = Math.max(0, Math.min(1, (frame - start) / (g.doneAt - start)));
    const task = g.tasks[Math.min(g.tasks.length - 1, Math.floor(t * g.tasks.length))];
    // Tokens ramp quickly at first (reading), then keep ticking up.
    return {name: g.name, task, tokens: Math.round(g.tokens * (0.6 * smooth(Math.min(1, t * 1.6)) + 0.4 * t)), done: frame >= g.doneAt};
  });
}

export function agentAt(s: Session, frame: number): AgentState {
  const items: Item[] = [];
  let y = 0;
  let streaming = false;
  let composer = '';
  for (const item of s.script) {
    if (item.kind === 'prompt' && frame < item.at) {
      // Type into the composer during the frames before sending.
      const text = item.lines.join(' ');
      const t = (frame - (item.at - s.typeFrames)) / (s.typeFrames - 4);
      if (t > 0) composer = text.slice(0, Math.min(text.length, Math.ceil(t * text.length)));
      break;
    }
    if (frame < item.at) { streaming = true; break; }
    if (item.kind === 'prompt') {
      const h = item.lines.length * s.line + 22;
      items.push({kind: 'prompt', y, h, lines: item.lines});
      y += h + s.gap;
    } else if (item.kind === 'text') {
      let budget = Math.floor((frame - item.at) * s.charsPerFrame);
      const lines: string[] = [];
      for (const l of item.lines) {
        if (budget <= 0) break;
        lines.push(l.slice(0, budget));
        budget -= l.length;
      }
      const h = item.lines.length * s.line;
      items.push({kind: 'text', y, h, lines});
      y += h + s.gap;
      if (budget < 0) { streaming = true; break; }
    } else if (item.kind === 'plan') {
      const h = item.steps.length * s.row;
      items.push({kind: 'plan', y, h, steps: item.steps, done: item.doneAt.map((d) => frame >= d)});
      y += h + s.gap;
    } else {
      const rows = agentRows(frame, item);
      const reveal = Math.min(item.agents.length, Math.floor((frame - item.at) / ROW_STAGGER) + 1);
      const h = s.row + item.agents.length * s.row;
      items.push({kind: 'agents', y, h, title: item.title, rows, reveal});
      y += h + s.gap;
      if (rows.some((r) => !r.done)) streaming = true;
    }
  }
  if (items.length === 0) return {composer, items, scroll: 0, focusY: s.view.h, streaming: false};
  const tail = items[items.length - 1];
  const focusY = tail.kind === 'agents' ? tail.y + s.row * (1 + tail.reveal) : tail.y + tail.h;
  const scroll = Math.max(0, focusY - s.view.h + 24);
  return {composer, items, scroll, focusY, streaming};
}

// Session-wide token counter shown in the status line: context + streamed text + every sub-agent.
export function sessionTokens(s: Session, frame: number): number {
  const a = agentAt(s, frame);
  let total = a.items.length ? 3200 : 0;
  for (const item of a.items) {
    if (item.kind === 'text') total += item.lines.join('').length * 14;
    if (item.kind === 'prompt') total += 1800;
    if (item.kind === 'agents') total += item.rows.slice(0, item.reveal).reduce((n, r) => n + r.tokens, 0);
  }
  return total;
}
