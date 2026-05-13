/**
 * Урок 1, формат Website Explainer 16:9 (1920×1080).
 * 9 сцен, ~2 минуты. Более развёрнуто — с практическими примерами и графиками.
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

const D = {
  intro: 9,
  mrpExplain: 11,
  mrpNumbers: 13,
  mzpNumbers: 14,
  practicalFines: 19,
  practicalLimits: 17,
  practicalPensions: 14,
  summary: 10,
  cta: 15,
};
const PAD = 3;

export const Lesson01Full: React.FC = () => {
  const { fps } = useVideoConfig();
  const f = (s: number) => Math.round(s * fps) + PAD;

  return (
    <AbsoluteFill style={{ backgroundColor: colors.background, fontFamily: fonts.body }}>
      <Audio src={staticFile('audio/lesson-01-full.mp3')} />
      <BG />
      <Header />
      <Series>
        <Series.Sequence durationInFrames={f(D.intro)}>
          <SceneIntro />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.mrpExplain)}>
          <SceneMrpExplain />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.mrpNumbers)}>
          <SceneMrpNumbers />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.mzpNumbers)}>
          <SceneMzpNumbers />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.practicalFines)}>
          <ScenePracticalExample
            title="Пример: штраф за форму 910"
            comparison={[
              { year: '2025', label: '15 МРП', amount: '58 980 ₸' },
              { year: '2026', label: '15 МРП', amount: '64 875 ₸' },
            ]}
            delta="+5 895 ₸"
          />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.practicalLimits)}>
          <ScenePracticalExample
            title="Лимит упрощёнки 910"
            comparison={[
              { year: '2025', label: '600 000 МРП', amount: '2.36 млрд ₸' },
              { year: '2026', label: '600 000 МРП', amount: '2.60 млрд ₸' },
            ]}
            delta="+236 млн ₸"
            isPositive
          />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.practicalPensions)}>
          <ScenePensions />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.summary)}>
          <SceneSummary />
        </Series.Sequence>
        <Series.Sequence durationInFrames={f(D.cta)}>
          <SceneCtaFull />
        </Series.Sequence>
      </Series>
      <Footer />
    </AbsoluteFill>
  );
};

const BG: React.FC = () => (
  <AbsoluteFill
    style={{
      background: `linear-gradient(135deg, ${colors.background} 0%, #EAF4FB 100%)`,
    }}
  />
);

const Header: React.FC = () => (
  <div
    style={{
      position: 'absolute',
      top: 30,
      left: 60,
      right: 60,
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      zIndex: 10,
    }}
  >
    <div style={{ fontSize: 28, fontWeight: 900, color: colors.primary, letterSpacing: 3 }}>
      ESEP
    </div>
    <div style={{ fontSize: 18, color: colors.textSecondary, fontWeight: 600 }}>
      Курс «НК 2026 за полчаса» · Урок 1
    </div>
  </div>
);

const Footer: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        position: 'absolute',
        bottom: 24,
        left: 60,
        right: 60,
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        fontSize: 14,
        color: colors.textSecondary,
        zIndex: 10,
        opacity: 0.85,
      }}
    >
      <div>Источник: Закон РК № 239-VIII от 08.12.2025 · adilet.zan.kz</div>
      <div style={{ fontWeight: 700 }}>esep.kz</div>
    </div>
  );
};

// ── Scenes ────────────────────────────────────────────────────────────────

const SceneIntro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const op = spring({ frame, fps, config: { damping: 12 } });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
      }}
    >
      <div style={{ textAlign: 'center', opacity: op }}>
        <div style={{ fontSize: 36, color: colors.textSecondary, marginBottom: 24, fontWeight: 600 }}>
          Урок 1
        </div>
        <div
          style={{
            fontSize: 110,
            fontWeight: 900,
            color: colors.textPrimary,
            lineHeight: 1.05,
            letterSpacing: -3,
          }}
        >
          МРП и МЗП<br />
          <span style={{ color: colors.primary }}>в 2026</span>
        </div>
        <div style={{ fontSize: 32, color: colors.textSecondary, marginTop: 40, fontWeight: 500 }}>
          Что вырастет, а что осталось как было
        </div>
      </div>
    </AbsoluteFill>
  );
};

const SceneMrpExplain: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const op = spring({ frame, fps, config: { damping: 12 } });

  const items = [
    { icon: '⚖', text: 'Штрафы' },
    { icon: '%', text: 'Лимиты режимов' },
    { icon: '🏦', text: 'Пенсии' },
    { icon: '📄', text: 'Порог НДС' },
    { icon: '🛟', text: 'Пособия' },
  ];

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
        opacity: op,
      }}
    >
      <div style={{ textAlign: 'center', maxWidth: 1400 }}>
        <div style={{ fontSize: 80, fontWeight: 900, color: colors.textPrimary, marginBottom: 16 }}>
          МРП
        </div>
        <div style={{ fontSize: 32, color: colors.textSecondary, marginBottom: 60 }}>
          месячный расчётный показатель — от него считается всё
        </div>
        <div style={{ display: 'flex', justifyContent: 'center', gap: 24, flexWrap: 'wrap' }}>
          {items.map((it, i) => {
            const delay = 20 + i * 12;
            const itOp = spring({ frame: frame - delay, fps, config: { damping: 14 } });
            return (
              <div
                key={it.text}
                style={{
                  background: colors.card,
                  borderRadius: 20,
                  padding: '32px 28px',
                  width: 220,
                  textAlign: 'center',
                  boxShadow: `0 8px 24px ${colors.primary}15`,
                  opacity: itOp,
                  transform: `scale(${itOp})`,
                }}
              >
                <div style={{ fontSize: 56, marginBottom: 12 }}>{it.icon}</div>
                <div style={{ fontSize: 24, fontWeight: 700, color: colors.textPrimary }}>{it.text}</div>
              </div>
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const SceneMrpNumbers: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const counter25 = Math.round(interpolate(frame, [0, 30], [0, 3932], { extrapolateRight: 'clamp' }));
  const counter26 = Math.round(interpolate(frame, [50, 90], [0, 4325], { extrapolateRight: 'clamp' }));
  const showArrow = frame > 90 ? spring({ frame: frame - 90, fps }) : 0;

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 80 }}>
        <BigYearCard year="2025" value={counter25} unit="₸" muted />
        <div
          style={{
            fontSize: 80,
            fontWeight: 900,
            color: colors.primary,
            opacity: showArrow,
            transform: `scale(${showArrow})`,
          }}
        >
          →
        </div>
        <BigYearCard year="2026" value={counter26} unit="₸" highlight />
      </div>
      <div
        style={{
          marginTop: 60,
          fontSize: 56,
          fontWeight: 800,
          color: colors.expense,
          opacity: showArrow,
        }}
      >
        +393 ₸ (+10%)
      </div>
    </AbsoluteFill>
  );
};

const SceneMzpNumbers: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const op = spring({ frame, fps, config: { damping: 12 } });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
        opacity: op,
      }}
    >
      <div style={{ textAlign: 'center' }}>
        <div style={{ fontSize: 36, color: colors.textSecondary, marginBottom: 30, fontWeight: 600 }}>
          А МЗП оставили
        </div>
        <div
          style={{
            fontSize: 280,
            fontWeight: 900,
            color: colors.income,
            letterSpacing: -10,
            lineHeight: 1,
          }}
        >
          85 000 ₸
        </div>
        <div
          style={{
            display: 'inline-block',
            marginTop: 40,
            padding: '20px 40px',
            background: `${colors.income}18`,
            borderRadius: 50,
            fontSize: 38,
            fontWeight: 800,
            color: colors.income,
          }}
        >
          = 0% (как в 2025)
        </div>
        <div style={{ marginTop: 50, fontSize: 28, color: colors.textSecondary, maxWidth: 1100, lineHeight: 1.5 }}>
          От МЗП считаются обязательные платежи ИП за себя: ОПВ, СО, ВОСМС.<br />
          Если бы её тоже подняли — нагрузка на ИП выросла бы вдвое.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const ScenePracticalExample: React.FC<{
  title: string;
  comparison: Array<{ year: string; label: string; amount: string }>;
  delta: string;
  isPositive?: boolean;
}> = ({ title, comparison, delta, isPositive = false }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const op = spring({ frame, fps, config: { damping: 12 } });
  const deltaColor = isPositive ? colors.income : colors.expense;

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
        opacity: op,
      }}
    >
      <div style={{ textAlign: 'center', maxWidth: 1500 }}>
        <div style={{ fontSize: 56, fontWeight: 800, color: colors.textPrimary, marginBottom: 60 }}>
          {title}
        </div>
        <div style={{ display: 'flex', justifyContent: 'center', gap: 60, marginBottom: 40 }}>
          {comparison.map((c, i) => {
            const delay = 20 + i * 25;
            const cardOp = spring({ frame: frame - delay, fps, config: { damping: 14 } });
            return (
              <div
                key={c.year}
                style={{
                  background: colors.card,
                  padding: '40px 60px',
                  borderRadius: 24,
                  boxShadow: `0 14px 40px ${colors.primary}15`,
                  opacity: cardOp,
                  transform: `translateY(${(1 - cardOp) * 30}px)`,
                  minWidth: 460,
                }}
              >
                <div style={{ fontSize: 28, color: colors.textSecondary, marginBottom: 12 }}>{c.year}</div>
                <div style={{ fontSize: 26, color: colors.textPrimary, fontWeight: 600, marginBottom: 8 }}>
                  {c.label}
                </div>
                <div style={{ fontSize: 88, fontWeight: 900, color: colors.primary, letterSpacing: -2 }}>
                  {c.amount}
                </div>
              </div>
            );
          })}
        </div>
        <div
          style={{
            display: 'inline-block',
            background: deltaColor,
            color: 'white',
            padding: '24px 60px',
            borderRadius: 60,
            fontSize: 56,
            fontWeight: 900,
          }}
        >
          {delta}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const ScenePensions: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const op = spring({ frame, fps, config: { damping: 12 } });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
        opacity: op,
      }}
    >
      <div style={{ textAlign: 'center' }}>
        <div style={{ fontSize: 56, fontWeight: 800, color: colors.textPrimary, marginBottom: 40 }}>
          🏦 Минимальная пенсия 2026
        </div>
        <div style={{ fontSize: 220, fontWeight: 900, color: colors.primary, letterSpacing: -6, lineHeight: 1 }}>
          60 398 ₸
        </div>
        <div style={{ fontSize: 30, color: colors.textSecondary, marginTop: 24, fontWeight: 500 }}>
          при стаже 33 года
        </div>
        <div
          style={{
            marginTop: 50,
            display: 'inline-block',
            background: `${colors.income}18`,
            color: colors.income,
            padding: '18px 36px',
            borderRadius: 40,
            fontSize: 36,
            fontWeight: 800,
          }}
        >
          + ~5 500 ₸ к 2025
        </div>
      </div>
    </AbsoluteFill>
  );
};

const SceneSummary: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const op = spring({ frame, fps, config: { damping: 12 } });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
        opacity: op,
      }}
    >
      <div style={{ textAlign: 'center' }}>
        <div style={{ fontSize: 60, fontWeight: 800, color: colors.textPrimary, marginBottom: 50 }}>
          Запомнили?
        </div>
        <div style={{ display: 'flex', gap: 60, justifyContent: 'center' }}>
          <BigYearCard year="МРП 2026" value={4325} unit="₸" highlight />
          <BigYearCard year="МЗП 2026" value={85000} unit="₸" color={colors.income} />
        </div>
        <div style={{ marginTop: 50, fontSize: 30, color: colors.textSecondary, fontWeight: 500 }}>
          Эти два числа вы будете умножать весь следующий год.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const SceneCtaFull: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const op = spring({ frame, fps, config: { damping: 12 } });

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        padding: `${safeZones.website.top + 40}px ${safeZones.website.right}px ${safeZones.website.bottom}px ${safeZones.website.left}px`,
        background: `linear-gradient(135deg, ${colors.gradientFrom} 0%, ${colors.gradientTo} 100%)`,
        opacity: op,
      }}
    >
      <div style={{ textAlign: 'center', color: 'white' }}>
        <div style={{ fontSize: 32, opacity: 0.85, marginBottom: 16 }}>В следующих уроках —</div>
        <div style={{ fontSize: 72, fontWeight: 900, lineHeight: 1.15, marginBottom: 50 }}>
          Упрощёнка 910 · НДС 16%<br />
          Прогрессивный ИПН · ОПВР 3.5%
        </div>
        <div style={{ fontSize: 38, opacity: 0.92, marginBottom: 50 }}>
          Подпишись на Esep — пройди весь курс бесплатно
        </div>
        <div
          style={{
            background: 'white',
            color: colors.primary,
            padding: '28px 60px',
            borderRadius: 80,
            fontSize: 52,
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

// ── Helpers ────────────────────────────────────────────────────────────────

const BigYearCard: React.FC<{
  year: string;
  value: number;
  unit: string;
  muted?: boolean;
  highlight?: boolean;
  color?: string;
}> = ({ year, value, unit, muted, highlight, color }) => {
  const c = color || (highlight ? colors.primary : muted ? colors.textSecondary : colors.textPrimary);
  return (
    <div
      style={{
        background: colors.card,
        padding: '40px 60px',
        borderRadius: 28,
        boxShadow: highlight ? `0 20px 50px ${colors.primary}30` : `0 10px 30px ${colors.primary}10`,
        border: highlight ? `3px solid ${colors.primary}` : `1px solid ${colors.textDisabled}30`,
      }}
    >
      <div style={{ fontSize: 32, color: colors.textSecondary, marginBottom: 12, fontWeight: 600 }}>{year}</div>
      <div style={{ fontSize: 130, fontWeight: 900, color: c, letterSpacing: -4, lineHeight: 0.95 }}>
        {value.toLocaleString('ru-RU')} {unit}
      </div>
    </div>
  );
};
