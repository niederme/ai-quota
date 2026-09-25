import {keyframes as track, type Key} from './anim';
import {theme} from './theme';

export const FPS = 60;
export const DURATION = 1020;

// Frame markers for the storyboard; audio cues and scenes key off these.
export const BEATS = {
  macOpen: 40,
  caption1: 240,
  phoneIn: 390,
  caption2: 600,
  notify: 640,
  peak: 690,
  reset: 725,
  endCard: 760,
} as const;

export type Window = {h5: number; d7: number};
export type Usage = {codex: Window; claude: Window};

const curves = {
  codexH5: [[0, 12], [BEATS.caption1, 34], [BEATS.caption2, 52], [DURATION, 58]] as Key[],
  codexD7: [[0, 40], [BEATS.caption2, 58], [DURATION, 61]] as Key[],
  claudeH5: [[0, 18], [BEATS.caption1, 46], [BEATS.caption2, 80], [BEATS.peak, 97],
    [BEATS.reset - 10, 97], [BEATS.reset + 20, 6], [DURATION, 18]] as Key[],
  claudeD7: [[0, 30], [BEATS.peak, 52], [DURATION, 56]] as Key[],
};

export function usageAt(frame: number): Usage {
  return {
    codex: {h5: track(frame, curves.codexH5), d7: track(frame, curves.codexD7)},
    claude: {h5: track(frame, curves.claudeH5), d7: track(frame, curves.claudeD7)},
  };
}

// Same thresholds as CircularGaugeView / OverviewView.
export function gaugeColor(worst: number): string {
  if (worst >= 95) return theme.critical;
  if (worst >= 85) return theme.warning;
  return theme.accent;
}
