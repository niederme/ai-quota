import React from 'react';
import {Composition, Still} from 'remotion';
import {LaunchVideo} from './LaunchVideo';
import {DURATION, FPS} from './timeline';
import {MacDesktop} from './ui/MacDesktop';
import {IOSOverview} from './ui/IOSOverview';
import {AppIcon} from './ui/AppIcon';
import {usageAt} from './timeline';

export const Root: React.FC = () => (
  <>
    <Composition id="Launch16x9" component={LaunchVideo} durationInFrames={DURATION} fps={FPS} width={3840} height={2160} />
    <Composition id="Launch16x9Preview" component={LaunchVideo} durationInFrames={DURATION} fps={FPS} width={1920} height={1080} />
    <Still id="MacStill" width={1470} height={956} component={() => (
      <MacDesktop frame={200} usage={usageAt(200)} popover={1} cursor={{x: 0, y: 0, opacity: 0, press: 0}} />)} />
    <Still id="IOSStill" width={420} height={912} component={() => (
      <IOSOverview usage={usageAt(500)} claudeGlow={0} notification={1} />)} />
    <Still id="IconStill" width={400} height={400} component={() => <div style={{padding: 50}}><AppIcon size={300} /></div>} />
  </>
);
