import React from 'react';
import {gaugeColor, type Window} from '../timeline';
import {theme} from '../theme';
import {ServiceLogo} from './Glyphs';

// Dual-ring gauge matching CircularGaugeView / OverviewView: 270° arcs from 135°,
// outer ring = 5h, inner ring = 7d. Geometry is in points at `size`.
export const Gauge: React.FC<{
  service: 'codex' | 'claude';
  usage: Window;
  size: number;
  ring: number;
  gap?: number;
  reveal?: number; // 0..1 fill-in multiplier
  labelScale?: number;
  glow?: number;
}> = ({service, usage, size, ring, gap = 4, reveal = 1, labelScale = 1, glow = 0}) => {
  const worst = Math.max(usage.h5, usage.d7);
  const color = gaugeColor(worst);
  const outerR = (size - ring) / 2;
  const innerR = outerR - ring - gap;
  const arc = (r: number, fill: number, stroke: string, opacity = 1) => {
    const c = 2 * Math.PI * r;
    return (
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={stroke} strokeOpacity={opacity}
        strokeWidth={ring} strokeLinecap="round"
        strokeDasharray={`${0.75 * c * Math.max(0.0001, fill)} ${c}`}
        transform={`rotate(135 ${size / 2} ${size / 2})`} />
    );
  };
  const f = (n: number) => `${Math.round(n)}%`;
  return (
    <div style={{position: 'relative', width: size, height: size}}>
      <svg width={size} height={size} style={{position: 'absolute', inset: 0, overflow: 'visible',
        filter: glow > 0 ? `drop-shadow(0 0 ${12 * glow}px ${color})` : undefined}}>
        {arc(outerR, 1, theme.track)}
        {arc(innerR, 1, theme.track)}
        {arc(outerR, (usage.h5 / 100) * reveal, color)}
        {arc(innerR, (usage.d7 / 100) * reveal, color, 0.6)}
      </svg>
      <div style={{position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center',
        justifyContent: 'center', paddingBottom: size * 0.07, fontFamily: theme.font, fontVariantNumeric: 'tabular-nums'}}>
        <ServiceLogo service={service} size={size * 0.2 * labelScale} color={color} />
        <div style={{marginTop: size * 0.05, fontSize: size * 0.122 * labelScale, fontWeight: 600, color, lineHeight: 1.15}}>
          {f(usage.h5)} <span style={{fontWeight: 500, opacity: 0.85}}>5h</span>
        </div>
        <div style={{fontSize: size * 0.122 * labelScale, fontWeight: 500, color, opacity: 0.62, lineHeight: 1.15}}>
          {f(usage.d7)} 7d
        </div>
      </div>
    </div>
  );
};

// Menu bar gauge, drawn like AIQuotaKit's GaugeImageMaker: touching outer (5h) and
// inner (7d) rings, butt caps, white when healthy (amber/red near the limit), inner
// fill dimmed, and a white needle dot at the tip of the outer fill.
function menuBarColor(worst: number) {
  const remaining = 1 - worst / 100;
  if (remaining <= 0.05) return 'rgb(255,64,64)';
  if (remaining <= 0.15) return 'rgb(255,166,0)';
  return '#FFFFFF';
}

export const MenuBarGauge: React.FC<{primary: number; secondary: number; size: number}> = ({primary, secondary, size}) => {
  const lw = size * 0.12;
  const r1 = size * 0.41;
  const r2 = r1 - lw;
  const c = size / 2;
  const color = menuBarColor(Math.max(primary, secondary));
  const arc = (r: number, fill: number, stroke: string, opacity: number) => {
    const circ = 2 * Math.PI * r;
    return <circle cx={c} cy={c} r={r} fill="none" stroke={stroke} strokeOpacity={opacity} strokeWidth={lw}
      strokeDasharray={`${0.75 * circ * Math.max(0, Math.min(1, fill))} ${circ}`} transform={`rotate(135 ${c} ${c})`} />;
  };
  const tip = ((135 + 270 * Math.min(1, primary / 100)) * Math.PI) / 180;
  const warning = Math.max(primary, secondary) >= 85;
  return (
    <svg width={size} height={size}>
      {arc(r1, 1, '#FFFFFF', 0.2)}
      {arc(r2, 1, '#FFFFFF', 0.12)}
      {secondary > 0 && arc(r2, secondary / 100, color, warning ? 0.65 : 0.45)}
      {primary > 0 && arc(r1, primary / 100, color, 1)}
      {primary > 0 && <circle cx={c + r1 * Math.cos(tip)} cy={c + r1 * Math.sin(tip)} r={lw * 0.5} fill="rgba(255,255,255,0.95)" />}
    </svg>
  );
};
