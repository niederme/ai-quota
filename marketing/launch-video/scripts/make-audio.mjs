// Synthesises the original soundtrack to public/soundtrack.wav (48 kHz stereo).
// Dusty boom-bap at 90 BPM (one beat = 40 frames at 60 fps), cut to the edit:
// drums + bass + Rhodes, scratches on the whip zooms, a filtered break under the
// first tagline, a tape-stop at the red peak, and a slam back in on the reset.
// Cue frames come from src/beats.json.
import {readFileSync, writeFileSync} from 'node:fs';

const {fps: FPS, duration: DURATION, beats: B} = JSON.parse(readFileSync(new URL('../src/beats.json', import.meta.url)));
const SR = 48000;
const N = Math.ceil((DURATION / FPS) * SR);
const BEAT = 40; // frames
const BAR = BEAT * 4;
const STEP = BEAT / 4; // 16th note in frames
const SWING = 0.18; // fraction of a 16th that off-beat 16ths are delayed
const sec = (frame) => frame / FPS;
const idx = (s) => Math.floor(s * SR);
const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);
const clamp01 = (x) => Math.max(0, Math.min(1, x));

let seed = 90;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

const bus = () => ({L: new Float32Array(N), R: new Float32Array(N)});
const drums = bus(), music = bus(), fx = bus();
function put(b, i, v, pan = 0) {
  if (i < 0 || i >= N) return;
  b.L[i] += v * Math.cos(((pan + 1) * Math.PI) / 4);
  b.R[i] += v * Math.sin(((pan + 1) * Math.PI) / 4);
}

// Sections (frames).
const DRUMS_IN = BEAT;                 // drums enter, filtered, after the first beat
const DRUMS_OPEN = BAR;                // filter fully open
const BREAK = [B.caption1, B.phoneIn]; // filtered break under "Know your limits."
const STOP = [B.peak, B.reset];        // tape-stop, then silence until the reset
const OUTRO_END = B.endCard + BAR;     // beat ends a bar into the end card
const playing = (f) => f >= DRUMS_IN && f < OUTRO_END && !(f >= STOP[0] && f < STOP[1]);

// Chords: Dm9 | Bbmaj7 | Gm9 | A7#9, one per bar.
const CHORDS = [
  {root: 38, notes: [53, 57, 60, 64]},
  {root: 34, notes: [53, 57, 58, 62]},
  {root: 31, notes: [50, 53, 57, 58]},
  {root: 33, notes: [49, 55, 60, 61]},
];
const chordAt = (f) => CHORDS[Math.floor(Math.max(0, f) / BAR) % CHORDS.length];

