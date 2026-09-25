import React from 'react';
import {MAC_SCREEN} from '../ui/MacDesktop';

// Drawn MacBook Air (Midnight). `width` is the lid width in stage px.
export const MacBookAir: React.FC<{width: number; children: React.ReactNode}> = ({width: W, children}) => {
  const side = W * 0.021;
  const top = W * 0.024;
  const bottom = W * 0.03;
  const sw = W - side * 2;
  const sh = (sw * MAC_SCREEN.h) / MAC_SCREEN.w;
  const lidH = top + sh + bottom;
  const baseW = W * 1.13;
  return (
    <div style={{position: 'relative', width: W, height: lidH + W * 0.034}}>
      <div style={{position: 'absolute', left: 0, top: 0, width: W, height: lidH,
        borderRadius: `${W * 0.03}px ${W * 0.03}px ${W * 0.012}px ${W * 0.012}px`,
        background: '#07070a', boxShadow: `inset 0 0 0 ${W * 0.0035}px #3a4250, inset 0 0 0 ${W * 0.005}px #111`}}>
        <div style={{position: 'absolute', left: side, top, width: sw, height: sh, overflow: 'hidden',
          borderRadius: `${W * 0.011}px ${W * 0.011}px 0 0`}}>
          <div style={{transform: `scale(${sw / MAC_SCREEN.w})`, transformOrigin: '0 0'}}>{children}</div>
          {/* screen glare */}
          <div style={{position: 'absolute', inset: 0, background: 'linear-gradient(115deg, rgba(255,255,255,0.06) 0%, transparent 38%)'}} />
        </div>
        <div style={{position: 'absolute', left: W / 2 - W * 0.05, top: top - 1, width: W * 0.1, height: W * 0.0215,
          background: '#07070a', borderRadius: `0 0 ${W * 0.008}px ${W * 0.008}px`}} />
        <div style={{position: 'absolute', left: W / 2 - W * 0.0025, top: top * 0.35, width: W * 0.005, height: W * 0.005,
          borderRadius: '50%', background: '#1b2230'}} />
      </div>
      {/* hinge + base */}
      <div style={{position: 'absolute', left: (W - baseW) / 2, top: lidH - W * 0.002, width: baseW, height: W * 0.036,
        borderRadius: `${W * 0.004}px ${W * 0.004}px ${W * 0.05}px ${W * 0.05}px / ${W * 0.004}px ${W * 0.004}px ${W * 0.024}px ${W * 0.024}px`,
        background: 'linear-gradient(180deg, #5b6576 0%, #3b4452 18%, #2a313c 60%, #161a21 100%)',
        boxShadow: '0 30px 60px rgba(0,0,0,0.55)'}}>
        <div style={{position: 'absolute', left: baseW / 2 - W * 0.075, top: 0, width: W * 0.15, height: W * 0.011,
          background: 'linear-gradient(180deg, #1c222b, #2f3743)', borderRadius: `0 0 ${W * 0.012}px ${W * 0.012}px`}} />
      </div>
    </div>
  );
};
