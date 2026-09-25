import React from 'react';
import {staticFile} from 'remotion';

// Tinted service logo via CSS mask so it can take the gauge color.
export const ServiceLogo: React.FC<{service: 'codex' | 'claude'; size: number; color: string}> = ({service, size, color}) => {
  const url = `url(${staticFile(service === 'codex' ? 'logo-openai.svg' : 'logo-claude.svg')})`;
  return (
    <div style={{width: size, height: size, backgroundColor: color, WebkitMaskImage: url, maskImage: url,
      WebkitMaskSize: 'contain', maskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskRepeat: 'no-repeat',
      WebkitMaskPosition: 'center', maskPosition: 'center'}} />
  );
};

export const RefreshGlyph: React.FC<{size: number; color: string; weight?: number}> = ({size, color, weight = 2}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round">
    <path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3" />
    <path d="M18 3.5v4h-4" />
  </svg>
);

export const GearGlyph: React.FC<{size: number; color: string}> = ({size, color}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.8} strokeLinejoin="round">
    <path d="M10.3 2.8h3.4l.5 2.4 1.7.9 2.2-1 2.4 2.4-1 2.2.9 1.7 2.4.5v3.4l-2.4.5-.9 1.7 1 2.2-2.4 2.4-2.2-1-1.7.9-.5 2.4h-3.4l-.5-2.4-1.7-.9-2.2 1-2.4-2.4 1-2.2-.9-1.7-2.4-.5v-3.4l2.4-.5.9-1.7-1-2.2 2.4-2.4 2.2 1 1.7-.9z" />
    <circle cx="12" cy="12" r="3.3" />
  </svg>
);

export const ChevronBadge: React.FC<{size: number}> = ({size}) => (
  <svg width={size} height={size} viewBox="0 0 24 24">
    <circle cx="12" cy="12" r="12" fill="rgba(118,118,128,0.36)" />
    <path d="M10 7l5 5-5 5" fill="none" stroke="rgba(235,235,245,0.7)" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const WifiGlyph: React.FC<{size: number; color: string}> = ({size, color}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color}>
    <path d="M12 20.5l3-3.6a4.6 4.6 0 0 0-6 0z" />
    <path d="M12 12.2a8 8 0 0 1 5.3 2l1.6-1.9a10.5 10.5 0 0 0-13.8 0l1.6 1.9a8 8 0 0 1 5.3-2z" />
    <path d="M12 7.2c3.3 0 6.3 1.2 8.6 3.2l1.6-1.9A15.4 15.4 0 0 0 12 4.7 15.4 15.4 0 0 0 1.8 8.5l1.6 1.9c2.3-2 5.3-3.2 8.6-3.2z" />
  </svg>
);

export const BatteryGlyph: React.FC<{width: number; color: string}> = ({width, color}) => (
  <svg width={width} height={width * 0.48} viewBox="0 0 27 13">
    <rect x="0.5" y="0.5" width="23" height="12" rx="3.6" fill="none" stroke={color} strokeOpacity={0.45} />
    <rect x="2" y="2" width="20" height="9" rx="2.2" fill={color} />
    <path d="M25 4.4v4.2a2 2 0 0 0 0-4.2z" fill={color} fillOpacity={0.45} />
  </svg>
);

export const Cursor: React.FC<{size: number}> = ({size}) => (
  <svg width={size} height={size * 1.5} viewBox="0 0 20 30" style={{filter: 'drop-shadow(0 2px 3px rgba(0,0,0,0.45))'}}>
    <path d="M2 2v21.5l5.2-5 3.6 8.4 3.6-1.5-3.5-8.3h7.3z" fill="#000" stroke="#fff" strokeWidth={1.6} strokeLinejoin="round" />
  </svg>
);

export const SparkGlyph: React.FC<{size: number; color: string}> = ({size, color}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color}>
    <path d="M10 3c.9 4.6 1.6 5.3 6.2 6.2C11.6 10.1 10.9 10.8 10 15.4 9.1 10.8 8.4 10.1 3.8 9.2 8.4 8.3 9.1 7.6 10 3z" />
    <path d="M18 13c.4 2.1.7 2.4 2.8 2.8-2.1.4-2.4.7-2.8 2.8-.4-2.1-.7-2.4-2.8-2.8 2.1-.4 2.4-.7 2.8-2.8z" />
  </svg>
);
