import React from 'react';
import {AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {agentAt, MAC_SESSION, PHONE_SESSION, type Session} from './agent';
import {easeInOut, easeOut, keyframes, ramp, type Ease, type Key} from './anim';
import {cameraAt, type Cam, type Shot} from './camera';
import {IPHONE_SCREEN, IPhoneAir} from './devices/IPhoneAir';
import {macGeometry, MacBookAir} from './devices/MacBookAir';
import {Caption} from './scenes/Caption';
import {EndLockup} from './scenes/EndLockup';
import {stage} from './theme';
import {BEATS, usageAt} from './timeline';
import {AGENT_RECT, EXTRA, MacDesktop, POPOVER_RECT} from './ui/MacDesktop';
import {PhoneScreen} from './ui/PhoneScreen';

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

// Taglines live in world space behind the devices; devices never sit under text
// except by passing in front of it.
const MAC: Placement = {
  cx: [[B.caption1 - 20, 960], [B.caption1 + 70, 540], [B.phoneIn, 560], [B.phoneIn + 90, 600], [B.reset - 40, 600], [B.reset, 380], [B.endCard + 10, 380], [B.endCard + 100, 660]],
  cy: [[B.caption1 - 20, 540], [B.caption1 + 70, 560], [B.phoneIn + 90, 520], [B.endCard, 520], [B.endCard + 100, 560]],
  w: [[B.caption1 - 20, 1200], [B.caption1 + 70, 860], [B.phoneIn + 90, 760], [B.endCard, 760], [B.endCard + 100, 900]],
};
const PHONE: Placement = {
  cx: [[B.phoneIn, 1300], [B.phoneIn + 90, 1180], [B.reset - 40, 1180], [B.reset + 40, 1300], [B.endCard, 1300], [B.endCard + 100, 1178]],
  cy: [[B.phoneIn, 1700], [B.phoneIn + 90, 560], [B.endCard, 560], [B.endCard + 100, 640]],
  w: [[B.phoneIn, 400], [B.endCard, 400], [B.endCard + 100, 250]],
};

// Mac screen point → world point for the current placement.
function macPoint(mac: {cx: number; cy: number; w: number}, sx: number, sy: number) {
  const g = macGeometry(mac.w);
  return {x: mac.cx - mac.w / 2 + g.side + sx * g.scale, y: mac.cy - g.height / 2 + g.top + sy * g.scale};
}
// iPhone screen point → world point.
function phonePoint(p: {cx: number; cy: number; w: number}, sx: number, sy: number) {
  const bezel = p.w * 0.036;
  const scale = (p.w - bezel * 2) / IPHONE_SCREEN.w;
  const h = (p.w - bezel * 2) * (IPHONE_SCREEN.h / IPHONE_SCREEN.w) + bezel * 2;
  return {x: p.cx - p.w / 2 + bezel + sx * scale, y: p.cy - h / 2 + bezel + sy * scale};
}

// Transcript y (screen points) the close-up watches: composer while typing, else the newest line.
function watchY(s: Session, frame: number, top: number, composerY: number, lo: number, hi: number) {
  let sum = 0;
  const n = 24;
  for (let k = 0; k < n; k++) {
    const f = Math.max(0, frame - k);
    const a = agentAt(s, f);
    const y = a.composer ? composerY : top + (a.focusY - a.scroll) - 80;
    sum += Math.max(lo, Math.min(hi, y));
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
      const y = watchY(MAC_SESSION, f, AGENT_RECT.y + 62, AGENT_RECT.y + 520, AGENT_RECT.y + 240, AGENT_RECT.y + 500);
      const p = macPoint(place(f, MAC), AGENT_RECT.x + 380 + f * 0.05, y);
      return {x: p.x, y: p.y, z: 2.4 - 0.3 * ramp(f, 0, B.zoomOut)};
    }},
    {at: B.zoomOut, blend: 64, ease: whip, cam: () => HOME},
    {at: B.click + 8, blend: 56, ease: easeOut, cam: (f) => {
      const p = macPoint(place(f, MAC), POPOVER_RECT.x + POPOVER_RECT.w / 2, POPOVER_RECT.y + POPOVER_RECT.h / 2);
      return {x: p.x - 250 / 1.9, y: p.y + 10, z: 1.9};
    }},
    {at: B.caption1 - 10, blend: 80, ease: easeInOut, cam: () => HOME},
    {at: B.phoneIn, blend: 90, ease: easeInOut, cam: () => ({x: 1040, y: 548, z: 1.06})},
    {at: B.phonePrompt - 30, blend: 60, ease: easeInOut, cam: (f) => {
      const y = watchY(PHONE_SESSION, f, 128, 780, 330, 640);
      const p = phonePoint(place(f, PHONE), 210, y);
      return {x: p.x, y: p.y, z: 1.45};
    }},
    {at: B.notify, blend: 36, ease: easeOut, cam: (f) => {
      const p = phonePoint(place(f, PHONE), 210, 300);
      return {x: p.x, y: p.y, z: 1.6};
    }},
    {at: B.tap + 24, blend: 60, ease: easeInOut, cam: (f) => {
      const p = phonePoint(place(f, PHONE), 210, 560);
      return {x: p.x, y: p.y, z: 1.55};
    }},
    {at: B.reset - 6, blend: 44, ease: whip, cam: () => ({x: 980, y: 545, z: 1.02})},
    {at: B.endCard, blend: 100, ease: easeInOut, cam: () => HOME},
  ];
  const cam = cameraAt(frame, shots, easeInOut);

  // Mac interaction: cursor glides to the menu bar extra, clicks, popover opens.
  const cursorT = ramp(frame, B.zoomOut + 30, B.click - 8);
  const cursor = {
    x: 640 + (EXTRA.x - 4 - 640) * cursorT,
    y: 430 + (EXTRA.y - 4 - 430) * cursorT,
    opacity: ramp(frame, B.zoomOut + 20, B.zoomOut + 40) * (1 - ramp(frame, B.click + 50, B.click + 80)),
    press: keyframes(frame, [[B.click - 4, 0], [B.click, 1], [B.click + 6, 0]]),
  };
  const popover = ramp(frame, B.macOpen, B.macOpen + 34, easeOut);

  // Mac recedes behind the phone, clears out for the second tagline, returns for the end card.
  const macBack = keyframes(frame, [[B.phoneIn, 0], [B.phoneIn + 90, 1], [B.endCard, 1], [B.endCard + 90, 0]], easeInOut);
  const macGone = keyframes(frame, [[B.reset - 40, 0], [B.reset, 1], [B.endCard + 10, 1], [B.endCard + 80, 0]], easeInOut);
  const claudeGlow = keyframes(frame, [[B.peak - 30, 0], [B.peak, 1], [B.reset + 10, 1], [B.reset + 60, 0]], easeInOut);
  const phoneRotY = keyframes(frame, [[B.phoneIn, -34], [B.phoneIn + 100, 0]], easeOut);
  const phoneRotZ = keyframes(frame, [[B.phoneIn, 8], [B.phoneIn + 100, 0]], easeOut);

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
          {/* Taglines: background layer, behind every device. */}
          <Caption frame={frame} inAt={B.caption1 + 20} outAt={B.phoneIn + 60} style={{left: 1080, top: 380, fontSize: 150}}>
            Know your<br />limits.
          </Caption>
          <Caption frame={frame} inAt={B.caption2 + 4} outAt={B.endCard - 14} style={{left: 110, top: 390, fontSize: 118}}>
            before they<br />break your flow.
          </Caption>

          {/* soft brand tint behind the phone; warms toward red at the critical peak */}
          <div style={{position: 'absolute', left: phone.cx - 700, top: phone.cy - 600, width: 1400, height: 1200, opacity: frame >= B.phoneIn ? 1 : 0,
            background: `radial-gradient(closest-side, rgba(${Math.round(191 + 64 * claudeGlow)},${Math.round(90 - 20 * claudeGlow)},${Math.round(242 - 180 * claudeGlow)},${0.10 + 0.06 * claudeGlow}), transparent)`}} />

          <div style={{opacity: (1 - 0.15 * macBack) * (1 - macGone), filter: macBack > 0.01 ? `blur(${macBack * 2.5}px)` : undefined}}>
            <div style={{position: 'absolute', left: mac.cx - mac.w * 0.625, top: mac.cy + macH / 2 - mac.w * 0.03, width: mac.w * 1.25, height: mac.w * 0.08,
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
                <PhoneScreen frame={frame} usage={usage} claudeGlow={claudeGlow} />
              </IPhoneAir>
            </Placed>
          )}
        </div>

        <EndLockup frame={frame} start={B.endCard + 60} />
      </div>
    </AbsoluteFill>
  );
};
