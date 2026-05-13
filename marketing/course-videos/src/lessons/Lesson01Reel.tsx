/**
 * Урок 1, формат Reel 9:16 (Instagram/TikTok).
 * 4 сцены: hook → facts → impact → cta. Длительность ~30-35 сек.
 *
 * Дизайн: bold typography, инфографика с анимацией чисел,
 * минимум картинок — максимум читаемости на мобильном.
 */

import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Series,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
} from 'remotion';
import { colors, fonts, safeZones } from '../theme';

// Длительности сцен (синхр. с scenes/lesson-01.json scenes.reel)
const D = { hook: 6.5, facts: 9, impact: 10, cta: 6 };
const PAD = 3;

export const Lesson01Reel: React.FC = () => {
  const { fps } = useVideoConfig();
  const f = (s: number) => Math.round(s * fps) + PAD;

  return (
    <AbsoluteFill style={{ backgroundColor: colors.background, fontFamily: fonts.body }}>
      <Audio src={staticFile('audio/lesson-01-reel.mp3')} />
      <BackgroundPattern />

      <Series>
        <Series.Sequence durationInFrames={f(D.hook)}>
          <SceneHook />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.facts)}>
          <SceneFacts />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.impact)}>
          <SceneImpact />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.cta)}>
          <SceneCta />
        </Series.Sequence>
      </Series>

      <Watermark />
    </AbsoluteFill>
  );
};

// ── Background ─────────────────────────────────────────────────────────────

const BackgroundPattern: React.FC = () => (
  <AbsoluteFill
    style={{
      background: `radial-gradient(ellipse at top, ${colors.primary}15 0%, ${colors.background} 60%)`,
    }}
  />
);

const Watermark: React.FC = () => (
  <div
    style={{
      position: 'absolute',
      top: 60,
      right: 60,
      color: colors.primary,
      fontSize: 28,
      fontWeight: 800,
      letterSpacing: 2,
      fontFamily: fonts.heading,
      opacity: 0.85,
    }}
  >
    ESEP
  </div>
);

// ── Scene 1: Hook ──────────────────────────────────────────────────────────

