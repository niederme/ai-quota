import React from 'react';

export const IPHONE_SCREEN = {w: 420, h: 912};

// Rounded-rect path in SVG coordinates.
function rrect(x: number, y: number, w: number, h: number, r: number) {
  return `M${x + r},${y}H${x + w - r}A${r},${r} 0 0 1 ${x + w},${y + r}V${y + h - r}A${r},${r} 0 0 1 ${x + w - r},${y + h}` +
    `H${x + r}A${r},${r} 0 0 1 ${x},${y + h - r}V${y + r}A${r},${r} 0 0 1 ${x + r},${y}Z`;
}

// Drawn iPhone Air (Cloud White). `width` is the device width in stage px.
//
// The frame + bezel are an overlay drawn *above* the screen with a rounded hole cut
// out, like a real mockup bezel. With the bezel underneath, Chrome's compositor
// could treat the (opaque) screen layer as covering it and skip drawing it, then
// the rounded mask exposed the stage at the screen corners — flickering frame to frame.
export const IPhoneAir: React.FC<{width: number; children: React.ReactNode}> = ({width: W, children}) => {
  const bezel = W * 0.036;
  const sw = W - bezel * 2;
  const sh = (sw * IPHONE_SCREEN.h) / IPHONE_SCREEN.w;
  const H = sh + bezel * 2;
  const rOuter = W * 0.175;
  const rInner = W * 0.168;
  const rim = W * 0.008;
  const rScreen = W * 0.14;
  const btn = (side: 'l' | 'r', top: number, h: number) => (
    <div style={{position: 'absolute', [side === 'l' ? 'left' : 'right']: -W * 0.011, top, width: W * 0.016, height: h,
      borderRadius: W * 0.01, background: 'linear-gradient(90deg, #bfbfbc, #f2f2f0, #bfbfbc)'}} />
  );
  const outer = rrect(0, 0, W, H, rOuter);
  const inner = rrect(rim, rim, W - rim * 2, H - rim * 2, rInner);
  const hole = rrect(bezel, bezel, sw, sh, rScreen);
  const id = `frame-${Math.round(W)}`;
  return (
    <div style={{position: 'relative', width: W, height: H}}>
      {btn('l', H * 0.2, H * 0.045)}
      {btn('l', H * 0.28, H * 0.08)}
      {btn('l', H * 0.38, H * 0.08)}
      {btn('r', H * 0.3, H * 0.12)}
      {btn('r', H * 0.62, H * 0.07)}
      {/* shadow + black backing */}
      <div style={{position: 'absolute', inset: 0, borderRadius: rOuter, background: '#000',
        boxShadow: '0 34px 70px rgba(30,20,50,0.22), 0 8px 18px rgba(30,20,50,0.10)'}} />
      {/* screen: clipped by an explicit clip-path shape (border-radius + overflow gets
          dropped by the compositor when screen content is composited); the overlay
          above covers any edge antialiasing */}
      <div style={{position: 'absolute', left: bezel, top: bezel, width: sw, height: sh, background: '#000',
        clipPath: `path('${rrect(0, 0, sw, sh, rScreen + rim)}')`}}>
        <div style={{transform: `scale(${sw / IPHONE_SCREEN.w})`, transformOrigin: '0 0'}}>{children}</div>
      </div>
      {/* frame + bezel overlay with the screen hole cut out */}
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{position: 'absolute', inset: 0, overflow: 'visible'}}>
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#ffffff" />
            <stop offset="0.28" stopColor="#e4e4e1" />
            <stop offset="0.7" stopColor="#d2d2ce" />
            <stop offset="1" stopColor="#f7f7f5" />
          </linearGradient>
          <linearGradient id={`${id}-glare`} x1="0" y1="0" x2="1" y2="0.6">
            <stop offset="0" stopColor="rgba(255,255,255,0.07)" />
            <stop offset="0.35" stopColor="rgba(255,255,255,0)" />
          </linearGradient>
        </defs>
        <path d={outer + inner} fill={`url(#${id})`} fillRule="evenodd" stroke="rgba(0,0,0,0.10)" strokeWidth={1} />
        <path d={inner + hole} fill="#000" fillRule="evenodd" />
        <path d={hole} fill={`url(#${id}-glare)`} />
        <rect x={W / 2 - sw * 0.155} y={bezel + sw * 0.027} width={sw * 0.31} height={sw * 0.088} rx={sw * 0.044} fill="#000" />
      </svg>
    </div>
  );
};
