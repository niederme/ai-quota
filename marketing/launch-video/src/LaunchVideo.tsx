import React from 'react';
import {AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {easeInOut, easeOut, keyframes, ramp} from './anim';
import {cameraFor, MAC, PHONE, place} from './direction';
import {IPhoneAir} from './devices/IPhoneAir';
import {macGeometry, MacBookAir} from './devices/MacBookAir';
import {Caption} from './scenes/Caption';
import {EndLockup} from './scenes/EndLockup';
import {stage} from './theme';
import {BEATS, usageAt} from './timeline';
import {EXTRA, MacDesktop} from './ui/MacDesktop';
import {PhoneScreen} from './ui/PhoneScreen';

// Stage is authored in a 1920×1080 design space and scaled to the output size.
const STAGE = {w: 1920, h: 1080};
const B = BEATS;

const Placed: React.FC<{cx: number; cy: number; children: React.ReactNode; style?: React.CSSProperties}> = ({cx, cy, children, style}) => (
  <div style={{position: 'absolute', left: cx, top: cy, transform: 'translate(-50%, -50%)', ...style}}>{children}</div>
);

export const LaunchVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const {width} = useVideoConfig();
  const usage = usageAt(frame);
  const mac = place(frame, MAC);
  const phone = place(frame, PHONE);

  const cam = cameraFor(frame);

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
            Know your<br />limits
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
