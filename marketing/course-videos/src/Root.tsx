import React from 'react';
import { Composition } from 'remotion';
import { Lesson01Reel } from './lessons/Lesson01Reel';
import { Lesson01Full } from './lessons/Lesson01Full';

// Длительности в frames (30fps). Брать с запасом — лишние кадры подрежет
// финальный --crf или просто завершится с черным фоном.
//
// Reel: 6.5 + 9 + 10 + 6 = 31.5 сек → 945 frames + padding
// Full: 9+11+13+14+19+17+14+10+15 = 122 сек → 3660 frames + padding

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="Lesson01Reel"
        component={Lesson01Reel}
        durationInFrames={970}
        fps={30}
        width={1080}
        height={1920}
      />
      <Composition
        id="Lesson01Full"
        component={Lesson01Full}
        durationInFrames={3700}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
