import {type Ease} from './anim';

export type Cam = {x: number; y: number; z: number};

// Blend two camera states; zoom interpolates in log space so pushes feel even.
export function blendCam(a: Cam, b: Cam, t: number): Cam {
  return {x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: Math.exp(Math.log(a.z) + (Math.log(b.z) - Math.log(a.z)) * t)};
}

export type Shot = {at: number; cam: (frame: number) => Cam; ease?: Ease; blend?: number};

// Each shot starts at `at` and blends in from the previous shot over `blend` frames.
export function cameraAt(frame: number, shots: Shot[], ease: Ease): Cam {
  let cam = shots[0].cam(frame);
  for (let i = 1; i < shots.length; i++) {
    const s = shots[i];
    if (frame < s.at) break;
    const t = Math.min(1, (frame - s.at) / (s.blend ?? 60));
    cam = blendCam(cam, s.cam(frame), (s.ease ?? ease)(t));
  }
  return cam;
}
