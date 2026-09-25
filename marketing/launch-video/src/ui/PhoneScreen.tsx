import React from 'react';
import {agentAt, PHONE_SESSION} from '../agent';
import {easeInOut, keyframes, ramp} from '../anim';
import {theme} from '../theme';
import {BEATS, type Usage} from '../timeline';
import {Composer, StatusLine} from './AgentWindow';
import {BatteryGlyph, WifiGlyph} from './Glyphs';
import {IOSOverview, Notification} from './IOSOverview';
import {C, Transcript} from './Transcript';

const StatusBar: React.FC = () => (
  <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: 54, display: 'flex', alignItems: 'center',
    justifyContent: 'space-between', padding: '8px 40px 0 58px', fontSize: 17, fontWeight: 600, color: 'white', fontFamily: theme.font}}>
    <span>9:41</span>
    <span style={{display: 'flex', gap: 7, alignItems: 'center'}}><WifiGlyph size={18} color="white" /><BatteryGlyph width={27} color="white" /></span>
  </div>
);

// Generic AI agent chat app on iOS, same session as the Mac.
const PhoneChat: React.FC<{frame: number}> = ({frame}) => {
  const a = agentAt(PHONE_SESSION, frame);
  return (
    <div style={{position: 'absolute', inset: 0, background: '#000', fontFamily: theme.font, color: C.text}}>
      <StatusBar />
      <div style={{position: 'absolute', left: 0, right: 0, top: 54, height: 58, display: 'flex', alignItems: 'center', justifyContent: 'center',
        borderBottom: '1px solid rgba(255,255,255,0.08)'}}>
        <span style={{position: 'absolute', left: 18, fontSize: 28, color: C.verb, fontWeight: 300}}>‹</span>
        <div style={{textAlign: 'center'}}>
          <div style={{fontSize: 16, fontWeight: 600}}>notes-app</div>
          <div style={{fontSize: 12, color: C.dim}}>Agent</div>
        </div>
      </div>
      <div style={{position: 'absolute', left: 28, top: 128}}>
        <Transcript session={PHONE_SESSION} frame={frame} fontSize={15} monoSize={12.5} />
      </div>
      <div style={{position: 'absolute', left: 14, right: 14, bottom: 34}}>
        <div style={{height: 22, marginBottom: 8, paddingLeft: 6}}><StatusLine session={PHONE_SESSION} frame={frame} size={12} /></div>
        <Composer text={a.composer} frame={frame} placeholder="Message the agent…" fontSize={16} maxChars={38} />
      </div>
    </div>
  );
};

// Chat → usage notification → tap → AIQuota opens out of the banner.
export const PhoneScreen: React.FC<{frame: number; usage: Usage; claudeGlow: number}> = ({frame, usage, claudeGlow}) => {
  const notif = keyframes(frame, [[BEATS.notify, 0], [BEATS.notify + 26, 1]], easeInOut);
  const press = keyframes(frame, [[BEATS.tap - 4, 0], [BEATS.tap, 1], [BEATS.tap + 6, 0]]);
  const open = ramp(frame, BEATS.tap + 4, BEATS.tap + 34, easeInOut);
  const banner = {top: 56, left: 10, right: 10, h: 78};
  const inset = {
    top: banner.top * (1 - open),
    left: banner.left * (1 - open),
    right: banner.right * (1 - open),
    bottom: (912 - banner.top - banner.h) * (1 - open),
  };
  return (
    <div style={{position: 'relative', width: 420, height: 912, overflow: 'hidden', background: '#000'}}>
      <div style={{position: 'absolute', inset: 0, transform: `scale(${1 - 0.06 * open})`, opacity: 1 - 0.5 * open}}>
        <PhoneChat frame={frame} />
      </div>
      {notif > 0 && open < 1 && (
        <div style={{position: 'absolute', inset: 0, transform: `scale(${1 - 0.03 * press})`, transformOrigin: '50% 95px', opacity: 1 - open}}>
          <Notification progress={notif} />
        </div>
      )}
      {open > 0 && (
        <div style={{position: 'absolute', inset: 0, clipPath: `inset(${inset.top}px ${inset.right}px ${inset.bottom}px ${inset.left}px round ${24 * (1 - open) + 4}px)`}}>
          <IOSOverview usage={usage} claudeGlow={claudeGlow} notification={0} />
        </div>
      )}
    </div>
  );
};
