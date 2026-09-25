import React from 'react';

export const IPHONE_SCREEN = {w: 420, h: 912};

// Drawn iPhone Air (Space Black). `width` is the device width in stage px.
export const IPhoneAir: React.FC<{width: number; children: React.ReactNode}> = ({width: W, children}) => {
  const bezel = W * 0.036;
  const sw = W - bezel * 2;
  const sh = (sw * IPHONE_SCREEN.h) / IPHONE_SCREEN.w;
  const H = sh + bezel * 2;
  const btn = (side: 'l' | 'r', top: number, h: number) => (
    <div style={{position: 'absolute', [side === 'l' ? 'left' : 'right']: -W * 0.011, top, width: W * 0.016, height: h,
      borderRadius: W * 0.01, background: 'linear-gradient(90deg, #2a2a2e, #4a4a50, #2a2a2e)'}} />
  );
  return (
    <div style={{position: 'relative', width: W, height: H}}>
      {btn('l', H * 0.2, H * 0.045)}
      {btn('l', H * 0.28, H * 0.08)}
      {btn('l', H * 0.38, H * 0.08)}
      {btn('r', H * 0.3, H * 0.12)}
      {btn('r', H * 0.62, H * 0.07)}
      <div style={{position: 'absolute', inset: 0, borderRadius: W * 0.175,
        background: 'linear-gradient(135deg, #5a5a60 0%, #1c1c20 30%, #2c2c31 70%, #6a6a70 100%)',
        boxShadow: '0 40px 80px rgba(0,0,0,0.55), 0 0 0 1px rgba(0,0,0,0.6)'}} />
      <div style={{position: 'absolute', inset: W * 0.008, borderRadius: W * 0.168, background: '#000'}} />
      <div style={{position: 'absolute', left: bezel, top: bezel, width: sw, height: sh, borderRadius: W * 0.14, overflow: 'hidden'}}>
        <div style={{transform: `scale(${sw / IPHONE_SCREEN.w})`, transformOrigin: '0 0'}}>{children}</div>
        <div style={{position: 'absolute', left: sw / 2 - sw * 0.155, top: sw * 0.027, width: sw * 0.31, height: sw * 0.088,
          borderRadius: sw * 0.05, background: '#000'}} />
        <div style={{position: 'absolute', inset: 0, background: 'linear-gradient(120deg, rgba(255,255,255,0.07) 0%, transparent 35%)'}} />
      </div>
    </div>
  );
};