// ---------- Instruments ----------
function kick(f, gain) {
  const s0 = idx(sec(f));
  let ph = 0;
  for (let i = 0; i < idx(0.42); i++) {
    const t = i / SR;
    ph += (48 + 110 * Math.exp(-t * 30)) / SR;
    const body = Math.sin(2 * Math.PI * ph) * Math.exp(-t * 7.5);
    const click = rand() * Math.exp(-t * 900) * 0.4;
    put(drums, s0 + i, Math.tanh((body + click) * 1.8) * gain, 0);
  }
}
function snare(f, gain) {
  const s0 = idx(sec(f));
  let b1 = 0, b2 = 0;
  const w = (2 * Math.PI * 2600) / SR;
  for (let i = 0; i < idx(0.3); i++) {
    const t = i / SR;
    const tone = (Math.sin(2 * Math.PI * 185 * t) + 0.5 * Math.sin(2 * Math.PI * 330 * t)) * Math.exp(-t * 28);
    const hp = rand() - b1 * 0.7 - b2;
    b1 += w * hp; b2 += w * b1;
    const noise = b1 * Math.exp(-t * 16);
    put(drums, s0 + i, Math.tanh((tone * 0.5 + noise * 1.1) * 1.5) * gain, 0.05);
  }
}
function hat(f, gain, open = false) {
  const s0 = idx(sec(f));
  let x1 = 0, y1 = 0, y2 = 0;
  const len = open ? 0.22 : 0.05;
  for (let i = 0; i < idx(len); i++) {
    const t = i / SR;
    const x = rand();
    y1 = 0.85 * (y1 + x - x1); x1 = x; // high-pass
    y2 = 0.6 * (y2 + y1) ; // soften
    put(drums, s0 + i, (y1 - 0.3 * y2) * Math.exp(-t * (open ? 14 : 70)) * gain, 0.35);
  }
}
// FM electric piano voice.
function rhodes(f, m, gain, len, pan) {
  const s0 = idx(sec(f));
  const fc = midi(m);
  for (let i = 0; i < idx(len); i++) {
    const t = i / SR;
    const index = 1.6 * Math.exp(-t * 6) + 0.25;
    const mod = Math.sin(2 * Math.PI * fc * t) * index;
    const v = Math.sin(2 * Math.PI * fc * t + mod) + 0.2 * Math.sin(2 * Math.PI * fc * 2 * t) * Math.exp(-t * 9);
    const env = Math.min(1, t * 300) * Math.exp(-t * 2.2) * clamp01((len - t) / 0.05);
    const trem = 1 + 0.18 * Math.sin(2 * Math.PI * 4.6 * t);
    put(music, s0 + i, v * env * trem * gain, pan);
  }
}
// Warm bass: sine + soft saturated 2nd harmonic, short glide in.
function bass(f, m, gain, len) {
  const s0 = idx(sec(f));
  const fr = midi(m);
  let ph = 0;
  for (let i = 0; i < idx(len); i++) {
    const t = i / SR;
    ph += fr * (1 + 0.04 * Math.exp(-t * 60)) / SR;
    const v = Math.tanh((Math.sin(2 * Math.PI * ph) + 0.35 * Math.sin(4 * Math.PI * ph)) * 1.6);
    const env = Math.min(1, t * 200) * (0.65 + 0.35 * Math.exp(-t * 5)) * clamp01((len - t) / 0.03);
    put(music, s0 + i, v * env * gain, 0);
  }
}
// Brass-ish stab: detuned saws through a closing low-pass.
function stab(f, notes, gain, len = 0.34) {
  const s0 = idx(sec(f));
  const voices = notes.flatMap((m) => [midi(m) * 0.997, midi(m) * 1.003]);
  const phase = voices.map(() => (rand() + 1) / 2);
  let lp1 = 0, lp2 = 0;
  for (let i = 0; i < idx(len); i++) {
    const t = i / SR;
    let x = 0;
    voices.forEach((fr, k) => { phase[k] = (phase[k] + fr / SR) % 1; x += 2 * phase[k] - 1; });
    x /= voices.length;
    const cut = 0.04 + 0.35 * Math.exp(-t * 9);
    lp1 += cut * (x - lp1); lp2 += cut * (lp1 - lp2);
    const env = Math.min(1, t * 150) * Math.exp(-t * 5) * clamp01((len - t) / 0.04);
    put(fx, s0 + i, lp2 * env * gain * 3, 0);
  }
}
// Turntable scratch: a formant-ish tone whose playback speed swings back and forth.
function scratch(f, gain, cuts = 2, dur = 0.34) {
  const s0 = idx(sec(f));
  let pos = 0, b1 = 0, b2 = 0;
  for (let i = 0; i < idx(dur); i++) {
    const t = i / SR;
    const speed = Math.sin(Math.PI * cuts * (t / dur)) * 2.2;
    pos += speed / SR;
    const src = Math.sin(2 * Math.PI * 330 * pos) + 0.6 * Math.sin(2 * Math.PI * 740 * pos) + 0.3 * rand() * Math.abs(speed);
    const w = (2 * Math.PI * (700 + 900 * Math.abs(speed))) / SR;
    const hp = src - b1 * 0.35 - b2;
    b1 += w * hp; b2 += w * b1;
    const env = Math.abs(speed) / 2.2 * clamp01(t / 0.01) * clamp01((dur - t) / 0.02);
    put(fx, s0 + i, Math.tanh(b1 * 1.4) * env * gain, 0.2);
  }
}
function hit(f, gain) { // crash-ish noise burst + low boom for the slam-backs
  const s0 = idx(sec(f));
  let x1 = 0, y1 = 0;
  for (let i = 0; i < idx(1.4); i++) {
    const t = i / SR;
    const x = rand();
    y1 = 0.9 * (y1 + x - x1); x1 = x;
    put(fx, s0 + i, (y1 * Math.exp(-t * 3.2) * 0.35 + Math.sin(2 * Math.PI * 45 * t) * Math.exp(-t * 6)) * gain, 0);
  }
}
function click(f, gain, freq, pan) {
  const s0 = idx(sec(f));
  for (let i = 0; i < idx(0.022); i++) {
    const t = i / SR;
    put(fx, s0 + i, (Math.sin(2 * Math.PI * freq * t) * 0.5 + rand() * 0.5) * Math.exp(-t * 320) * gain, pan);
  }
}
function bell(f, m, gain, pan = 0.4) {
  const s0 = idx(sec(f));
  const fr = midi(m);
  for (let i = 0; i < idx(1.4); i++) {
    const t = i / SR;
    const v = (Math.sin(2 * Math.PI * fr * t) + 0.3 * Math.sin(2 * Math.PI * fr * 2.76 * t) * Math.exp(-t * 7)) * Math.exp(-t * 3.5);
    put(fx, s0 + i, v * gain * Math.min(1, t * 500), pan);
  }
}

