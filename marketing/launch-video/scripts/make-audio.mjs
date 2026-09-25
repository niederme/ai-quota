// Synthesises the original soundtrack to public/soundtrack.wav (48 kHz stereo).
// Cue frames mirror BEATS in src/timeline.ts (60 fps). 90 BPM = one beat per 40 frames,
// so captions (240, 600) and the end card (760) land on the grid.
import {writeFileSync} from 'node:fs';

const SR = 48000;
const FPS = 60;
const DURATION = 1020;
const BEATS = {macOpen: 40, caption1: 240, phoneIn: 390, caption2: 600, notify: 640, peak: 690, reset: 725, endCard: 760};
const N = Math.ceil((DURATION / FPS) * SR);
const L = new Float32Array(N);
const R = new Float32Array(N);
const t = (frame) => frame / FPS;
const idx = (sec) => Math.floor(sec * SR);
const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);

let seed = 7;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

function add(buf, i, v) { if (i >= 0 && i < N) buf[i] += v; }
function addStereo(i, v, pan = 0) {
  add(L, i, v * Math.cos((pan + 1) * Math.PI / 4));
  add(R, i, v * Math.sin((pan + 1) * Math.PI / 4));
}

// --- Pad: detuned soft triangles through a slow low-pass, crossfading chords.
const chords = [
  {at: 0, notes: [50, 57, 61, 64, 66]},                 // Dmaj9
  {at: t(BEATS.caption2), notes: [47, 54, 57, 62, 64]},  // Bm11
  {at: t(BEATS.endCard), notes: [43, 55, 59, 62, 66, 69]}, // Gmaj9 (#11 colour)
];
const tri = (ph) => 2 * Math.abs(2 * (ph - Math.floor(ph + 0.5))) - 1;
for (let c = 0; c < chords.length; c++) {
  const start = chords[c].at;
  const end = c + 1 < chords.length ? chords[c + 1].at : DURATION / FPS;
  const fadeIn = c === 0 ? 1.6 : 0.6;
  const s0 = idx(Math.max(0, start - 0.3)), s1 = Math.min(N, idx(end + 1.2));
  chords[c].notes.forEach((m, k) => {
    for (const det of [-0.06, 0.06]) {
      const f = midi(m + det);
      let ph = (rand() + 1) / 2, lp = 0;
      const pan = (k / (chords[c].notes.length - 1)) * 1.2 - 0.6 + det * 3;
      for (let i = s0; i < s1; i++) {
        const sec = i / SR;
        const env = Math.min(1, Math.max(0, (sec - (start - 0.3)) / fadeIn)) * Math.min(1, Math.max(0, (end + 1.2 - sec) / 1.2));
        ph += f / SR;
        const x = tri(ph) * (0.85 + 0.15 * Math.sin(2 * Math.PI * 0.23 * sec + k));
        const cutoff = 0.02 + 0.03 * (c === 2 ? Math.min(1, (sec - start) / 2) : 0.4);
        lp += cutoff * (x - lp);
        addStereo(i, lp * env * 0.05 * (m < 50 ? 1.3 : 1), pan);
      }
    }
  });
}

// --- Pulse: soft sub kick on the beat between the first caption and the end card.
for (let f = BEATS.caption1; f < BEATS.endCard; f += 40) {
  const s = idx(t(f));
  const accent = f === BEATS.caption1 || f === BEATS.caption2 ? 1.3 : 1;
  let ph = 0;
  for (let i = 0; i < idx(0.45); i++) {
    const sec = i / SR;
    ph += (46 + 70 * Math.exp(-sec * 28)) / SR;
    addStereo(s + i, Math.sin(2 * Math.PI * ph) * Math.exp(-sec * 7) * 0.22 * accent, 0);
  }
}

// --- Ticks: cursor click and gauge fill ticks as the popover reveals.
function tick(frame, gain, freq = 3200, pan = 0.3) {
  const s = idx(t(frame));
  for (let i = 0; i < idx(0.03); i++) {
    const sec = i / SR;
    addStereo(s + i, (Math.sin(2 * Math.PI * freq * sec) * 0.6 + rand() * 0.4) * Math.exp(-sec * 260) * gain, pan);
  }
}
tick(34, 0.35, 1800, 0.4);
for (let f = BEATS.macOpen + 4, k = 0; f < BEATS.macOpen + 40; f += 4, k++) tick(f, 0.1 * (1 - k / 12), 2600 + k * 120, 0.35);
for (let f = BEATS.phoneIn + 70, k = 0; f < BEATS.phoneIn + 100; f += 5, k++) tick(f, 0.07, 3000 + k * 100, 0.5);

