import React from 'react';
import {agentAt, smoothScroll, type Item, type Session} from '../agent';
import {easeOut, ramp} from '../anim';
import {theme} from '../theme';

export const C = {
  window: '#1C1C1E', bar: '#232325', text: '#E5E5EA', dim: '#8E8E93', faint: '#48484A',
  bubble: '#2C2C2E', code: '#141416', ok: '#30D158', verb: '#64D2FF',
  kw: '#FF7AB2', fn: '#67B7A4', str: '#FC6A5D', type: '#D0BF69',
};

export const Spinner: React.FC<{frame: number}> = ({frame}) => (
  <span style={{display: 'inline-block', width: 16, color: theme.accent}}>{'✶✸✹✺✹✸'[Math.floor(frame / 5) % 6]}</span>
);

// New content fades and rises into place instead of popping.
const enter = (frame: number, at: number): React.CSSProperties => {
  const t = ramp(frame, at, at + 12, easeOut);
  return t >= 1 ? {} : {opacity: t, transform: `translateY(${(1 - t) * 10}px)`};
};

const Row: React.FC<{item: Item; frame: number; s: Session; fontSize: number; monoSize: number}> = ({item, frame, s, fontSize, monoSize}) => {
  const base: React.CSSProperties = {position: 'absolute', left: 0, right: 0, top: item.y};
  switch (item.kind) {
    case 'prompt':
      return (
        <div style={{...base, display: 'flex', justifyContent: 'flex-end'}}>
          <div style={{padding: '11px 16px', borderRadius: 18, background: C.bubble, color: C.text, fontSize, lineHeight: `${s.line}px`, whiteSpace: 'pre'}}>
            {item.lines.map((l, i) => <div key={i}>{l}</div>)}
          </div>
        </div>
      );
    case 'text':
      return (
        <div style={{...base, fontSize, lineHeight: `${s.line}px`, color: C.text, whiteSpace: 'pre'}}>
          {item.lines.map((l, i) => <div key={i}>{l}</div>)}
        </div>
      );
    case 'plan':
      return (
        <div style={{...base, fontSize: fontSize - 1}}>
          {item.steps.map((step, i) => (
            <div key={i} style={{height: s.row, display: 'flex', alignItems: 'center', gap: 10, color: item.done[i] ? C.dim : C.text}}>
              <span style={{width: 16, textAlign: 'center', color: item.done[i] ? C.ok : C.dim}}>{item.done[i] ? '✔' : '◻'}</span>
              <span style={{textDecoration: item.done[i] ? 'line-through' : 'none'}}>{step}</span>
            </div>
          ))}
        </div>
      );
    case 'agents': {
      const running = item.rows.some((r) => !r.done);
      return (
        <div style={{...base, fontFamily: theme.mono, fontSize: monoSize, whiteSpace: 'pre'}}>
          <div style={{height: s.row, display: 'flex', alignItems: 'center', gap: 8, color: C.text, fontWeight: 600}}>
            {running ? <Spinner frame={frame} /> : <span style={{color: C.ok, width: 16}}>●</span>}
            {running ? item.title : `${item.rows.length} agents finished`}
          </div>
          {item.rows.slice(0, item.reveal).map((r, i) => (
            <div key={r.name} style={{height: s.row, display: 'flex', alignItems: 'center', gap: 8, ...enter(frame, r.at)}}>
              <span style={{color: C.faint}}>{i === item.rows.length - 1 ? '└─' : '├─'}</span>
              {r.done ? <span style={{color: C.ok, width: 16}}>●</span> : <Spinner frame={frame + i * 7} />}
              <span style={{color: C.verb, fontWeight: 600}}>{r.name}</span>
              <span style={{color: r.done ? C.ok : C.dim, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis'}}>{r.done ? 'Done' : `${r.task}…`}</span>
              <span style={{color: r.done ? C.dim : C.text}}>{(r.tokens / 1000).toFixed(1)}k</span>
            </div>
          ))}
        </div>
      );
    }
  }
};

export const Transcript: React.FC<{session: Session; frame: number; fontSize: number; monoSize: number}> = ({session, frame, fontSize, monoSize}) => {
  const a = agentAt(session, frame);
  return (
    <div style={{position: 'relative', width: session.view.w, height: session.view.h, overflow: 'hidden', fontFamily: theme.font}}>
      <div style={{position: 'absolute', left: 0, right: 0, top: -smoothScroll(session, frame)}}>
        {a.items.map((item, i) => (
          <div key={i} style={enter(frame, item.at)}>
            <Row item={item} frame={frame} s={session} fontSize={fontSize} monoSize={monoSize} />
          </div>
        ))}
      </div>
    </div>
  );
};
