import React from 'react';
import {MAC_SCREEN} from '../ui/MacDesktop';

// Rect path with only the top corners rounded.
const topRounded = (w: number, h: number, r: number) =>
  `M0,${h}V${r}A${r},${r} 0 0 1 ${r},0H${w - r}A${r},${r} 0 0 1 ${w},${r}V${h}Z`;

// Drawn MacBook Air (Silver). `width` is the lid width in stage px.
export const macGeometry = (W: number) => {
  const side = W * 0.021;
  const top = W * 0.024;
  const bottom = W * 0.03;
  const sw = W - side * 2;
  const sh = (sw * MAC_SCREEN.h) / MAC_SCREEN.w;
  return {side, top, bottom, sw, sh, lidH: top + sh + bottom, scale: sw / MAC_SCREEN.w, height: top + sh + bottom + W * 0.034};
};

export const MacBookAir: React.FC<{width: number; children: React.ReactNode}> = ({width: W, children}) => {
  const g = macGeometry(W);
  const baseW = W * 1.13;
  return (
    <div style={{position: 'relative', width: W, height: g.height}}>
      <div style={{position: 'absolute', left: 0, top: 0, width: W, height: g.lidH,
        borderRadius: `${W * 0.03}px ${W * 0.03}px ${W * 0.012}px ${W * 0.012}px`,
        background: '#0a0a0c', boxShadow: `inset 0 0 0 ${W * 0.0032}px #c9cbcf, inset 0 0 0 ${W * 0.0048}px #1a1a1c`}}>
        {/* Explicit clip-path: border-radius + overflow can be dropped by the compositor
            when screen content is composited (backdrop-filter), leaking square corners. */}
        <div style={{position: 'absolute', left: g.side, top: g.top, width: g.sw, height: g.sh,
          clipPath: `path('${topRounded(g.sw, g.sh, W * 0.011)}')`}}>
          <div style={{transform: `scale(${g.scale})`, transformOrigin: '0 0'}}>{children}</div>
          <div style={{position: 'absolute', inset: 0, background: 'linear-gradient(115deg, rgba(255,255,255,0.05) 0%, transparent 38%)'}} />
        </div>
        <div style={{position: 'absolute', left: W / 2 - W * 0.05, top: g.top - 1, width: W * 0.1, height: W * 0.0215,
          background: '#0a0a0c', borderRadius: `0 0 ${W * 0.008}px ${W * 0.008}px`}} />
      </div>
      <div style={{position: 'absolute', left: (W - baseW) / 2, top: g.lidH - W * 0.002, width: baseW, height: W * 0.036,
        borderRadius: `${W * 0.004}px ${W * 0.004}px ${W * 0.05}px ${W * 0.05}px / ${W * 0.004}px ${W * 0.004}px ${W * 0.024}px ${W * 0.024}px`,
        background: 'linear-gradient(180deg, #f2f3f5 0%, #d9dbde 22%, #c3c6cb 65%, #9da1a8 100%)'}}>
        <div style={{position: 'absolute', left: baseW / 2 - W * 0.075, top: 0, width: W * 0.15, height: W * 0.011,
          background: 'linear-gradient(180deg, #a9adb3, #cfd2d6)', borderRadius: `0 0 ${W * 0.012}px ${W * 0.012}px`}} />
      </div>
    </div>
  );
};