const SceneHook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const fadeIn = spring({ frame, fps, config: { damping: 14 } });
  const numberScale = spring({ frame: frame - 12, fps, config: { damping: 10 } });
  const subY = interpolate(frame, [25, 45], [40, 0], {
    extrapolateRight: 'clamp',
  });
  const subOpacity = interpolate(frame, [25, 45], [0, 1], { extrapolateRight: 'clamp' });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.reels.top}px ${safeZones.reels.right}px ${safeZones.reels.bottom}px ${safeZones.reels.left}px`,
      }}
    >
      <div style={{ textAlign: 'center', opacity: fadeIn }}>
        <div
          style={{
            fontSize: 56,
            fontWeight: 600,
            color: colors.textSecondary,
            lineHeight: 1.1,
            marginBottom: 20,
          }}
        >
          МРП вырос
        </div>
        <div
          style={{
            fontSize: 280,
            fontWeight: 900,
            color: colors.primary,
            letterSpacing: -8,
            lineHeight: 0.95,
            transform: `scale(${numberScale})`,
            fontFamily: fonts.heading,
          }}
        >
          +393₸
        </div>
        <div
          style={{
            fontSize: 60,
            fontWeight: 700,
            color: colors.textPrimary,
            marginTop: 60,
            opacity: subOpacity,
            transform: `translateY(${subY}px)`,
            lineHeight: 1.2,
          }}
        >
          А за этим —<br />
          <span style={{ color: colors.expense }}>всё.</span>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ── Scene 2: Facts (animated stats) ───────────────────────────────────────

const SceneFacts: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const rows = [
    { label: 'МРП 2025', value: '3 932 ₸', change: null, color: colors.textSecondary },
    { label: 'МРП 2026', value: '4 325 ₸', change: '+10%', color: colors.primary },
    { label: 'МЗП 2026', value: '85 000 ₸', change: '= 0%', color: colors.income },
  ];

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.reels.top}px ${safeZones.reels.right}px ${safeZones.reels.bottom}px ${safeZones.reels.left}px`,
      }}
    >
      <div style={{ width: '100%', maxWidth: 880 }}>
        <div
          style={{
            fontSize: 64,
            fontWeight: 800,
            color: colors.textPrimary,
            marginBottom: 50,
            textAlign: 'center',
          }}
        >
          Цифры 2026
        </div>
        {rows.map((r, i) => {
          const delay = 15 + i * 35;
          const rowOpacity = spring({ frame: frame - delay, fps, config: { damping: 12 } });
          const rowX = interpolate(frame, [delay, delay + 20], [-50, 0], {
            extrapolateRight: 'clamp',
            extrapolateLeft: 'clamp',
          });
          return (
            <div
              key={r.label}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '32px 40px',
                marginBottom: 16,
                background: colors.card,
                borderRadius: 24,
                boxShadow: `0 10px 30px ${colors.primary}10`,
                opacity: rowOpacity,
                transform: `translateX(${rowX}px)`,
              }}
            >
              <div>
                <div style={{ fontSize: 36, fontWeight: 600, color: colors.textSecondary, marginBottom: 6 }}>
                  {r.label}
                </div>
                <div style={{ fontSize: 80, fontWeight: 900, color: r.color, letterSpacing: -2 }}>
                  {r.value}
                </div>
              </div>
              {r.change && (
                <div
                  style={{
                    fontSize: 44,
                    fontWeight: 800,
                    color: r.color,
                    background: `${r.color}18`,
                    padding: '12px 24px',
                    borderRadius: 18,
                  }}
                >
                  {r.change}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ── Scene 3: Impact list ──────────────────────────────────────────────────

const SceneImpact: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const items = [
    'Штрафы по форме 910 — выше',
    'Лимит дохода 600 000 МРП — выше',
    'Платежи ИП за себя — выше',
  ];

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        padding: `${safeZones.reels.top}px ${safeZones.reels.right}px ${safeZones.reels.bottom}px ${safeZones.reels.left}px`,
      }}
    >
      <div
        style={{
          fontSize: 72,
          fontWeight: 800,
          color: colors.textPrimary,
          marginBottom: 60,
          lineHeight: 1.1,
        }}
      >
        Что вырастет:
      </div>
      {items.map((text, i) => {
        const delay = i * 50;
        const itemOp = spring({ frame: frame - delay, fps, config: { damping: 14 } });
        const itemY = interpolate(frame, [delay, delay + 25], [60, 0], {
          extrapolateRight: 'clamp',
          extrapolateLeft: 'clamp',
        });
        return (
          <div
            key={text}
            style={{
              display: 'flex',
              alignItems: 'center',
              marginBottom: 36,
              opacity: itemOp,
              transform: `translateY(${itemY}px)`,
            }}
          >
            <div
              style={{
                width: 70,
                height: 70,
                borderRadius: 18,
                background: colors.expense,
                color: 'white',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 44,
                fontWeight: 900,
                marginRight: 28,
              }}
            >
              ↑
            </div>
            <div style={{ fontSize: 52, fontWeight: 700, color: colors.textPrimary, lineHeight: 1.2 }}>
              {text}
            </div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

// ── Scene 4: CTA (cliffhanger) ────────────────────────────────────────────

const SceneCta: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const pulse = 1 + Math.sin(frame / 8) * 0.04;
  const bgFade = spring({ frame, fps, config: { damping: 12 } });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.reels.top}px ${safeZones.reels.right}px ${safeZones.reels.bottom}px ${safeZones.reels.left}px`,
        background: `linear-gradient(160deg, ${colors.gradientFrom} 0%, ${colors.gradientTo} 100%)`,
        opacity: bgFade,
      }}
    >
      <div style={{ textAlign: 'center', color: 'white' }}>
        <div
          style={{
            fontSize: 56,
            fontWeight: 600,
            opacity: 0.85,
            marginBottom: 24,
            lineHeight: 1.2,
          }}
        >
          Полный урок —
        </div>
        <div
          style={{
            fontSize: 140,
            fontWeight: 900,
            letterSpacing: -4,
            marginBottom: 40,
            transform: `scale(${pulse})`,
            fontFamily: fonts.heading,
          }}
        >
          БЕСПЛАТНО
        </div>
        <div
          style={{
            fontSize: 44,
            fontWeight: 600,
            opacity: 0.92,
            marginBottom: 80,
            lineHeight: 1.3,
          }}
        >
          при подписке на Esep
        </div>
        <div
          style={{
            background: 'white',
            color: colors.primary,
            padding: '32px 60px',
            borderRadius: 100,
            fontSize: 56,
            fontWeight: 900,
            display: 'inline-block',
            letterSpacing: -1,
          }}
        >
          esep.kz/курс
        </div>
      </div>
    </AbsoluteFill>
  );
};
