import React from 'react';
import {AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {easeInOut, easeOut, keyframes, ramp, type Key} from './anim';
import {IPhoneAir} from './devices/IPhoneAir';
import {MacBookAir} from './devices/MacBookAir';
import {Caption} from './scenes/Caption';
import {EndLockup} from './scenes/EndLockup';
import {theme} from './theme';
import {BEATS, usageAt} from './timeline';
import {IOSOverview} from './ui/IOSOverview';
import {EXTRA, MacDesktop} from './ui/MacDesktop';

// Stage is authored in a 1920×1080 design space and scaled to the output size.
const STAGE = {w: 1920, h: 1080};
const B = BEATS;

type Placement = {cx: Key[]; cy: Key[]; w: Key[]};
const at = (frame: number, p: Placement) => ({
  cx: keyframes(frame, p.cx, easeInOut), cy: keyframes(frame, p.cy, easeInOut), w: keyframes(frame, p.w, easeInOut),
});

const MAC: Placement = {
  cx: [[0, 960], [B.caption1, 880], [B.caption1 + 130, 700], [B.caption2, 690], [B.caption2 + 70, 520], [B.endCard, 520], [B.endCard + 90, 660]],
  cy: [[0, 590], [B.caption1, 600], [B.caption1 + 130, 560], [B.caption2, 555], [B.caption2 + 70, 560], [B.endCard, 560], [B.endCard + 90, 560]],
  w: [[0, 1480], [B.caption1, 1600], [B.caption1 + 130, 1080], [B.caption2, 1110], [B.caption2 + 70, 1000], [B.endCard, 1000], [B.endCard + 90, 900]],
};
const PHONE: Placement = {
  cx: [[B.phoneIn, 1450], [B.caption2, 1430], [B.caption2 + 70, 1340], [B.endCard, 1340], [B.endCard + 90, 1178]],
  cy: [[B.phoneIn, 1560], [B.phoneIn + 80, 590], [B.caption2, 575], [B.caption2 + 70, 560], [B.endCard, 560], [B.endCard + 90, 640]],
  w: [[B.phoneIn, 330], [B.caption2, 336], [B.caption2 + 70, 410], [B.endCard, 410], [B.endCard + 90, 250]],
};

const Placed: React.FC<{cx: number; cy: number; children: React.ReactNode; style?: React.CSSProperties}> = ({cx, cy, children, style}) => (
  <div style={{position: 'absolute', left: cx, top: cy, transform: 'translate(-50%, -50%)', ...style}}>{children}</div>
);

export const LaunchVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const {width} = useVideoConfig();
  const usage = usageAt(frame);

  // Mac interaction: cursor glides to the menu bar extra, clicks, popover opens.
  const cursorT = ramp(frame, 0, 32);
  const cursor = {
    x: 1330 + (EXTRA.x - 1330) * cursorT,
    y: 430 + (EXTRA.y - 4 - 430) * cursorT,
    opacity: 1 - ramp(frame, 90, 120),
    press: keyframes(frame, [[32, 0], [36, 1], [42, 0]]),
  };
  const popover = ramp(frame, B.macOpen, B.macOpen + 34, easeOut);

  const mac = at(frame, MAC);
  const phone = at(frame, PHONE);
  const macDim = keyframes(frame, [[B.caption2, 0], [B.caption2 + 60, 1], [B.endCard, 1], [B.endCard + 60, 0]], easeInOut);

  const notification = keyframes(frame, [[B.notify, 0], [B.notify + 30, 1], [B.reset + 10, 1], [B.reset + 40, 0]], easeInOut);
  const claudeGlow = keyframes(frame, [[B.peak - 30, 0], [B.peak, 1], [B.reset + 10, 1], [B.reset + 60, 0]], easeInOut);

  // Stage glow follows the action.
  const glowX = keyframes(frame, [[0, 70], [B.phoneIn, 55], [B.caption2 + 60, 68], [B.endCard + 90, 45]], easeInOut);
  const glowHue = claudeGlow * (1 - ramp(frame, B.reset, B.reset + 40));

  return (
    <AbsoluteFill style={{background: theme.base, overflow: 'hidden'}}>
      <Audio src={staticFile('soundtrack.wav')} />
      <div style={{position: 'absolute', width: STAGE.w, height: STAGE.h, transform: `scale(${width / STAGE.w})`, transformOrigin: '0 0'}}>
        <div style={{position: 'absolute', inset: 0, background: `
          radial-gradient(55% 60% at ${glowX}% 42%, rgba(${Math.round(102 + 150 * glowHue)},31,${Math.round(143 - 90 * glowHue)},0.55), transparent 70%),
          radial-gradient(40% 40% at 100% 0%, rgba(191,90,242,0.18), transparent 70%),
          linear-gradient(180deg, #120a1c 0%, ${theme.base} 100%)`}} />

        <Placed cx={mac.cx} cy={mac.cy} style={{opacity: 1 - 0.7 * macDim, filter: macDim > 0.01 ? `blur(${macDim * 6}px)` : undefined}}>
          <MacBookAir width={mac.w}>
            <MacDesktop frame={frame} usage={usage} popover={popover} cursor={cursor} />
          </MacBookAir>
        </Placed>

        {frame >= B.phoneIn && (
          <Placed cx={phone.cx} cy={phone.cy}>
            <IPhoneAir width={phone.w}>
              <IOSOverview usage={usage} claudeGlow={claudeGlow} notification={notification} />
            </IPhoneAir>
          </Placed>
        )}

        <Caption frame={frame} inAt={B.caption1 + 22} outAt={B.phoneIn - 10} style={{left: 1290, top: 380, fontSize: 118}}>
          Know your<br />limits.
        </Caption>
        <Caption frame={frame} inAt={B.caption2 + 30} outAt={B.endCard - 20} style={{left: 130, top: 400, fontSize: 104}}>
          before they<br />break your flow.
        </Caption>

        <EndLockup frame={frame} start={B.endCard + 40} />

        <div style={{position: 'absolute', inset: 0, background: 'radial-gradient(120% 90% at 50% 50%, transparent 60%, rgba(0,0,0,0.45) 100%)'}} />
      </div>
    </AbsoluteFill>
  );
};
