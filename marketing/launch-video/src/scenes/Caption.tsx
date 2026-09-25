import React from 'react';
import {easeOut, ramp} from '../anim';
import {stage, theme} from '../theme';

// Blur-in / blur-out headline. Frames are absolute composition frames.
export const Caption: React.FC<{frame: number; inAt: number; outAt: number; children: React.ReactNode; style?: React.CSSProperties}> = ({frame, inAt, outAt, children, style}) => {
  const a = ramp(frame, inAt, inAt + 36, easeOut);
  const b = ramp(frame, outAt, outAt + 24);
  const o = a * (1 - b);
  if (o <= 0) return null;
  return (
    <div style={{position: 'absolute', fontFamily: theme.font, fontWeight: 700, color: stage.ink,
      letterSpacing: '-0.025em', lineHeight: 1.02, opacity: o,
      filter: `blur(${(1 - a) * 14 + b * 10}px)`, transform: `translateY(${(1 - a) * 28 - b * 20}px)`, ...style}}>
      {children}
    </div>
  );
};