// ---------- Arrangement ----------
const swing = (f, step) => f + (step % 2 === 1 ? SWING * STEP : 0);

for (let bar = 0; bar * BAR < DURATION; bar++) {
  const b0 = bar * BAR;
  const alt = bar % 2 === 1;
  for (let step = 0; step < 16; step++) {
    const f = swing(b0 + step * STEP, step);
    if (!playing(f)) continue;
    const inBreak = f >= BREAK[0] && f < BREAK[1];
    const kicks = alt ? [0, 3, 7, 10] : [0, 7, 10];
    if (kicks.includes(step)) kick(f, 0.9);
    if (inBreak) continue; // break: kick only (and it gets filtered)
    if (step === 4 || step === 12) snare(f, 0.62);
    if (step === 15 && alt) snare(f, 0.16); // ghost
    if (step % 2 === 0) hat(f, step === 14 ? 0.2 : 0.22, step === 14);
    else if (step === 3 || step === 11) hat(f, 0.08);
  }
}

// Bassline: syncopated roots/octaves, sits out in the break and the stop.
const BASS_STEPS = [[0, 0, 0.5], [3, 0, 0.18], [6, 12, 0.16], [10, 0, 0.3], [14, 7, 0.14]];
for (let bar = 0; bar * BAR < OUTRO_END; bar++) {
  const b0 = bar * BAR;
  if (b0 < BAR) continue;
  for (const [step, off, len] of BASS_STEPS) {
    const f = swing(b0 + step * STEP, step);
    if (!playing(f) || (f >= BREAK[0] && f < BREAK[1])) continue;
    bass(f, chordAt(f).root + off, 0.34, len);
  }
}

// Rhodes: chord on the one, a push on the "and" of two. Also carries the intro and the break.
for (let bar = 0; bar * BAR < DURATION; bar++) {
  const b0 = bar * BAR;
  const ch = chordAt(b0).notes;
  for (const [step, len, g] of [[0, 1.0, 0.07], [6, 0.35, 0.05], [11, 0.5, 0.045]]) {
    const f = swing(b0 + step * STEP, step);
    if (f >= STOP[0] && f < STOP[1]) continue;
    if (f >= OUTRO_END) continue;
    ch.forEach((m, k) => rhodes(f + k * 0.6, m, g, f >= OUTRO_END ? 2.2 : len, -0.3 + k * 0.2));
  }
}

