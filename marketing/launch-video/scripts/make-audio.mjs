// Synthesises the original soundtrack to public/soundtrack.wav (48 kHz stereo).
// Light, bright arrangement at 90 BPM (one beat = 40 frames at 60 fps): plucked
// arpeggios, soft groove, warm pad, and UI foley. Cue frames come from src/beats.json.
import {readFileSync, writeFileSync} from 'node:fs';

const {fps: FPS, duration: DURATION, beats: B} = JSON.parse(readFileSync(new URL('../src/beats.json', import.meta.url)));
const SR = 48000;
const N = Math.ceil((DURATION / FPS) * SR);
const L = new Float32Array(N);
const R = new Float32Array(N);
const sec = (frame) => frame / FPS;
const idx = (s) => Math.floor(s * SR);
const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);
const BEAT = 40; // frames

let seed = 11;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;
const clamp01 = (x) => Math.max(0, Math.min(1, x));

function put(i, v, pan = 0) {
  if (i < 0 || i >= N) return;
  L[i] += v * Math.cos(((pan + 1) * Math.PI) / 4);
  R[i] += v * Math.sin(((pan + 1) * Math.PI) / 4);
}

// Chord timeline (frames). Root is used by the bass.
const CHORDS = [
  {at: 0, root: 38, notes: [62, 66, 69, 73, 76]},            // Dmaj9
  {at: B.caption1, root: 43, notes: [62, 66, 67, 71, 74]},   // Gmaj9 lift on "Know your limits."
  {at: B.phoneIn + 40, root: 38, notes: [62, 64, 66, 69, 73]}, // Dadd9
  {at: B.caption2, root: 35, notes: [61, 62, 66, 69, 71]},   // Bm11 on "before they break your flow."
  {at: B.peak, root: 33, notes: [62, 64, 67, 69, 72]},       // A7sus: suspense at the peak
  {at: B.reset, root: 38, notes: [62, 66, 69, 73, 76]},      // back home as the gauge resets
  {at: B.endCard, root: 43, notes: [62, 66, 67, 71, 74, 79]}, // Gmaj9 bloom for the end card
  {at: B.endCard + 160, root: 38, notes: [62, 66, 69, 73, 76, 81]}, // resolve to D
];
const chordAt = (frame) => CHORDS.filter((c) => c.at <= frame).pop();

// --- Karplus–Strong pluck.
function pluck(frame, m, gain, pan, bright = 0.5, len = 0.9) {
  const f = midi(m);
  const period = Math.max(2, Math.round(SR / f));
  const buf = new Float32Array(period);
  let lp = 0;
  for (let i = 0; i < period; i++) { lp += bright * (rand() - lp); buf[i] = lp; }
  const s0 = idx(sec(frame));
  let p = 0;
  for (let i = 0; i < idx(len); i++) {
    const a = buf[p], b = buf[(p + 1) % period];
    buf[p] = 0.5 * (a + b) * 0.996;
    p = (p + 1) % period;
    const env = Math.min(1, i / 40) * Math.min(1, (idx(len) - i) / 2000);
    put(s0 + i, a * gain * env, pan);
  }
}

// --- Pad: soft additive voices (fundamental + gentle 2nd/3rd harmonics), slow swells.
for (let c = 0; c < CHORDS.length; c++) {
  const start = sec(CHORDS[c].at);
  const end = c + 1 < CHORDS.length ? sec(CHORDS[c + 1].at) : DURATION / FPS;
  const s0 = idx(Math.max(0, start - 0.15)), s1 = Math.min(N, idx(end + 0.8));
  CHORDS[c].notes.slice(0, 4).forEach((m, k) => {
    const f = midi(m - 12);
    const pan = -0.5 + k * 0.33;
    const ph0 = (rand() + 1) * Math.PI;
    for (let i = s0; i < s1; i++) {
      const t = i / SR;
      const env = clamp01((t - (start - 0.15)) / 0.5) * clamp01((end + 0.8 - t) / 0.8);
      const w = 2 * Math.PI * f * t + ph0;
      const v = Math.sin(w) + 0.25 * Math.sin(2 * w + 0.3) + 0.08 * Math.sin(3 * w);
      const breathe = 0.8 + 0.2 * Math.sin(2 * Math.PI * 0.25 * t + k);
      put(i, v * env * breathe * 0.024, pan);
    }
  });
}

