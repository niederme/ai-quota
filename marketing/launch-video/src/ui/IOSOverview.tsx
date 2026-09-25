import React from 'react';
import {Img, staticFile} from 'remotion';
import {easeOut} from '../anim';
import {gaugeColor, resetLines, type Usage, type Window} from '../timeline';
import {theme} from '../theme';
import {Gauge} from './Gauge';
import {BatteryGlyph, ChevronBadge, GearGlyph, RefreshGlyph, WifiGlyph} from './Glyphs';

const glass: React.CSSProperties = {
  background: 'rgba(255,255,255,0.075)', border: '1px solid rgba(255,255,255,0.12)',
  backdropFilter: 'blur(24px) saturate(1.4)', WebkitBackdropFilter: 'blur(24px) saturate(1.4)',
  boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.10)',
};

const Background: React.FC = () => (
  <div style={{position: 'absolute', inset: 0, background: `
    radial-gradient(circle at 100% 0%, rgba(191,90,242,0.35), transparent 357px),
    linear-gradient(180deg, rgba(102,31,143,0.72) 0%, rgba(191,90,242,0.12) 40%, transparent 70%),
    ${theme.base}`}} />
);

const HISTORY = Array.from({length: 30}, (_, i) => [32, 48, 21, 64, 53, 18, 8][(29 - i) % 7]);

const Card: React.FC<{service: 'codex' | 'claude'; name: string; plan: string; usage: Window; glow: number; frame: number; chart?: boolean}> = ({service, name, plan, usage, glow, frame, chart}) => {
  const color = gaugeColor(Math.max(usage.h5, usage.d7));
  const [h5, d7] = resetLines(service, 'ios', frame);
  return (
    <div style={{...glass, borderRadius: 28, padding: '16px 16px 14px', position: 'relative',
      boxShadow: `${glass.boxShadow}, 0 0 ${40 * glow}px ${color}${glow > 0 ? '66' : '00'}`}}>
      <div style={{display: 'flex', gap: 20}}>
        <Gauge service={service} usage={usage} size={124} ring={10} gap={3} glow={glow} />
        <div style={{flex: 1, paddingTop: 6}}>
          <div style={{fontSize: 22, fontWeight: 600, color: theme.primary}}>{name}</div>
          <div style={{fontSize: 15, color: theme.secondary, marginTop: 2}}>{plan}</div>
          <div style={{fontSize: 15, fontWeight: 500, color, marginTop: 12, lineHeight: 1.45}}>
            {h5}<br />{d7}
          </div>
        </div>
        <div style={{position: 'absolute', right: 16, top: 16}}><ChevronBadge size={20} /></div>
      </div>
      {chart && (
        <>
          <div style={{height: 1, background: 'rgba(255,255,255,0.10)', margin: '18px 0 14px'}} />
          <div style={{display: 'flex', alignItems: 'flex-end', gap: 5, height: 44}}>
            {HISTORY.map((v, i) => <div key={i} style={{flex: 1, height: `${(v / 64) * 100}%`, background: theme.accent, borderRadius: 1.5}} />)}
          </div>
          <div style={{fontSize: 13, color: theme.secondary, marginTop: 8}}>Aug 27 – Today</div>
        </>
      )}
    </div>
  );
};

export const Notification: React.FC<{progress: number}> = ({progress}) => {
  const p = easeOut(Math.max(0, Math.min(1, progress)));
  return (
    <div style={{position: 'absolute', left: 10, right: 10, top: 56, opacity: Math.min(1, p * 2),
      transform: `translateY(${(1 - p) * -120}px)`, borderRadius: 24, padding: '13px 14px', display: 'flex', gap: 11,
      background: 'rgba(52,40,66,0.72)', backdropFilter: 'blur(30px) saturate(1.8)', WebkitBackdropFilter: 'blur(30px) saturate(1.8)',
      border: '1px solid rgba(255,255,255,0.14)', boxShadow: '0 12px 30px rgba(0,0,0,0.4)', fontFamily: theme.font}}>
      <Img src={staticFile('icon-dark.png')} style={{width: 38, height: 38, borderRadius: 9}} />
      <div style={{flex: 1, color: theme.primary, fontSize: 15, lineHeight: 1.3}}>
        <div style={{display: 'flex', justifyContent: 'space-between'}}>
          <b>Claude 5h usage high</b><span style={{color: theme.secondary, fontSize: 13}}>now</span>
        </div>
        <div style={{color: 'rgba(235,235,245,0.8)'}}>85% used. Open AIQuota for current usage.</div>
      </div>
    </div>
  );
};

export const IOSOverview: React.FC<{usage: Usage; claudeGlow: number; notification: number; frame: number}> = ({usage, claudeGlow, notification, frame}) => (
  <div style={{position: 'relative', width: 420, height: 912, overflow: 'hidden', fontFamily: theme.font, color: theme.primary}}>
    <Background />
    <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: 54, display: 'flex', alignItems: 'center',
      justifyContent: 'space-between', padding: '8px 40px 0 58px', fontSize: 17, fontWeight: 600}}>
      <span>9:41</span>
      <span style={{display: 'flex', gap: 7, alignItems: 'center'}}><WifiGlyph size={18} color="white" /><BatteryGlyph width={27} color="white" /></span>
    </div>
    <div style={{position: 'absolute', left: 20, right: 18, top: 68, display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
      <div style={{fontSize: 34, fontWeight: 700, letterSpacing: 0.2}}>AIQuota</div>
      <div style={{...glass, background: 'rgba(191,90,242,0.35)', borderRadius: 24, display: 'flex', gap: 28, padding: '10px 20px'}}>
        <RefreshGlyph size={22} color="white" /><GearGlyph size={22} color="white" />
      </div>
    </div>
    <div style={{position: 'absolute', left: 17, right: 17, top: 142, display: 'flex', flexDirection: 'column', gap: 26}}>
      <Card service="codex" name="Codex" plan="Plus plan" usage={usage.codex} glow={0} frame={frame} chart />
      <Card service="claude" name="Claude" plan="Max plan" usage={usage.claude} glow={claudeGlow} frame={frame} />
      <div style={{textAlign: 'center', fontSize: 13, color: theme.secondary}}>Updated just now</div>
    </div>
    {notification > 0 && <Notification progress={notification} />}
  </div>
);
