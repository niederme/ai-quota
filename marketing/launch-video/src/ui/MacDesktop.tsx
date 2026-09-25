import React from 'react';
import {easeOut} from '../anim';
import {gaugeColor, type Usage} from '../timeline';
import {theme} from '../theme';
import {AgentWindow} from './AgentWindow';
import {MiniGauge} from './Gauge';
import {BatteryGlyph, ControlCenterGlyph, Cursor, SearchGlyph, WifiGlyph} from './Glyphs';
import {MacPopover} from './MacPopover';

// "Larger text" scaled resolution: fewer, bigger things on screen.
export const MAC_SCREEN = {w: 1180, h: 767};
const MENU_H = 30;
// Right side of the menu bar laid out in fixed slots (right to left: clock, Control
// Center, battery, Wi-Fi, AIQuota, Spotlight) with even spacing like real macOS, so the
// AIQuota extra's position is known exactly for the cursor and popover.
const MENU_PAD_R = 14;
const MENU_GAP = 14;
const SLOTS = [['search', 15], ['aiquota', 54], ['wifi', 17], ['battery', 25], ['cc', 16], ['clock', 136]] as const;
type Slot = (typeof SLOTS)[number][0];
const slotX: Record<Slot, number> = (() => {
  const total = SLOTS.reduce((w, [, sw]) => w + sw, 0) + MENU_GAP * (SLOTS.length - 1);
  let x = MAC_SCREEN.w - MENU_PAD_R - total;
  const out = {} as Record<Slot, number>;
  for (const [name, sw] of SLOTS) { out[name] = x; x += sw + MENU_GAP; }
  return out;
})();
const slotW = Object.fromEntries(SLOTS) as Record<Slot, number>;
// Menu bar extra centre (screen points); the popover hangs beneath it.
export const EXTRA = {x: slotX.aiquota + slotW.aiquota / 2, y: MENU_H / 2};
export const AGENT_RECT = {x: 110, y: 72, w: 760, h: 640};
export const POPOVER_RECT = {x: EXTRA.x - 170, y: MENU_H + 6, w: 340, h: 468};

// Neutral graphite wallpaper so AIQuota's purple is the only colour story.
const Wallpaper: React.FC = () => (
  <div style={{position: 'absolute', inset: 0, background: `
    radial-gradient(70% 60% at 85% 10%, rgba(120,150,190,0.35), transparent 70%),
    radial-gradient(60% 60% at 10% 95%, rgba(190,160,130,0.22), transparent 70%),
    linear-gradient(165deg, #3a3f47 0%, #24272c 55%, #1b1d21 100%)`}} />
);

export type CursorState = {x: number; y: number; opacity: number; press: number};

export const MacDesktop: React.FC<{frame: number; usage: Usage; popover: number; cursor: CursorState}> = ({frame, usage, popover, cursor}) => {
  const p = easeOut(Math.max(0, Math.min(1, popover)));
  const barColor = (w: Usage['codex']) => gaugeColor(Math.max(w.h5, w.d7));
  return (
    <div style={{position: 'relative', width: MAC_SCREEN.w, height: MAC_SCREEN.h, overflow: 'hidden', fontFamily: theme.font}}>
      <Wallpaper />
      <div style={{position: 'absolute', left: AGENT_RECT.x, top: AGENT_RECT.y}}>
        <AgentWindow frame={frame} />
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: MENU_H, display: 'flex', alignItems: 'center',
        padding: '0 16px', fontSize: 13, color: 'white', background: 'rgba(30,30,34,0.35)', backdropFilter: 'blur(20px)'}}>
        <div style={{display: 'flex', gap: 20}}>
          <b>Agent</b><span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span>
        </div>
      </div>
      {/* right-side menu extras, evenly spaced */}
      {([
        ['search', <SearchGlyph size={14} color="white" />],
        ['wifi', <WifiGlyph size={16} color="white" />],
        ['battery', <BatteryGlyph width={25} color="white" />],
        ['cc', <ControlCenterGlyph size={16} color="white" />],
      ] as const).map(([slot, glyph]) => (
        <div key={slot} style={{position: 'absolute', left: slotX[slot], top: 0, width: slotW[slot], height: MENU_H,
          display: 'flex', alignItems: 'center', justifyContent: 'center'}}>{glyph}</div>
      ))}
      <div style={{position: 'absolute', left: slotX.clock, top: 0, width: slotW.clock, height: MENU_H, display: 'flex', alignItems: 'center',
        justifyContent: 'flex-end', fontSize: 13, color: 'white', whiteSpace: 'nowrap'}}>Thu Sep 25&nbsp;&nbsp;9:41 AM</div>
      <div style={{position: 'absolute', left: slotX.aiquota, width: slotW.aiquota, top: 4, height: MENU_H - 8, boxSizing: 'border-box',
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4, borderRadius: 7, background: `rgba(255,255,255,${0.08 + 0.16 * p})`}}>
        <MiniGauge value={usage.codex.h5} size={16} color={barColor(usage.codex)} />
        <MiniGauge value={usage.claude.h5} size={16} color={barColor(usage.claude)} />
      </div>
      {p > 0.001 && (
        <div style={{position: 'absolute', left: POPOVER_RECT.x, top: POPOVER_RECT.y, opacity: Math.min(1, p * 1.6),
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