// --- Arpeggio: 16th-note plucks. Sparse while the agent starts, full once the story kicks in.
const ARP = [0, 2, 1, 3, 2, 4, 3, 1];
for (let f = B.promptSent, n = 0; f < DURATION - 60; f += BEAT / 4, n++) {
  const inDrop = f >= B.peak && f < B.reset;
  const intro = f < B.caption1;
  const outro = f >= B.endCard;
  if (inDrop) continue;
  if (intro && n % 2 === 1) continue;
  if (outro && n % 4 !== 0) continue;
  const ch = chordAt(f).notes;
  const m = ch[ARP[n % ARP.length] % ch.length] + (n % 16 >= 8 && !intro ? 12 : 0);
  const accent = n % 4 === 0 ? 1 : 0.7;
  const gain = (intro ? 0.16 + 0.12 * clamp01((f - B.promptSent) / 150) : outro ? 0.26 : 0.32) * accent;
  pluck(f, m, gain, n % 2 ? 0.35 : -0.35, intro ? 0.35 : 0.55);
}

// --- Bass: round sine on beats 1 and 3 from the zoom-out on.
for (let f = B.zoomOut + 40; f < B.endCard + 80; f += BEAT * 2) {
  if (f >= B.peak && f < B.reset) continue;
  const root = chordAt(f).root;
  const s0 = idx(sec(f));
  for (let i = 0; i < idx(1.1); i++) {
    const t = i / SR;
    const env = Math.min(1, t * 60) * Math.exp(-t * 2.2);
    put(s0 + i, Math.sin(2 * Math.PI * midi(root) * t) * env * 0.14, 0);
  }
}

// --- Drums: soft kick on each beat, shaker 8ths, light snap on 2 and 4.
function kick(frame, gain) {
  const s0 = idx(sec(frame));
  let ph = 0;
  for (let i = 0; i < idx(0.3); i++) {
    const t = i / SR;
    ph += (50 + 90 * Math.exp(-t * 35)) / SR;
    put(s0 + i, Math.sin(2 * Math.PI * ph) * Math.exp(-t * 12) * gain, 0);
  }
}
function shaker(frame, gain, pan) {
  const s0 = idx(sec(frame));
  let hp = 0, prev = 0;
  for (let i = 0; i < idx(0.07); i++) {
    const t = i / SR;
    const x = rand();
    hp = 0.92 * (hp + x - prev); prev = x;
    put(s0 + i, hp * Math.min(1, t * 400) * Math.exp(-t * 55) * gain, pan);
  }
}
function snap(frame, gain) {
  const s0 = idx(sec(frame));
  let b1 = 0, b2 = 0;
  const w = (2 * Math.PI * 1800) / SR;
  for (let i = 0; i < idx(0.12); i++) {
    const t = i / SR;
    const hp = rand() - b1 * 0.6 - b2;
    b1 += w * hp; b2 += w * b1;
    put(s0 + i, b1 * Math.exp(-t * 38) * gain, 0.1);
  }
}
for (let f = B.zoomOut + 40, n = 0; f < B.endCard; f += BEAT, n++) {
  if (f >= B.peak && f < B.reset) continue;
  kick(f, f < B.caption1 ? 0.16 : 0.22);
  if (f >= B.caption1 && n % 2 === 1) snap(f, 0.09);
}
for (let f = B.caption1, n = 0; f < B.endCard; f += BEAT / 2, n++) {
  if (f >= B.peak && f < B.reset) continue;
  shaker(f + (n % 2 ? 3 : 0), n % 2 ? 0.05 : 0.035, n % 2 ? 0.4 : -0.4);
}

// --- Foley.
function click(frame, gain, freq, pan) {
  const s0 = idx(sec(frame));
  for (let i = 0; i < idx(0.025); i++) {
    const t = i / SR;
    put(s0 + i, (Math.sin(2 * Math.PI * freq * t) * 0.5 + rand() * 0.5) * Math.exp(-t * 300) * gain, pan);
  }
}
// Typing the prompt.
for (let f = 4; f < B.promptSent - 4; f += 2 + Math.floor((rand() + 1) * 1.2)) click(f, 0.07 + 0.03 * rand(), 2400 + 600 * rand(), -0.1 + 0.2 * rand());
click(B.promptSent, 0.14, 1500, 0);
// Tool steps landing while the agent works.
for (const f of [92, 102, 112, 222, 240, 260]) click(f, 0.05, 3400, 0.3);
// Menu bar click.
click(B.click, 0.2, 1700, 0.4);

function whoosh(frame, dur, gain, dir = 1, pan = 0) {
  const s0 = idx(sec(frame) - dur * 0.55);
  let b1 = 0, b2 = 0;
  for (let i = 0; i < idx(dur); i++) {
    const p = i / idx(dur);
    const env = Math.sin(Math.PI * Math.pow(p, 0.7)) ** 2;
    const fc = dir > 0 ? 400 + 3000 * p : 3400 - 3000 * p;
    const w = (2 * Math.PI * fc) / SR;
    const hp = rand() - b1 * 1.1 - b2;
    b1 += w * hp; b2 += w * b1;
    put(s0 + i, b1 * env * gain, pan * (2 * p - 1));
  }
}
whoosh(B.zoomOut + 32, 1.0, 0.07, -1);
whoosh(B.click + 30, 0.6, 0.04, 1, 0.3);
whoosh(B.caption1 + 20, 0.9, 0.05, -1, -0.4);
whoosh(B.phoneIn + 50, 1.0, 0.07, 1, 0.6);
whoosh(B.caption2 - 10, 0.9, 0.05, 1, 0.3);
whoosh(B.endCard + 20, 1.3, 0.06, -1, -0.2);

