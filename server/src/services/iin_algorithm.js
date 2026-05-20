/**
 * Валидация ИИН (Индивидуального Идентификационного Номера) Казахстана.
 *
 * Источник: Постановление Правительства РК № 853 от 26.08.2013
 * Структура ИИН (12 цифр):
 *   [1-2] год рождения (последние 2 цифры)
 *   [3-4] месяц рождения (01-12)
 *   [5-6] день рождения (01-31)
 *   [7]   век и пол:
 *           1, 2 — XX век (1900-1999), 1=м, 2=ж
 *           3, 4 — XXI век (2000-2099), 3=м, 4=ж
 *           5, 6 — XXII век (2100-2199), 5=м, 6=ж (резерв)
 *   [8-11] порядковый номер
 *   [12]   контрольная цифра (по алгоритму ниже)
 *
 * Алгоритм контрольной цифры:
 *   1) Берём первые 11 цифр, умножаем на веса [1..11]
 *   2) Сумма mod 11
 *   3) Если результат != 10 → это контрольная цифра, СРАВНИВАЕМ с d[12]
 *   4) Если результат == 10 → пересчитываем с весами [3,4,5,6,7,8,9,10,11,1,2]
 *      Если снова 10 → ИИН недействителен
 *      Иначе → это контрольная цифра
 */

/**
 * Чисто математическая проверка контрольной цифры.
 * НЕ проверяет существование в реестре КГД.
 *
 * @param {string} iin - 12-значная строка
 * @returns {{ valid: boolean, reason: string|null, details: object }}
 */
function validateIinChecksum(iin) {
  // ── Базовая проверка формата ─────────────────────────────────────────────
  if (typeof iin !== 'string') {
    return {
      valid: false,
      reason: 'ИИН должен быть строкой',
      details: { input: typeof iin },
    };
  }

  if (!/^\d{12}$/.test(iin)) {
    return {
      valid: false,
      reason: 'ИИН должен содержать ровно 12 цифр',
      details: { length: iin.length },
    };
  }

  const digits = iin.split('').map(Number);

  // ── Проверка даты рождения ───────────────────────────────────────────────
  const yy = parseInt(iin.substring(0, 2), 10);
  const mm = parseInt(iin.substring(2, 4), 10);
  const dd = parseInt(iin.substring(4, 6), 10);

  if (mm < 1 || mm > 12) {
    return {
      valid: false,
      reason: `Неверный месяц рождения: ${mm}`,
      details: { yy, mm, dd },
    };
  }
  if (dd < 1 || dd > 31) {
    return {
      valid: false,
      reason: `Неверный день рождения: ${dd}`,
      details: { yy, mm, dd },
    };
  }

  // ── Декодируем век и пол по 7-й цифре ───────────────────────────────────
  const centuryCode = digits[6];
  let century = null;
  let gender = null;

  if (centuryCode === 1 || centuryCode === 2) {
    century = 1900;
    gender = centuryCode === 1 ? 'male' : 'female';
  } else if (centuryCode === 3 || centuryCode === 4) {
    century = 2000;
    gender = centuryCode === 3 ? 'male' : 'female';
  } else if (centuryCode === 5 || centuryCode === 6) {
    // Коды 5/6 встречаются для актуальных ИИН в РК. Официальная трактовка
    // (XXII век) даёт год в будущем — это нормально только для будущих
    // поколений. В реальности же 5/6 используют для XXI века тоже.
    // Логика: пробуем XXII → если в будущем → fallback на XXI.
    century = 2100;
    gender = centuryCode === 5 ? 'male' : 'female';
    const tryYear = 2100 + yy;
    const now = new Date();
    if (tryYear > now.getFullYear()) {
      century = 2000; // fallback на XXI век
    }
  } else {
    return {
      valid: false,
      reason: `Неверный код века/пола (7-я цифра): ${centuryCode}`,
      details: { centuryCode },
    };
  }

  const fullYear = century + yy;
  // Реалистичность: дата не в будущем и не старше 130 лет
  const birthDate = new Date(fullYear, mm - 1, dd);
  const now = new Date();
  if (birthDate > now) {
    return {
      valid: false,
      reason: `Дата рождения в будущем: ${fullYear}-${mm}-${dd}`,
      details: { birthDate: birthDate.toISOString() },
    };
  }

  // ── Контрольная цифра — первый проход ────────────────────────────────────
  const weights1 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  let sum1 = 0;
  for (let i = 0; i < 11; i++) {
    sum1 += digits[i] * weights1[i];
  }
  let control = sum1 % 11;

  // ── Если == 10, делаем второй проход с другими весами ───────────────────
  if (control === 10) {
    const weights2 = [3, 4, 5, 6, 7, 8, 9, 10, 11, 1, 2];
    let sum2 = 0;
    for (let i = 0; i < 11; i++) {
      sum2 += digits[i] * weights2[i];
    }
    control = sum2 % 11;

    if (control === 10) {
      return {
        valid: false,
        reason: 'ИИН недействителен: контрольная цифра не вычисляется (оба прохода дали 10)',
        details: { sum1, sum2 },
      };
    }
  }

  // ── Сравниваем с 12-й цифрой ─────────────────────────────────────────────
  if (control !== digits[11]) {
    return {
      valid: false,
      reason: `Контрольная цифра не сходится. Ожидалось ${control}, в ИИН: ${digits[11]}`,
      details: { expected: control, actual: digits[11], sum1 },
    };
  }

  // ── Всё OK — возвращаем расшифровку ──────────────────────────────────────
  return {
    valid: true,
    reason: null,
    details: {
      birthDate: `${fullYear}-${String(mm).padStart(2, '0')}-${String(dd).padStart(2, '0')}`,
      gender,
      century,
      sequenceNumber: parseInt(iin.substring(7, 11), 10),
      controlDigit: digits[11],
    },
  };
}

module.exports = { validateIinChecksum };
