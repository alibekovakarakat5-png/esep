// ── KBK Recommender ──────────────────────────────────────────────────────────
// Функции:
//   recommendKbk(profile, paymentType)  → лучший КБК для профиля
//   listKbkForProfile(profile)          → все актуальные КБК для пользователя
//   validateKbk(profile, kbk, paymentType) → проверка на ошибку, с подсказкой
//
// Профиль:
//   {
//     entity_type:    'ip' | 'too' | 'individual',
//     regime:         'esp' | 'self_employed' | '910' | 'oyr' | 'retail' | null,
//     size_category:  'small' | 'medium' | 'large' | null,
//     has_employees:  boolean,
//     is_vat_payer:   boolean,
//   }

const { KBK, PAYMENT_TYPE_LABELS } = require('../data/kbk_directory');

function matchesProfile(applies, profile) {
  if (!applies) return true;
  if (applies.entity_type    && applies.entity_type    !== profile.entity_type)    return false;
  if (applies.regime         && applies.regime         !== profile.regime)         return false;
  if (applies.size_category  && applies.size_category  !== profile.size_category)  return false;
  if (applies.has_employees != null && applies.has_employees !== !!profile.has_employees) return false;
  if (applies.is_vat_payer  != null && applies.is_vat_payer  !== !!profile.is_vat_payer)  return false;
  return true;
}

/**
 * Возвращает массив КБК, релевантных профилю.
 * applicabilityScore — насколько точно applies_to совпал с профилем.
 */
function listKbkForProfile(profile) {
  const out = [];
  for (const k of KBK) {
    if (!matchesProfile(k.applies_to, profile)) continue;
    const score = applies_specificity(k.applies_to);
    out.push({ ...k, _score: score });
  }
  // Сортировка: сначала более специфичные совпадения
  out.sort((a, b) => b._score - a._score);
  return out;
}

function applies_specificity(applies) {
  if (!applies) return 0;
  let s = 0;
  if (applies.entity_type)    s++;
  if (applies.regime)         s++;
  if (applies.size_category)  s++;
  if (applies.has_employees != null) s++;
  if (applies.is_vat_payer  != null) s++;
  return s;
}

/**
 * Рекомендует один КБК для типа платежа в контексте профиля.
 * Возвращает { recommended, alternatives, reason }
 */
function recommendKbk(profile, paymentType) {
  const all = KBK.filter(k => k.payment_type === paymentType);
  const matched = all.filter(k => matchesProfile(k.applies_to, profile));

  if (matched.length === 0) {
    return {
      recommended: null,
      alternatives: all.map(stripScore),
      reason: `Для типа платежа "${PAYMENT_TYPE_LABELS[paymentType] || paymentType}" не найден КБК, соответствующий вашему профилю. Уточните режим налогообложения.`,
    };
  }

  // Самый специфичный
  matched.sort((a, b) => applies_specificity(b.applies_to) - applies_specificity(a.applies_to));
  const recommended = matched[0];
  const alternatives = matched.slice(1).map(stripScore);

  return {
    recommended: stripScore(recommended),
    alternatives,
    reason: buildReason(recommended, profile),
  };
}

function stripScore(k) {
  const { _score, ...rest } = k;
  return rest;
}

function buildReason(kbk, profile) {
  const parts = [];
  if (kbk.applies_to?.entity_type === 'ip')   parts.push('вы ИП');
  if (kbk.applies_to?.entity_type === 'too')  parts.push('вы ТОО');
  if (kbk.applies_to?.regime === '910')       parts.push('режим — упрощёнка');
  if (kbk.applies_to?.regime === 'oyr')       parts.push('режим — общеустановленный');
  if (kbk.applies_to?.size_category === 'small')  parts.push('малый бизнес');
  if (kbk.applies_to?.size_category === 'medium') parts.push('средний бизнес');
  if (kbk.applies_to?.size_category === 'large')  parts.push('крупный бизнес');
  if (kbk.applies_to?.has_employees === true)  parts.push('есть сотрудники');
  if (kbk.applies_to?.is_vat_payer  === true)  parts.push('плательщик НДС');
  return parts.length
    ? `Рекомендуем КБК ${kbk.code} (${kbk.label}), потому что ${parts.join(', ')}.`
    : `Рекомендуем КБК ${kbk.code} (${kbk.label}).`;
}

/**
 * Проверить введённый пользователем КБК на соответствие профилю.
 * Возвращает { ok, level: 'ok'|'warn'|'red', message, expected? }.
 */
function validateKbk(profile, code, paymentType) {
  const found = KBK.find(k => k.code === code);
  if (!found) {
    return {
      ok: false,
      level: 'warn',
      message: `КБК ${code} не найден в нашем справочнике. Проверьте платёжку — возможно, опечатка.`,
    };
  }

  // Если задан тип платежа — сравним с рекомендацией
  if (paymentType) {
    const rec = recommendKbk(profile, paymentType);
    if (rec.recommended && rec.recommended.code !== code) {
      // Конкретная ошибка
      if (matchesProfile(found.applies_to, profile)) {
        // КБК подходит профилю, но не для этого типа платежа
        return {
          ok: false,
          level: 'warn',
          message: `КБК ${code} (${found.label}) подходит вашему профилю, но он для другого типа платежа. Для "${PAYMENT_TYPE_LABELS[paymentType] || paymentType}" обычно ${rec.recommended.code} (${rec.recommended.label}).`,
          expected: rec.recommended,
        };
      }
      return {
        ok: false,
        level: 'red',
        message: `Внимание! Обычно ${entityLabel(profile)} платят "${PAYMENT_TYPE_LABELS[paymentType] || paymentType}" на КБК ${rec.recommended.code} (${rec.recommended.label}). Вы указали ${code} (${found.label}) — это возможно ошибка.`,
        expected: rec.recommended,
      };
    }
  } else {
    // Тип платежа не указан — проверим только соответствие профилю
    if (!matchesProfile(found.applies_to, profile)) {
      return {
        ok: false,
        level: 'warn',
        message: `КБК ${code} (${found.label}) обычно не используется ${entityLabel(profile)}. Уверены, что это правильный код?`,
      };
    }
  }

  return { ok: true, level: 'ok', message: 'КБК соответствует вашему профилю.' };
}

function entityLabel(profile) {
  if (profile.entity_type === 'ip')         return 'ИП';
  if (profile.entity_type === 'too')        return 'ТОО';
  if (profile.entity_type === 'individual') return 'физлица';
  return 'налогоплательщики';
}

module.exports = {
  KBK,
  PAYMENT_TYPE_LABELS,
  listKbkForProfile,
  recommendKbk,
  validateKbk,
};
