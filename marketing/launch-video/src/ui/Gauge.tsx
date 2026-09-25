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

// Tiny menu bar glyph: single ring with fill.
export const MiniGauge: React.FC<{value: number; size: number; color: string}> = ({value, size, color}) => {
  const ring = size * 0.16;
  const r = (size - ring) / 2;
  const c = 2 * Math.PI * r;
  const d = (fill: number) => `${0.75 * c * fill} ${c}`;
  return (
    <svg width={size} height={size}>
      <g transform={`rotate(135 ${size / 2} ${size / 2})`} fill="none" strokeWidth={ring} strokeLinecap="round">
        <circle cx={size / 2} cy={size / 2} r={r} stroke="rgba(255,255,255,0.28)" strokeDasharray={d(1)} />
        <circle cx={size / 2} cy={size / 2} r={r} stroke={color} strokeDasharray={d(value / 100)} />
      </g>
    </svg>
  );
};
