// Where things are and where the camera looks, frame by frame. Pure, so the
// motion can be tested for smoothness without rendering.
import {agentAt, MAC_SESSION, PHONE_SESSION, type Session} from './agent';
import {keyframes, ramp, smoother, type Ease, type Key} from './anim';
import {cameraAt, type Cam, type Shot} from './camera';
import {IPHONE_SCREEN} from './devices/IPhoneAir';
import {macGeometry} from './devices/MacBookAir';
import {springFollow} from './follow';
import {BEATS} from './timeline';
import {AGENT_RECT, POPOVER_RECT} from './ui/MacDesktop';

const B = BEATS;
export const HOME: Cam = {x: 960, y: 540, z: 1};

// Snappy ease for whip zooms: slow start, fast middle, long settle.
const whip: Ease = (t) => (t < 0.5 ? 8 * t ** 4 : 1 - Math.pow(-2 * t + 2, 4) / 2);

type Placement = {cx: Key[]; cy: Key[]; w: Key[]};
export const place = (frame: number, p: Placement) => ({
  cx: keyframes(frame, p.cx, smoother), cy: keyframes(frame, p.cy, smoother), w: keyframes(frame, p.w, smoother),
});

// Taglines live in world space behind the devices; devices never sit under text
// except by passing in front of it.
export const MAC: Placement = {
  cx: [[B.caption1 - 20, 960], [B.caption1 + 70, 540], [B.phoneIn, 560], [B.phoneIn + 90, 600], [B.reset - 40, 600], [B.reset, 380], [B.endCard + 10, 380], [B.endCard + 100, 660]],
  cy: [[B.caption1 - 20, 540], [B.caption1 + 70, 560], [B.phoneIn + 90, 520], [B.endCard, 520], [B.endCard + 100, 560]],
  w: [[B.caption1 - 20, 1200], [B.caption1 + 70, 860], [B.phoneIn + 90, 760], [B.endCard, 760], [B.endCard + 100, 900]],
};
export const PHONE: Placement = {
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

// Transcript y (screen points) the close-up watches: composer while typing, else
// the newest line. Raw target steps as content arrives; springFollow smooths it.
function watchTarget(s: Session, frame: number, top: number, composerY: number, lo: number, hi: number) {
  const a = agentAt(s, frame);
  const y = a.composer || a.items.length === 0 ? composerY : top + (a.focusY - a.scroll) - 80;
  return Math.max(lo, Math.min(hi, y));
}
// Two springs in series so the camera also eases *into* each move.
const smoothFollow = (key: string, f: number, target: (g: number) => number) =>
  springFollow(`${key}:2`, f, (g) => springFollow(`${key}:1`, g, target, 0.11), 0.11);
const macWatchY = (f: number) =>
  smoothFollow('mac-watch', f, (g) => watchTarget(MAC_SESSION, g, AGENT_RECT.y + 62, AGENT_RECT.y + 520, AGENT_RECT.y + 240, AGENT_RECT.y + 500));
const phoneWatchY = (f: number) =>
  smoothFollow('phone-watch', f, (g) => watchTarget(PHONE_SESSION, g, 128, 780, 330, 640));


export function cameraFor(frame: number): Cam {
  const shots: Shot[] = [
    {at: 0, cam: (f) => {
      const y = macWatchY(f);
      const p = macPoint(place(f, MAC), AGENT_RECT.x + 380 + f * 0.05, y);
      // Slow constant push from the very first frame so the open never sits still.
      return {x: p.x, y: p.y, z: 2.55 - 0.4 * (f / B.zoomOut)};
    }},
    {at: B.zoomOut, blend: 64, ease: whip, cam: () => HOME},
    {at: B.click + 8, blend: 60, ease: smoother, cam: (f) => {
      const p = macPoint(place(f, MAC), POPOVER_RECT.x + POPOVER_RECT.w / 2, POPOVER_RECT.y + POPOVER_RECT.h / 2);
      return {x: p.x - 250 / 1.9, y: p.y + 10, z: 1.9};
    }},
    {at: B.caption1 - 10, blend: 80, ease: smoother, cam: () => HOME},
    {at: B.phoneIn, blend: 90, ease: smoother, cam: () => ({x: 1040, y: 548, z: 1.06})},
    {at: B.phonePrompt - 30, blend: 60, ease: smoother, cam: (f) => {
      const y = phoneWatchY(f);
      const p = phonePoint(place(f, PHONE), 210, y);
      return {x: p.x, y: p.y, z: 1.45};
    }},
    {at: B.notify, blend: 44, ease: smoother, cam: (f) => {
      const p = phonePoint(place(f, PHONE), 210, 300);
      return {x: p.x, y: p.y, z: 1.6};
    }},
    {at: B.tap + 24, blend: 60, ease: smoother, cam: (f) => {
      const p = phonePoint(place(f, PHONE), 210, 560);
      return {x: p.x, y: p.y, z: 1.55};
    }},
    {at: B.reset - 6, blend: 44, ease: whip, cam: () => ({x: 980, y: 545, z: 1.02})},
    {at: B.endCard, blend: 100, ease: smoother, cam: () => HOME},
  ];
  return cameraAt(frame, shots, smoother);
}
