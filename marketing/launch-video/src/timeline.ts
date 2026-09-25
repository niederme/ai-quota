import {keyframes as track, type Key} from './anim';
import {theme} from './theme';
import beats from './beats.json';

export const FPS = beats.fps;
export const DURATION = beats.duration;

// Frame markers live in beats.json so the soundtrack script shares them.
// 90 BPM = one beat per 40 frames; captions and the end card sit on that grid.
export const BEATS = beats.beats;

export type Window = {h5: number; d7: number};
export type Usage = {codex: Window; claude: Window};

const curves = {
  codexH5: [[0, 20], [BEATS.macOpen, 31], [BEATS.caption2, 48], [DURATION, 55]] as Key[],
  codexD7: [[0, 52], [BEATS.caption2, 58], [DURATION, 61]] as Key[],
  claudeH5: [[0, 30], [BEATS.macOpen, 54], [BEATS.caption2, 81], [BEATS.peak, 97],
    [BEATS.reset - 10, 97], [BEATS.reset + 20, 6], [DURATION, 16]] as Key[],
  claudeD7: [[0, 38], [BEATS.peak, 52], [DURATION, 55]] as Key[],
};

export function usageAt(frame: number): Usage {
  return {
    codex: {h5: track(frame, curves.codexH5), d7: track(frame, curves.codexD7)},
    claude: {h5: track(frame, curves.claudeH5), d7: track(frame, curves.claudeD7)},
  };
}

// Tokens streamed by the agent session on the Mac; drives the status line.
export function tokensAt(frame: number): number {
  return Math.round(track(frame, [[BEATS.promptSent, 0], [BEATS.zoomOut, 21400], [BEATS.caption2, 58200], [DURATION, 74800]]));
}

// Same thresholds as CircularGaugeView / OverviewView.
export function gaugeColor(worst: number): string {
  if (worst >= 95) return theme.critical;
  if (worst >= 85) return theme.warning;
  return theme.accent;
}
