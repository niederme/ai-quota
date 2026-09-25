import React from 'react';
import {easeOut} from '../anim';
import {gaugeColor, type Usage} from '../timeline';
import {theme} from '../theme';
import {MiniGauge} from './Gauge';
import {BatteryGlyph, Cursor, WifiGlyph} from './Glyphs';
import {MacPopover} from './MacPopover';

export const MAC_SCREEN = {w: 1470, h: 956};
const MENU_H = 34;
// Menu bar extra position (screen points); the popover hangs beneath it.
export const EXTRA = {x: 1198, y: MENU_H / 2};

const Wallpaper: React.FC = () => (
  <div style={{position: 'absolute', inset: 0, background: `
    radial-gradient(60% 55% at 78% 18%, rgba(191,90,242,0.55), transparent 70%),
    radial-gradient(70% 60% at 12% 88%, rgba(102,31,143,0.85), transparent 70%),
    radial-gradient(50% 45% at 45% 55%, rgba(60,20,110,0.7), transparent 75%),
    linear-gradient(160deg, #1d0c2e 0%, #0B060F 70%)`}} />
);

// Suggests a coding session in progress behind the popover.
const TerminalWindow: React.FC<{frame: number}> = ({frame}) => {
  const lines = [0.62, 0.44, 0.78, 0.3, 0.55, 0.7, 0.4, 0.66, 0.25, 0.58, 0.48, 0.72, 0.35, 0.6];
  const visible = Math.min(lines.length, 5 + Math.floor(frame / 18));
  return (
    <div style={{position: 'absolute', left: 150, top: 150, width: 760, height: 560, borderRadius: 16,
      background: 'rgba(18,12,26,0.86)', border: '1px solid rgba(255,255,255,0.10)',
      boxShadow: '0 30px 80px rgba(0,0,0,0.45)', overflow: 'hidden'}}>
      <div style={{height: 40, display: 'flex', alignItems: 'center', gap: 8, paddingLeft: 16}}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: c}} />)}
      </div>
      <div style={{padding: '14px 28px', display: 'flex', flexDirection: 'column', gap: 16}}>
        {lines.slice(0, visible).map((w, i) => (
          <div key={i} style={{display: 'flex', gap: 10}}>
            <div style={{width: 14, height: 10, borderRadius: 5, background: i % 4 === 0 ? theme.accent : 'rgba(255,255,255,0.18)'}} />
            <div style={{width: `${w * 90}%`, height: 10, borderRadius: 5, background: 'rgba(235,235,245,0.22)'}} />
          </div>
        ))}
      </div>
    </div>
  );
};

export const MacDesktop: React.FC<{frame: number; usage: Usage; popover: number; cursor: {x: number; y: number; opacity: number; press: number}}> = ({frame, usage, popover, cursor}) => {
  const p = easeOut(Math.max(0, Math.min(1, popover)));
  const barColor = (w: Usage['codex']) => gaugeColor(Math.max(w.h5, w.d7));
  return (
    <div style={{position: 'relative', width: MAC_SCREEN.w, height: MAC_SCREEN.h, overflow: 'hidden', fontFamily: theme.font}}>
      <Wallpaper />
      <TerminalWindow frame={frame} />
      <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: MENU_H, display: 'flex', alignItems: 'center',
        padding: '0 18px', fontSize: 14, color: 'white', background: 'rgba(20,10,30,0.25)', backdropFilter: 'blur(20px)'}}>
        <div style={{display: 'flex', gap: 22}}>
          <b>Terminal</b><span>Shell</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span>
        </div>
        <div style={{flex: 1}} />
        <div style={{display: 'flex', alignItems: 'center', gap: 18}}>
          <div style={{display: 'flex', gap: 5, padding: '3px 8px', borderRadius: 8,
            background: `rgba(255,255,255,${0.12 + 0.12 * p})`}}>
            <MiniGauge value={usage.codex.h5} size={18} color={barColor(usage.codex)} />
            <MiniGauge value={usage.claude.h5} size={18} color={barColor(usage.claude)} />
          </div>
          <WifiGlyph size={17} color="white" />
          <BatteryGlyph width={26} color="white" />
          <span>Thu Sep 25</span><span style={{marginLeft: -8}}>9:41 AM</span>
        </div>
      </div>
      {p > 0.001 && (
        <div style={{position: 'absolute', left: EXTRA.x - 170, top: MENU_H + 6, opacity: Math.min(1, p * 1.6),
          transform: `translateY(${(1 - p) * -10}px) scale(${0.96 + 0.04 * p})`, transformOrigin: '50% 0'}}>
          <MacPopover usage={usage} reveal={p} />
        </div>
      )}
      <div style={{position: 'absolute', left: cursor.x, top: cursor.y, opacity: cursor.opacity,
        transform: `scale(${1 - 0.12 * cursor.press})`, transformOrigin: '0 0'}}>
        <Cursor size={20} />
      </div>
    </div>
  );
};
