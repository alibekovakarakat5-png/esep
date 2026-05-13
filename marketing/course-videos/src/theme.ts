/**
 * Бренд-палитра Esep. Согласована с приложением (lib/core/theme/app_theme.dart).
 * Используется во всех уроках курса.
 */

export const colors = {
  // Primary — KZ sky blue (бренд Esep)
  primary: '#0099CC',
  primaryDark: '#0077A8',
  primaryLight: '#33B5D9',

  // Accent — KZ gold
  gold: '#F5A623',
  goldLight: '#FFBF4D',

  // Semantic
  income: '#27AE60',
  expense: '#E74C3C',
  warning: '#F39C12',
  info: '#3498DB',

  // Surfaces
  background: '#F8FAFF',
  white: '#FFFFFF',
  card: '#FFFFFF',

  // Text
  textPrimary: '#1A1D23',
  textSecondary: '#6B7280',
  textDisabled: '#B0B7C3',

  // Gradient stops
  gradientFrom: '#0099CC',
  gradientTo: '#0077A8',
} as const;

export const fonts = {
  // Используем системные шрифты для быстрого рендера.
  // Google Fonts можно подключить через @remotion/google-fonts когда нужно.
  heading: '"Inter", "SF Pro Display", -apple-system, system-ui, sans-serif',
  body: '"Inter", -apple-system, system-ui, sans-serif',
  mono: '"JetBrains Mono", "Menlo", monospace',
};

/** Safe-zones для разных форматов (см. references/formats.md скилла) */
export const safeZones = {
  reels: {
    top: 285,
    bottom: 400,
    left: 80,
    right: 120,
    width: 1080 - 80 - 120,
    height: 1920 - 285 - 400,
  },
  website: {
    top: 60,
    bottom: 60,
    left: 80,
    right: 80,
    width: 1920 - 160,
    height: 1080 - 120,
  },
};
