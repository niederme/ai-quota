// App tokens mirror the iOS dark appearance (iOS/App/Assets.xcassets Overview*).
export const theme = {
  base: '#0B060F',
  accent: '#BF5AF2',
  warning: '#FF9F0A',
  critical: '#FF453A',
  wash: 'rgb(102,31,143)',
  primary: '#FFFFFF',
  secondary: 'rgba(235,235,245,0.62)',
  tertiary: 'rgba(235,235,245,0.30)',
  track: 'rgba(118,118,128,0.18)',
  font: '-apple-system, "SF Pro Display", "SF Pro Text", system-ui, sans-serif',
  mono: '"SF Mono", ui-monospace, Menlo, monospace',
} as const;

// Framing around the devices: light and neutral so the dark product UI carries the colour.
export const stage = {
  bg: '#F5F5F7',
  ink: '#1D1D1F',
  inkSecondary: '#6E6E73',
} as const;
