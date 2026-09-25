import {describe, expect, it} from 'vitest';
import {blendCam, cameraAt} from './camera';

const lin = (t: number) => t;

describe('camera', () => {
  it('interpolates zoom in log space', () => {
    expect(blendCam({x: 0, y: 0, z: 1}, {x: 0, y: 0, z: 4}, 0.5).z).toBeCloseTo(2);
  });
  it('lands exactly on each shot after its blend', () => {
    const shots = [
      {at: 0, cam: () => ({x: 0, y: 0, z: 2})},
      {at: 10, blend: 10, cam: () => ({x: 100, y: 50, z: 1})},
    ];
    expect(cameraAt(5, shots, lin)).toEqual({x: 0, y: 0, z: 2});
    expect(cameraAt(20, shots, lin)).toEqual({x: 100, y: 50, z: 1});
  });
});
