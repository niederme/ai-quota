import React from 'react';
import {agentAt, MAC_SESSION, sessionTokens, type Session} from '../agent';
import {theme} from '../theme';
import {C, Spinner, Transcript} from './Transcript';

export const StatusLine: React.FC<{session: Session; frame: number; size: number}> = ({session, frame, size}) => {
  const a = agentAt(session, frame);
  const start = session.script[0].at;
  const secs = Math.max(0, Math.floor(((frame - start) / 60) * 4.3));
  return (
    <div style={{fontFamily: theme.mono, fontSize: size, color: C.dim, whiteSpace: 'pre', opacity: frame >= start ? 1 : 0}}>
      {a.streaming ? <Spinner frame={frame} /> : <span style={{color: C.ok}}>● </span>}
      <span style={{color: theme.accent}}>Working</span> · {(sessionTokens(session, frame) / 1000).toFixed(1)}k tokens · {Math.floor(secs / 60)}m {secs % 60}s
    </div>
  );
};

// Fixed single-line composer: long prompts scroll left as they're typed, so the
// field never changes height mid-sentence.
const Caret: React.FC<{frame: number}> = ({frame}) =>
  frame % 40 < 22 ? <span style={{display: 'inline-block', width: 2, height: 18, marginLeft: 1, background: C.text, verticalAlign: -3}} /> : null;

export const Composer: React.FC<{text: string; frame: number; placeholder: string; fontSize: number; maxChars: number; focused?: boolean}> = ({text, frame, placeholder, fontSize, maxChars, focused}) => (
  <div style={{height: 48, boxSizing: 'border-box', borderRadius: 16, background: C.bubble, border: '1px solid rgba(255,255,255,0.08)', padding: '13px 16px',
    fontSize, lineHeight: '22px', color: text ? C.text : C.dim, whiteSpace: 'nowrap', overflow: 'hidden'}}>
    {!text && focused && <Caret frame={frame} />}
    {text ? (text.length > maxChars ? '…' + text.slice(-maxChars) : text) : placeholder}
    {text && <Caret frame={frame} />}
  </div>
);

export const AgentWindow: React.FC<{frame: number}> = ({frame}) => {
  const a = agentAt(MAC_SESSION, frame);
  return (
    <div style={{width: 760, height: 640, borderRadius: 14, background: C.window, overflow: 'hidden', fontFamily: theme.font,
      border: '1px solid rgba(255,255,255,0.10)', boxShadow: '0 30px 80px rgba(0,0,0,0.5)', position: 'relative'}}>
      <div style={{height: 44, background: C.bar, display: 'flex', alignItems: 'center', padding: '0 16px', gap: 8, borderBottom: '1px solid rgba(255,255,255,0.06)'}}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: c}} />)}
        <div style={{flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, color: C.dim, marginRight: 52}}>notes-app — Agent</div>
      </div>
      <div style={{position: 'absolute', left: 30, top: 62}}>
        <Transcript session={MAC_SESSION} frame={frame} fontSize={15} monoSize={13.5} />
      </div>
      <div style={{position: 'absolute', left: 20, right: 20, bottom: 18}}>
        <div style={{height: 22, marginBottom: 8, paddingLeft: 4}}><StatusLine session={MAC_SESSION} frame={frame} size={12.5} /></div>
        <Composer text={a.composer} frame={frame} placeholder="Ask the agent…" fontSize={15} maxChars={86} focused={frame < MAC_SESSION.script[0].at} />
      </div>
    </div>
  );
};