// Foley and hits cut to picture.
for (let f = 6, k = 0; f < B.promptSent - 4; f += 2 + (k++ % 3 === 0 ? 1 : 0)) click(f, 0.06 + 0.02 * rand(), 2400 + 700 * rand(), 0);
click(B.promptSent, 0.12, 1500, 0);
for (let f = B.followUp - 36, k = 0; f < B.followUp - 4; f += 2 + (k++ % 3 === 0 ? 1 : 0)) click(f, 0.05 + 0.02 * rand(), 2600 + 600 * rand(), 0);
scratch(B.zoomOut + 20, 0.28, 2);
click(B.click, 0.18, 1700, 0.4);
stab(B.macOpen, [62, 65, 69, 72], 0.5);
scratch(B.caption1 - 8, 0.22, 3, 0.4);
hit(B.phoneIn, 0.5);
stab(B.phoneIn, [62, 65, 69, 72], 0.55);
scratch(B.phoneIn + 40, 0.2, 2);
for (let f = B.phonePrompt - 30, k = 0; f < B.phonePrompt - 4; f += 2 + (k++ % 3 === 0 ? 1 : 0)) click(f, 0.05 + 0.02 * rand(), 2600 + 600 * rand(), 0.2);
bell(B.notify + 12, 88, 0.08);
bell(B.notify + 20, 95, 0.06);
click(B.tap, 0.15, 1900, 0.2);
stab(B.tap + 4, [61, 64, 67, 70], 0.4);
hit(B.reset, 0.6);
stab(B.reset, [62, 65, 69, 72, 76], 0.7);
scratch(B.reset + 20, 0.22, 2);
hit(B.endCard, 0.45);
stab(B.endCard, [58, 62, 65, 69], 0.55);
stab(OUTRO_END, [62, 65, 69, 72, 76], 0.6, 0.6);
// Final chord rings out under the logo.
[50, 57, 60, 64, 65, 69].forEach((m, k) => rhodes(OUTRO_END + k * 1.2, m, 0.09, 2.8, -0.4 + k * 0.16));

// ---------- Drum bus filter automation (intro build + break) ----------
function cutoffAt(f) {
  if (f < DRUMS_OPEN) return 300 + 9000 * Math.pow(clamp01((f - DRUMS_IN) / (DRUMS_OPEN - DRUMS_IN)), 2);
  if (f >= BREAK[0] && f < BREAK[1]) {
    const into = clamp01((f - BREAK[0]) / 20), out = clamp01((BREAK[1] - f) / 30);
    return 9300 - 8800 * Math.min(into, out);
  }
  return 9300;
}
for (const ch of ['L', 'R']) {
  let a = 0, b = 0;
  for (let n = 0; n < N; n++) {
    const w = 1 - Math.exp((-2 * Math.PI * cutoffAt((n / SR) * FPS)) / SR);
    a += w * (drums[ch][n] - a); b += w * (a - b);
    drums[ch][n] = b;
  }
}