function bell(frame, m, gain, pan = 0.4, decay = 3) {
  const s0 = idx(sec(frame));
  const f = midi(m);
  for (let i = 0; i < idx(1.8); i++) {
    const t = i / SR;
    const v = (Math.sin(2 * Math.PI * f * t) + 0.3 * Math.sin(2 * Math.PI * f * 2.76 * t) * Math.exp(-t * 7)) * Math.exp(-t * decay);
    put(s0 + i, v * gain * Math.min(1, t * 500), pan);
  }
}
// Popover opening sparkle.
[81, 85, 88].forEach((m, k) => bell(B.macOpen + 4 + k * 3, m, 0.03, 0.3 + k * 0.1, 5));
// iOS notification.
bell(B.notify + 12, 88, 0.07, 0.5);
bell(B.notify + 20, 95, 0.055, 0.5);
// Riser through the drop into the reset.
{
  const s0 = idx(sec(B.peak - 10)), s1 = idx(sec(B.reset));
  let b1 = 0, b2 = 0;
  for (let i = s0; i < s1; i++) {
    const p = (i - s0) / (s1 - s0);
    const w = (2 * Math.PI * (600 + 5000 * p * p)) / SR;
    const hp = rand() - b1 * 0.5 - b2;
    b1 += w * hp; b2 += w * b1;
    put(i, b1 * p * p * 0.06, 0);
  }
}
// Reset sparkle and end-card shimmer.
[74, 78, 81, 86, 90].forEach((m, k) => bell(B.reset + k * 3, m, 0.04, -0.4 + k * 0.2, 4));
[79, 83, 86, 91].forEach((m, k) => bell(B.endCard + 50 + k * 8, m, 0.035, 0.4 - k * 0.25, 2.5));

// --- Room: Schroeder reverb.
function reverb(src, pre) {
  const out = new Float32Array(N);
  const combs = [1557, 1617, 1491, 1422].map((d) => ({d: d + pre, buf: new Float32Array(d + pre), i: 0, lp: 0}));
  for (let n = 0; n < N; n++) {
    let y = 0;
    for (const c of combs) {
      const v = c.buf[c.i];
      c.lp = v * 0.55 + c.lp * 0.45;
      c.buf[c.i] = src[n] + c.lp * 0.82;
      c.i = (c.i + 1) % c.d;
      y += v;
    }
    out[n] = y * 0.25;
  }
  for (const d of [225, 556]) {
    const buf = new Float32Array(d); let i = 0;
    for (let n = 0; n < N; n++) {
      const v = buf[i], x = out[n];
      buf[i] = x + v * 0.5; out[n] = v - x * 0.5; i = (i + 1) % d;
    }
  }
  return out;
}
const wetL = reverb(L, 0), wetR = reverb(R, 23);

// --- Mix, gentle soft-clip, fade the tail, normalise to -1 dBFS.
const outL = new Float32Array(N), outR = new Float32Array(N);
let peak = 0;
const total = N / SR;
for (let n = 0; n < N; n++) {
  const t = n / SR;
  const fade = Math.min(1, n / (SR * 0.03)) * Math.min(1, (total - t) / 1.5);
  outL[n] = Math.tanh((L[n] * 0.85 + wetL[n] * 0.3) * 1.4) * fade;
  outR[n] = Math.tanh((R[n] * 0.85 + wetR[n] * 0.3) * 1.4) * fade;
  peak = Math.max(peak, Math.abs(outL[n]), Math.abs(outR[n]));
}
const gain = Math.pow(10, -1 / 20) / peak;

const data = Buffer.alloc(N * 4);
for (let n = 0; n < N; n++) {
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, outL[n] * gain)) * 32767), n * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, outR[n] * gain)) * 32767), n * 4 + 2);
}
const header = Buffer.alloc(44);
header.write('RIFF', 0); header.writeUInt32LE(36 + data.length, 4); header.write('WAVE', 8);
header.write('fmt ', 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22);
header.writeUInt32LE(SR, 24); header.writeUInt32LE(SR * 4, 28); header.writeUInt16LE(4, 32); header.writeUInt16LE(16, 34);
header.write('data', 36); header.writeUInt32LE(data.length, 40);
writeFileSync(new URL('../public/soundtrack.wav', import.meta.url), Buffer.concat([header, data]));
console.log(`wrote public/soundtrack.wav (${total.toFixed(2)}s, gain ${gain.toFixed(2)})`);