// --- Whooshes: band-passed noise swells for device moves.
function whoosh(frame, dur, gain, pan = 0, rise = 1) {
  const s = idx(t(frame) - dur * 0.6);
  let b1 = 0, b2 = 0;
  for (let i = 0; i < idx(dur); i++) {
    const p = i / idx(dur);
    const env = Math.sin(Math.PI * Math.pow(p, 0.8)) ** 2;
    const fc = rise > 0 ? 300 + 2200 * p : 2500 - 2200 * p;
    const w = 2 * Math.PI * fc / SR, q = 0.9;
    // State-variable band-pass.
    const x = rand();
    const hp = x - b1 * q - b2;
    b1 += w * hp;
    b2 += w * b1;
    addStereo(s + i, b1 * env * gain, pan * (p * 2 - 1));
  }
}
whoosh(BEATS.caption1 - 20, 1.1, 0.1, -0.6);
whoosh(BEATS.phoneIn + 40, 1.0, 0.11, 0.6);
whoosh(BEATS.caption2, 1.0, 0.08, 0.3);
whoosh(BEATS.endCard + 20, 1.4, 0.1, -0.2, -1);

// --- Notification chime (two soft bells).
function bell(frame, m, gain, pan = 0.5) {
  const s = idx(t(frame));
  const f = midi(m);
  for (let i = 0; i < idx(1.6); i++) {
    const sec = i / SR;
    const v = (Math.sin(2 * Math.PI * f * sec) + 0.35 * Math.sin(2 * Math.PI * f * 2.76 * sec) * Math.exp(-sec * 6)) * Math.exp(-sec * 3.2);
    addStereo(s + i, v * gain * Math.min(1, sec * 400), pan);
  }
}
bell(BEATS.notify + 12, 88, 0.09);
bell(BEATS.notify + 20, 95, 0.07);

// --- Tension under the critical peak: low detuned drone swelling into the reset.
{
  const s0 = idx(t(BEATS.peak - 40)), s1 = idx(t(BEATS.reset + 10));
  let ph1 = 0, ph2 = 0;
  for (let i = s0; i < s1; i++) {
    const p = (i - s0) / (s1 - s0);
    ph1 += midi(35) / SR; ph2 += midi(35.3) / SR;
    const env = Math.sin(Math.PI * p) * p;
    addStereo(i, (Math.sin(2 * Math.PI * ph1) + Math.sin(2 * Math.PI * ph2)) * env * 0.08, 0);
  }
}
// --- Reset sparkle: quick rising arpeggio as the gauge refills.
[74, 78, 81, 86, 90].forEach((m, k) => bell(BEATS.reset + 8 + k * 4, m, 0.05, -0.4 + k * 0.2));
// --- End card shimmer as the lockup lands.
[79, 83, 86, 90].forEach((m, k) => bell(BEATS.endCard + 40 + k * 7, m, 0.045, 0.4 - k * 0.25));

// --- Simple Schroeder reverb for space.
function reverb(src, pre) {
  const out = new Float32Array(N);
  const combs = [1557, 1617, 1491, 1422].map((d) => ({d: d + pre, buf: new Float32Array(d + pre), i: 0, lp: 0}));
  for (let n = 0; n < N; n++) {
    let y = 0;
    for (const c of combs) {
      const v = c.buf[c.i];
      c.lp = v * 0.6 + c.lp * 0.4;
      c.buf[c.i] = src[n] + c.lp * 0.84;
      c.i = (c.i + 1) % c.d;
      y += v;
    }
    out[n] = y * 0.25;
  }
  for (const d of [225, 556]) {
    const buf = new Float32Array(d); let i = 0;
    for (let n = 0; n < N; n++) {
      const v = buf[i]; const x = out[n];
      buf[i] = x + v * 0.5; out[n] = v - x * 0.5; i = (i + 1) % d;
    }
  }
  return out;
}
const wetL = reverb(L, 0), wetR = reverb(R, 23);

// --- Mix, fade the tail, normalise to -1 dBFS.
const outL = new Float32Array(N), outR = new Float32Array(N);
let peak = 0;
for (let n = 0; n < N; n++) {
  const sec = n / SR, total = N / SR;
  const fade = Math.min(1, n / (SR * 0.05)) * Math.min(1, (total - sec) / 1.2);
  outL[n] = (L[n] * 0.8 + wetL[n] * 0.35) * fade;
  outR[n] = (R[n] * 0.8 + wetR[n] * 0.35) * fade;
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
console.log(`wrote public/soundtrack.wav (${(N / SR).toFixed(2)}s, gain ${gain.toFixed(2)})`);
