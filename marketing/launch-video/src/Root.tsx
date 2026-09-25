import React from 'react';
import {Composition, Still} from 'remotion';
import {LaunchVideo} from './LaunchVideo';
import {DURATION, FPS} from './timeline';
import {MacDesktop} from './ui/MacDesktop';
import {IOSOverview} from './ui/IOSOverview';
import {AppIcon} from './ui/AppIcon';
import {PhoneScreen} from './ui/PhoneScreen';
import {usageAt} from './timeline';

export const Root: React.FC = () => (
  <>
    <Composition id="Launch16x9" component={LaunchVideo} durationInFrames={DURATION} fps={FPS} width={3840} height={2160} />
    <Composition id="Launch16x9Preview" component={LaunchVideo} durationInFrames={DURATION} fps={FPS} width={1920} height={1080} />
    <Still id="MacStill" width={1180} height={767} component={() => (
      <MacDesktop frame={380} usage={usageAt(380)} popover={1} cursor={{x: 0, y: 0, opacity: 0, press: 0}} />)} />
    <Still id="IOSStill" width={420} height={912} component={() => (
      <IOSOverview usage={usageAt(600)} claudeGlow={0} notification={1} frame={600} />)} />
    <Still id="PhoneChatStill" width={420} height={912} component={() => <PhoneScreen frame={1060} usage={usageAt(1060)} claudeGlow={0} />} />
    <Still id="IconStill" width={400} height={400} component={() => <div style={{padding: 50}}><AppIcon size={300} /></div>} />
  </>
);
