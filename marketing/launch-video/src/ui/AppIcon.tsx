import React from 'react';

// Dark-appearance app icon rebuilt from AIQuota/AppIcon.icon/Assets as strokes so
// the quota arcs can animate. Arcs: outer r=320, inner r=210, width 86, from 135°.
const OUTER = {r: 320, sweep: 210.5};
const INNER = {r: 210, sweep: 151.6};
const W = 86;

const polar = (r: number, deg: number) => {
  const a = (deg * Math.PI) / 180;
  return [512 + r * Math.cos(a), 512 + r * Math.sin(a)];
};

const Arc: React.FC<{r: number; sweep: number; stroke: string; opacity?: number}> = ({r, sweep, stroke, opacity = 1}) => {
  if (sweep <= 0.01) return null;
  const [x0, y0] = polar(r, 135);
  const [x1, y1] = polar(r, 135 + sweep);
  return <path d={`M ${x0} ${y0} A ${r} ${r} 0 ${sweep > 180 ? 1 : 0} 1 ${x1} ${y1}`} fill="none" stroke={stroke}
    strokeOpacity={opacity} strokeWidth={W} strokeLinecap="round" />;
};

const Indicator: React.FC<{r: number; sweep: number; id: string; opacity: number}> = ({r, sweep, id, opacity}) => {
  const [x, y] = polar(r, 135 + sweep);
  return (
    <g opacity={opacity}>
      <defs>
        <radialGradient id={id} cx="40%" cy="30%" r="75%">
          <stop offset="0%" stopColor="#E9D4FF" />
          <stop offset="55%" stopColor="#B062F0" />
          <stop offset="100%" stopColor="#7A2FC4" />
        </radialGradient>
      </defs>
      <circle cx={x} cy={y + 6} r={51} fill="rgba(0,0,0,0.35)" />
      <circle cx={x} cy={y} r={51} fill={`url(#${id})`} />
      <ellipse cx={x - 8} cy={y - 22} rx={26} ry={12} fill="rgba(255,255,255,0.45)" />
    </g>
  );
};

export const AppIcon: React.FC<{size: number; progress?: number}> = ({size, progress = 1}) => {
  const p = Math.max(0, Math.min(1, progress));
  return (
    <div style={{width: size, height: size, borderRadius: size * 0.2237, overflow: 'hidden', position: 'relative',
      background: 'linear-gradient(180deg, #1d1633 0%, #110c21 100%)',
      boxShadow: `inset 0 ${size * 0.004}px 0 rgba(255,255,255,0.14), 0 ${size * 0.05}px ${size * 0.14}px rgba(30,20,50,0.28), 0 ${size * 0.01}px ${size * 0.03}px rgba(30,20,50,0.18)`}}>
      <svg viewBox="0 0 1024 1024" width={size} height={size}>
        <Arc r={OUTER.r} sweep={270} stroke="#767680" opacity={0.18} />
        <Arc r={INNER.r} sweep={270} stroke="#767680" opacity={0.18} />
        <Arc r={OUTER.r} sweep={OUTER.sweep * p} stroke="#983EFF" />
        <Arc r={INNER.r} sweep={INNER.sweep * p} stroke="#C04DFF" />
        <Indicator r={OUTER.r} sweep={OUTER.sweep * p} id="io" opacity={p} />
        <Indicator r={INNER.r} sweep={INNER.sweep * p} id="ii" opacity={p} />
        <path d="M512 437 C526 509 535 518 607 532 C535 546 526 555 512 627 C498 555 489 546 417 532 C489 518 498 509 512 437Z"
          fill="#F7F2FF" opacity={0.92} />
      </svg>
    </div>
  );
};
