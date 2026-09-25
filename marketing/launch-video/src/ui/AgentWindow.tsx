import React from 'react';
import {AGENT_VIEW, agentAt, LINE, PROMPT as PROMPT_TEXT, type Item} from '../agent';
import {theme} from '../theme';
import {tokensAt, BEATS} from '../timeline';

const C = {
  window: '#1C1C1E', bar: '#232325', text: '#E5E5EA', dim: '#8E8E93', faint: '#48484A',
  bubble: '#2C2C2E', code: '#141416', ok: '#30D158', verb: '#64D2FF',
  kw: '#FF7AB2', fn: '#67B7A4', str: '#FC6A5D', type: '#D0BF69',
};

// Light-touch syntax colouring for the TypeScript sample.
function highlight(line: string) {
  const parts = line.split(/('[^']*'|\b(?:export|class|private|async|await|while|this)\b|\b[A-Z][A-Za-z]+\b|\b\w+(?=\())/g);
  return parts.map((p, i) => {
    if (!p) return null;
    let color = C.text;
    if (/^'/.test(p)) color = C.str;
    else if (/^(export|class|private|async|await|while|this)$/.test(p)) color = C.kw;
    else if (/^[A-Z]/.test(p)) color = C.type;
    else if (i % 2 === 1) color = C.fn;
    return <span key={i} style={{color}}>{p}</span>;
  });
}

const Spinner: React.FC<{frame: number; color?: string}> = ({frame, color = theme.accent}) => (
  <span style={{display: 'inline-block', width: 16, color}}>{'✶✸✹✺✹✸'[Math.floor(frame / 5) % 6]}</span>
);

const Row: React.FC<{item: Item; frame: number}> = ({item, frame}) => {
  const base: React.CSSProperties = {position: 'absolute', left: 0, right: 0, top: item.y};
  switch (item.kind) {
    case 'prompt':
      return null;
    case 'text':
      return (
        <div style={{...base, fontSize: 15, lineHeight: `${LINE}px`, color: C.text, whiteSpace: 'pre'}}>
          {item.lines.map((l, i) => <div key={i}>{l}</div>)}
        </div>
      );
    case 'tool':
      return (
        <div style={{...base, height: item.h, display: 'flex', alignItems: 'center', gap: 10, fontFamily: theme.mono, fontSize: 13.5}}>
          {item.done ? <span style={{color: C.ok, width: 16}}>●</span> : <Spinner frame={frame} />}
          <span style={{color: C.verb, fontWeight: 600}}>{item.verb}</span>
          <span style={{color: C.text}}>{item.target}</span>
          {item.detail && item.done && <span style={{color: C.dim}}>· {item.detail}</span>}
        </div>
      );
    case 'code':
      return (
        <div style={{...base, height: item.h, borderRadius: 10, background: C.code, border: `1px solid ${C.faint}55`, overflow: 'hidden'}}>
          <div style={{height: 30, display: 'flex', alignItems: 'center', padding: '0 14px', fontFamily: theme.mono, fontSize: 12, color: C.dim, borderBottom: `1px solid ${C.faint}55`}}>{item.file}</div>
          <div style={{padding: '6px 14px', fontFamily: theme.mono, fontSize: 13, lineHeight: '20px', whiteSpace: 'pre'}}>
            {item.lines.map((l, i) => <div key={i}>{l === '' ? ' ' : highlight(l)}</div>)}
          </div>
        </div>
      );
  }
};

export const AgentWindow: React.FC<{frame: number}> = ({frame}) => {
  const a = agentAt(frame);
  // Ease the auto-scroll so new lines glide in rather than snap.
  let scroll = 0;
  for (let k = 0; k < 8; k++) scroll += agentAt(Math.max(0, frame - k)).scroll;
  scroll /= 8;
  const tokens = tokensAt(frame);
  const secs = Math.max(0, Math.floor((frame - BEATS.promptSent) / 60 * 3.1));
  const prompt = a.items.find((i) => i.kind === 'prompt');
  return (
    <div style={{width: 760, height: 640, borderRadius: 14, background: C.window, overflow: 'hidden', fontFamily: theme.font,
      border: '1px solid rgba(255,255,255,0.10)', boxShadow: '0 30px 80px rgba(0,0,0,0.5)', position: 'relative'}}>
      <div style={{height: 44, background: C.bar, display: 'flex', alignItems: 'center', padding: '0 16px', gap: 8, borderBottom: '1px solid rgba(255,255,255,0.06)'}}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: c}} />)}
        <div style={{flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, color: C.dim, marginRight: 52}}>notes-app — Agent</div>
      </div>
      <div style={{position: 'absolute', left: 30, top: 44 + 18, width: AGENT_VIEW.w, height: AGENT_VIEW.h, overflow: 'hidden'}}>
        <div style={{position: 'absolute', left: 0, right: 0, top: -scroll}}>
          {prompt && (
            <div style={{position: 'absolute', right: 0, top: 0, width: 520, padding: '11px 16px', borderRadius: 16, background: C.bubble,
              color: C.text, fontSize: 15, lineHeight: `${LINE}px`}}>{PROMPT_TEXT}</div>
          )}
          {a.items.map((item, i) => <Row key={i} item={item} frame={frame} />)}
        </div>
      </div>
      <div style={{position: 'absolute', left: 20, right: 20, bottom: 18}}>
        <div style={{height: 22, fontFamily: theme.mono, fontSize: 12.5, color: C.dim, marginBottom: 8, paddingLeft: 4, opacity: frame >= BEATS.promptSent ? 1 : 0}}>
          {a.streaming ? <Spinner frame={frame} /> : <span style={{color: C.ok}}>● </span>}
          <span style={{color: theme.accent}}>Working</span> · {(tokens / 1000).toFixed(1)}k tokens · {secs}s
        </div>
        <div style={{minHeight: 48, borderRadius: 14, background: C.bubble, border: '1px solid rgba(255,255,255,0.08)', padding: '13px 16px',
          fontSize: 15, lineHeight: '22px', color: a.composer ? C.text : C.dim}}>
          {a.composer || 'Ask the agent…'}
          {a.composer && frame % 40 < 22 && <span style={{display: 'inline-block', width: 2, height: 18, marginLeft: 1, background: C.text, verticalAlign: -3}} />}
        </div>
      </div>
    </div>
  );
};