// ---------- Mix: short room on snare/music, vinyl, tape-stop, glue ----------
function room(src, pre) {
  const out = new Float32Array(N);
  const combs = [1116, 1188, 1277, 1356].map((d) => ({d: d + pre, buf: new Float32Array(d + pre), i: 0, lp: 0}));
  for (let n = 0; n < N; n++) {
    let y = 0;
    for (const c of combs) {
      const v = c.buf[c.i];
      c.lp = v * 0.5 + c.lp * 0.5;
      c.buf[c.i] = src[n] + c.lp * 0.72;
      c.i = (c.i + 1) % c.d;
      y += v;
    }
    out[n] = y * 0.25;
  }
  return out;
}
const mixL = new Float32Array(N), mixR = new Float32Array(N);
const sendL = new Float32Array(N), sendR = new Float32Array(N);
for (let n = 0; n < N; n++) {
  sendL[n] = drums.L[n] * 0.12 + music.L[n] * 0.35 + fx.L[n] * 0.3;
  sendR[n] = drums.R[n] * 0.12 + music.R[n] * 0.35 + fx.R[n] * 0.3;
}
const wetL = room(sendL, 0), wetR = room(sendR, 19);
let crackleLp = 0;
for (let n = 0; n < N; n++) {
  // Vinyl: sparse pops over soft hiss.
  let v = rand() * 0.004;
  if ((rand() + 1) / 2 < 22 / SR) v += rand() * 0.12;
  crackleLp += 0.3 * (v - crackleLp);
  mixL[n] = drums.L[n] + music.L[n] + fx.L[n] + wetL[n] * 0.5 + crackleLp;
  mixR[n] = drums.R[n] + music.R[n] + fx.R[n] + wetR[n] * 0.5 + crackleLp * 0.9;
}

// Tape-stop at the red peak: playback slows to zero over 0.45 s, then silence to the reset.
{
  const s0 = idx(sec(STOP[0])), len = idx(0.45), s1 = idx(sec(STOP[1]));
  const srcL = mixL.slice(s0, s0 + len), srcR = mixR.slice(s0, s0 + len);
  let pos = 0;
  for (let i = 0; i < s1 - s0; i++) {
    const rate = Math.max(0, 1 - i / len);
    pos += rate * rate;
    const k = Math.floor(pos), fr = pos - k;
    const gain = i < len ? 1 : 0;
    mixL[s0 + i] = gain * ((srcL[k] ?? 0) * (1 - fr) + (srcL[k + 1] ?? 0) * fr);
    mixR[s0 + i] = gain * ((srcR[k] ?? 0) * (1 - fr) + (srcR[k + 1] ?? 0) * fr);
  }
}

// Glue compression + soft clip, fade the tail, normalise to -1 dBFS.
let env = 0, peak = 0;
const total = N / SR;
for (let n = 0; n < N; n++) {
  const lvl = Math.max(Math.abs(mixL[n]), Math.abs(mixR[n]));
  env = lvl > env ? env + 0.01 * (lvl - env) : env + 0.0002 * (lvl - env);
  const g = env > 0.5 ? 0.5 / env + (1 - 0.5 / env) * 0.35 : 1;
  const t = n / SR;
  const fade = Math.min(1, n / (SR * 0.02)) * Math.min(1, (total - t) / 1.2);
  mixL[n] = Math.tanh(mixL[n] * g * 1.3) * fade;
  mixR[n] = Math.tanh(mixR[n] * g * 1.3) * fade;
  peak = Math.max(peak, Math.abs(mixL[n]), Math.abs(mixR[n]));
}
const gain = Math.pow(10, -1 / 20) / peak;

const data = Buffer.alloc(N * 4);
for (let n = 0; n < N; n++) {
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mixL[n] * gain)) * 32767), n * 4);
  data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mixR[n] * gain)) * 32767), n * 4 + 2);
}
const header = Buffer.alloc(44);
header.write('RIFF', 0); header.writeUInt32LE(36 + data.length, 4); header.write('WAVE', 8);
header.write('fmt ', 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22);
header.writeUInt32LE(SR, 24); header.writeUInt32LE(SR * 4, 28); header.writeUInt16LE(4, 32); header.writeUInt16LE(16, 34);
header.write('data', 36); header.writeUInt32LE(data.length, 40);
writeFileSync(new URL('../public/soundtrack.wav', import.meta.url), Buffer.concat([header, data]));
console.log(`wrote public/soundtrack.wav (${total.toFixed(2)}s, gain ${gain.toFixed(2)})`);
