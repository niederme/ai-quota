import React from 'react';
import {AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {agentAt} from './agent';
import {easeInOut, easeOut, keyframes, ramp, type Ease, type Key} from './anim';
import {cameraAt, type Cam, type Shot} from './camera';
import {IPhoneAir} from './devices/IPhoneAir';
import {macGeometry, MacBookAir} from './devices/MacBookAir';
import {Caption} from './scenes/Caption';
import {EndLockup} from './scenes/EndLockup';
import {stage} from './theme';
import {BEATS, usageAt} from './timeline';
import {IOSOverview} from './ui/IOSOverview';
import {AGENT_RECT, EXTRA, MacDesktop, POPOVER_RECT} from './ui/MacDesktop';

// Stage is authored in a 1920×1080 design space and scaled to the output size.
const STAGE = {w: 1920, h: 1080};
const B = BEATS;
const HOME: Cam = {x: 960, y: 540, z: 1};

// Snappy ease for whip zooms: slow start, fast middle, long settle.
const whip: Ease = (t) => (t < 0.5 ? 8 * t ** 4 : 1 - Math.pow(-2 * t + 2, 4) / 2);

type Placement = {cx: Key[]; cy: Key[]; w: Key[]};
const place = (frame: number, p: Placement) => ({
  cx: keyframes(frame, p.cx, easeInOut), cy: keyframes(frame, p.cy, easeInOut), w: keyframes(frame, p.w, easeInOut),
});

const MAC: Placement = {
  cx: [[B.caption1, 960], [B.caption1 + 100, 700], [B.caption2 - 40, 690], [B.caption2 + 40, 420], [B.endCard, 420], [B.endCard + 100, 660]],
  cy: [[B.caption1, 540], [B.caption1 + 100, 560], [B.endCard + 100, 560]],
  w: [[B.caption1, 1200], [B.caption1 + 100, 1060], [B.caption2 + 40, 1000], [B.endCard, 1000], [B.endCard + 100, 900]],
};
const PHONE: Placement = {
  cx: [[B.phoneIn, 1480], [B.phoneIn + 90, 1400], [B.caption2, 1370], [B.endCard, 1370], [B.endCard + 100, 1178]],
  cy: [[B.phoneIn, 1650], [B.phoneIn + 90, 590], [B.caption2, 570], [B.endCard, 570], [B.endCard + 100, 640]],
  w: [[B.phoneIn, 330], [B.endCard, 330], [B.endCard + 100, 250]],
};

// Mac screen point → world point for the current placement.
function macPoint(mac: {cx: number; cy: number; w: number}, sx: number, sy: number) {
  const g = macGeometry(mac.w);
  return {x: mac.cx - mac.w / 2 + g.side + sx * g.scale, y: mac.cy - g.height / 2 + g.top + sy * g.scale};
}

// Screen y the close-up camera watches: the composer while typing, then the newest line.
function agentWatchY(frame: number) {
  let sum = 0;
  const n = 24;
  for (let k = 0; k < n; k++) {
    const f = Math.max(0, frame - k);
    const a = agentAt(f);
    const y = f < B.promptSent ? AGENT_RECT.y + 500 : AGENT_RECT.y + 62 + (a.focusY - a.scroll) - 70;
    sum += Math.max(AGENT_RECT.y + 240, Math.min(AGENT_RECT.y + 500, y));
  }
  return sum / n;
}

const Placed: React.FC<{cx: number; cy: number; children: React.ReactNode; style?: React.CSSProperties}> = ({cx, cy, children, style}) => (
  <div style={{position: 'absolute', left: cx, top: cy, transform: 'translate(-50%, -50%)', ...style}}>{children}</div>
);

export const LaunchVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const {width} = useVideoConfig();
  const usage = usageAt(frame);
  const mac = place(frame, MAC);
  const phone = place(frame, PHONE);

  const shots: Shot[] = [
    {at: 0, cam: (f) => {
      const p = macPoint(place(f, MAC), AGENT_RECT.x + 380 + f * 0.08, agentWatchY(f));
      return {x: p.x, y: p.y, z: 2.4 - 0.25 * ramp(f, 0, B.zoomOut)};
    }},
    {at: B.zoomOut, blend: 64, ease: whip, cam: () => HOME},
    {at: B.click + 8, blend: 56, ease: easeOut, cam: (f) => {
      const m = place(f, MAC);
      const p = macPoint(m, POPOVER_RECT.x + POPOVER_RECT.w / 2, POPOVER_RECT.y + POPOVER_RECT.h / 2);
      return {x: p.x - 250 / 1.9, y: p.y + 10, z: 1.9};
    }},
    {at: B.caption1 - 10, blend: 80, ease: easeInOut, cam: () => HOME},
    {at: B.phoneIn + 40, blend: 140, ease: easeInOut, cam: () => ({x: 1010, y: 548, z: 1.07})},
    {at: B.caption2 - 40, blend: 70, ease: easeInOut, cam: (f) => {
      const p = place(f, PHONE);
      return {x: p.cx - 330 / 1.55, y: p.cy + 10, z: 1.55};
    }},
    {at: B.notify + 10, blend: 90, ease: easeInOut, cam: (f) => {
      const p = place(f, PHONE);
      return {x: p.cx - 360 / 1.8, y: p.cy + 70, z: 1.8};
    }},
    {at: B.endCard - 20, blend: 110, ease: easeInOut, cam: () => HOME},
  ];
  const cam = cameraAt(frame, shots, easeInOut);

  // Mac interaction: cursor glides to the menu bar extra, clicks, popover opens.
  const cursorT = ramp(frame, B.zoomOut + 20, B.click - 8);
  const cursor = {
    x: 640 + (EXTRA.x - 4 - 640) * cursorT,
    y: 430 + (EXTRA.y - 4 - 430) * cursorT,
    opacity: ramp(frame, B.zoomOut + 10, B.zoomOut + 30) * (1 - ramp(frame, B.click + 50, B.click + 80)),
    press: keyframes(frame, [[B.click - 4, 0], [B.click, 1], [B.click + 6, 0]]),
  };
  const popover = ramp(frame, B.macOpen, B.macOpen + 34, easeOut);

  const macFade = keyframes(frame, [[B.caption2 - 40, 0], [B.caption2 + 30, 1], [B.endCard, 1], [B.endCard + 70, 0]], easeInOut);
  const notification = keyframes(frame, [[B.notify, 0], [B.notify + 30, 1], [B.reset + 10, 1], [B.reset + 40, 0]], easeInOut);
  const claudeGlow = keyframes(frame, [[B.peak - 30, 0], [B.peak, 1], [B.reset + 10, 1], [B.reset + 60, 0]], easeInOut);
  const phoneRotY = keyframes(frame, [[B.phoneIn, -38], [B.phoneIn + 100, -10], [B.caption2 - 40, -6], [B.caption2 + 30, 0]], easeOut);
  const phoneRotZ = keyframes(frame, [[B.phoneIn, 9], [B.phoneIn + 100, 0]], easeOut);

  const macShadowW = mac.w * 1.25;
  const macH = macGeometry(mac.w).height;

  return (
    <AbsoluteFill style={{background: stage.bg, overflow: 'hidden'}}>
      <Audio src={staticFile('soundtrack.wav')} />
      <div style={{position: 'absolute', width: STAGE.w, height: STAGE.h, transform: `scale(${width / STAGE.w})`, transformOrigin: '0 0', overflow: 'hidden'}}>
        <div style={{position: 'absolute', inset: 0, background: `
          radial-gradient(60% 55% at 50% 0%, #ffffff, transparent 70%),
          linear-gradient(180deg, #FAFAFB 0%, ${stage.bg} 60%, #ECEBEF 100%)`}} />

        <div style={{position: 'absolute', left: 0, top: 0, width: STAGE.w, height: STAGE.h,
          transform: `translate(${STAGE.w / 2}px, ${STAGE.h / 2}px) scale(${cam.z}) translate(${-cam.x}px, ${-cam.y}px)`, transformOrigin: '0 0'}}>
          {/* soft brand tint behind the devices; warms toward red at the critical peak */}
          <div style={{position: 'absolute', left: phone.cx - 700, top: phone.cy - 600, width: 1400, height: 1200,
            background: `radial-gradient(closest-side, rgba(${Math.round(191 + 64 * claudeGlow)},${Math.round(90 - 20 * claudeGlow)},${Math.round(242 - 180 * claudeGlow)},${0.10 + 0.06 * claudeGlow}), transparent)`,
            opacity: frame >= B.phoneIn ? 1 : 0}} />

          <div style={{opacity: 1 - 0.8 * macFade, filter: macFade > 0.01 ? `blur(${macFade * 5}px)` : undefined}}>
            <div style={{position: 'absolute', left: mac.cx - macShadowW / 2, top: mac.cy + macH / 2 - mac.w * 0.03, width: macShadowW, height: mac.w * 0.08,
              background: 'radial-gradient(closest-side, rgba(30,25,45,0.30), transparent)', filter: 'blur(6px)'}} />
            <Placed cx={mac.cx} cy={mac.cy}>
              <MacBookAir width={mac.w}>
                <MacDesktop frame={frame} usage={usage} popover={popover} cursor={cursor} />
              </MacBookAir>
            </Placed>
          </div>

          {frame >= B.phoneIn && (
            <Placed cx={phone.cx} cy={phone.cy} style={{transform: `translate(-50%, -50%) perspective(1800px) rotateY(${phoneRotY}deg) rotateZ(${phoneRotZ}deg)`}}>
              <IPhoneAir width={phone.w}>
                <IOSOverview usage={usage} claudeGlow={claudeGlow} notification={notification} />
              </IPhoneAir>
            </Placed>
          )}
        </div>

        <Caption frame={frame} inAt={B.caption1 + 20} outAt={B.phoneIn + 10} style={{left: 1290, top: 380, fontSize: 118}}>
          Know your<br />limits.
        </Caption>
        <Caption frame={frame} inAt={B.caption2 + 10} outAt={B.endCard - 30} style={{left: 130, top: 400, fontSize: 104}}>
          before they<br />break your flow.
        </Caption>

        <EndLockup frame={frame} start={B.endCard + 50} />
      </div>
    </AbsoluteFill>
  );
};

