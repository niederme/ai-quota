import React from 'react';
import {easeOut, ramp} from '../anim';
import {stage, theme} from '../theme';
import {AppIcon} from '../ui/AppIcon';

const rise = (frame: number, at: number) => {
  const t = ramp(frame, at, at + 40, easeOut);
  return {opacity: t, transform: `translateY(${(1 - t) * 24}px)`, filter: `blur(${(1 - t) * 8}px)`};
};

export const EndLockup: React.FC<{frame: number; start: number}> = ({frame, start}) => {
  if (frame < start) return null;
  return (
    <div style={{position: 'absolute', left: 1330, top: 270, width: 440, display: 'flex', flexDirection: 'column',
      alignItems: 'center', fontFamily: theme.font, color: stage.ink}}>
      <div style={rise(frame, start)}>
        <AppIcon size={200} progress={ramp(frame, start + 10, start + 80, easeOut)} />
      </div>
      <div style={{...rise(frame, start + 22), marginTop: 44, fontSize: 112, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1}}>
        AIQuota
      </div>
      <div style={{...rise(frame, start + 38), marginTop: 20, fontSize: 44, fontWeight: 500, color: stage.inkSecondary, letterSpacing: '-0.01em'}}>
        macOS &amp; iOS
      </div>
    </div>
  );
};
