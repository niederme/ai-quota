import React from 'react';
import {staticFile, Img} from 'remotion';
import {gaugeColor, type Usage} from '../timeline';
import {theme} from '../theme';
import {Gauge} from './Gauge';
import {RefreshGlyph} from './Glyphs';

const W = 340;
const divider = <div style={{height: 1, background: 'rgba(255,255,255,0.10)'}} />;

const Column: React.FC<{service: 'codex' | 'claude'; name: string; usage: Usage['codex']; reveal: number}> = ({service, name, usage, reveal}) => {
  const color = gaugeColor(Math.max(usage.h5, usage.d7));
  return (
    <div style={{flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 14}}>
      <Gauge service={service} usage={usage} size={124} ring={9} gap={3} reveal={reveal} />
      <div style={{marginTop: -12}}><RefreshGlyph size={13} color="rgba(235,235,245,0.4)" /></div>
      <div style={{marginTop: 6, fontSize: 15, fontWeight: 700, color: theme.primary}}>{name}</div>
      <div style={{marginTop: 3, fontSize: 11, lineHeight: 1.35, textAlign: 'center', color, opacity: 0.85}}>
        5h resets 10:01am<br />7d resets Mon. 8:01am
      </div>
    </div>
  );
};

export const MacPopover: React.FC<{usage: Usage; reveal: number}> = ({usage, reveal}) => (
  <div style={{width: W, borderRadius: 16, overflow: 'hidden', fontFamily: theme.font, color: theme.primary,
    // Translucent glass like the real menu bar popover: the desktop shows through,
    // with only a light purple tint.
    background: 'linear-gradient(180deg, rgba(86,72,112,0.34) 0%, rgba(44,38,60,0.30) 100%)',
    backdropFilter: 'blur(36px) saturate(1.9) brightness(1.08)', WebkitBackdropFilter: 'blur(36px) saturate(1.9) brightness(1.08)',
    border: '1px solid rgba(255,255,255,0.20)',
    boxShadow: '0 24px 60px rgba(0,0,0,0.42), inset 0 1px 0 rgba(255,255,255,0.22), inset 0 0 0 1px rgba(255,255,255,0.04)'}}>
    <div style={{display: 'flex', alignItems: 'center', padding: '12px 16px', gap: 10}}>
      <Img src={staticFile('icon-dark.png')} style={{width: 22, height: 22}} />
      <div style={{fontSize: 15, fontWeight: 700, flex: 1}}>AIQuota</div>
      <div style={{fontSize: 13, fontWeight: 600, color: theme.accent}}>● 5h <span style={{opacity: 0.55, marginLeft: 6}}>● 7d</span></div>
    </div>
    {divider}
    <div style={{display: 'flex', paddingBottom: 14}}>
      <Column service="codex" name="Codex" usage={usage.codex} reveal={reveal} />
      <div style={{width: 1, background: 'rgba(255,255,255,0.10)', margin: '18px 0'}} />
      <Column service="claude" name="Claude Code" usage={usage.claude} reveal={reveal} />
    </div>
    {divider}
    <div style={{display: 'flex', padding: '12px 16px', fontSize: 12, lineHeight: 1.7}}>
      <div style={{flex: 1}}>
        <span style={{color: theme.secondary}}>Plan:</span> <b>Plus</b><br />
        <span style={{color: theme.secondary}}>Credit balance:</span> <b>$10.44</b>
      </div>
      <div style={{flex: 1, paddingLeft: 16}}>
        <span style={{color: theme.secondary}}>Plan:</span> <b>Max</b>
      </div>
    </div>
    {divider}
    <div style={{display: 'flex', justifyContent: 'space-between', padding: '12px 20px', fontSize: 14}}>
      <span style={{color: 'rgba(200,190,255,0.9)'}}>Settings</span>
      <span style={{color: theme.tertiary}}>Just now</span>
      <span style={{color: 'rgba(200,190,255,0.9)'}}>Quit</span>
    </div>
  </div>
);
