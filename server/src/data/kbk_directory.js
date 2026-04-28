// ── Справочник КБК (Кодов бюджетной классификации) РК ────────────────────────
//
// Источники:
//   - Приказ Министра финансов РК "О Единой бюджетной классификации"
//   - Письма КГД о применении КБК для разных категорий налогоплательщиков
//
// Структура каждой записи:
//   code         — 6-значный КБК (как пишут в платёжке)
//   label        — короткое название
//   full_name    — официальное название
//   payment_type — внутренний тип платежа (income_tax | vat | social_tax | ...)
//   applies_to   — фильтр: для кого этот КБК актуален
//                  { entity_type?, regime?, size_category?, has_employees? }
//   law_ref      — ссылка на статью НК или приказ
//   payer_role   — 'self' (сам плательщик) | 'employer' (работодатель за работника)
//
// Размер бизнеса (Закон РК "О предпринимательстве", ст. 24):
//   small  — до 100 чел. + до 300 000 МРП оборота/год
//   medium — до 250 чел. + до 3 000 000 МРП
//   large  — всё свыше
//
// Если applies_to опущен — КБК универсальный.

const KBK = [
  // ── ИНДИВИДУАЛЬНЫЙ ПОДОХОДНЫЙ НАЛОГ ────────────────────────────────────────
  {
    code: '101101',
    label: 'ИПН по 910',
    full_name: 'Индивидуальный подоходный налог с доходов, облагаемых по упрощённой декларации',
    payment_type: 'income_tax',
    applies_to: { entity_type: 'ip', regime: '910' },
    law_ref: 'НК РК ст. 686-689',
    payer_role: 'self',
  },
  {
    code: '101201',
    label: 'ИПН с з/п работников',
    full_name: 'Индивидуальный подоходный налог с доходов, облагаемых у источника выплаты',
    payment_type: 'income_tax_employees',
    applies_to: { has_employees: true },
    law_ref: 'НК РК ст. 320, 350',
    payer_role: 'employer',
  },
  {
    code: '101202',
    label: 'ИПН (физлица, не у источника)',
    full_name: 'Индивидуальный подоходный налог с доходов, не облагаемых у источника выплаты',
    payment_type: 'income_tax_general',
    applies_to: { entity_type: 'ip', regime: 'oyr' },
    law_ref: 'НК РК ст. 320, 358',
    payer_role: 'self',
  },

  // ── КОРПОРАТИВНЫЙ ПОДОХОДНЫЙ НАЛОГ ─────────────────────────────────────────
  {
    code: '101102',
    label: 'КПН (упрощёнка для ТОО)',
    full_name: 'Корпоративный подоходный налог с юридических лиц на упрощённой декларации',
    payment_type: 'income_tax',
    applies_to: { entity_type: 'too', regime: '910' },
    law_ref: 'НК РК ст. 686-689',
    payer_role: 'self',
    note: 'Для ТОО на упрощёнке. Малый бизнес — 0% до 2028 г.',
  },
  {
    code: '101110',
    label: 'КПН (крупный бизнес)',
    full_name: 'Корпоративный подоходный налог с юридических лиц-резидентов, крупное предпринимательство',
    payment_type: 'income_tax',
    applies_to: { entity_type: 'too', regime: 'oyr', size_category: 'large' },
    law_ref: 'НК РК Раздел 7, ст. 222-313',
    payer_role: 'self',
  },
  {
    code: '101111',
    label: 'КПН (средний бизнес)',
    full_name: 'Корпоративный подоходный налог с юридических лиц-резидентов, среднее предпринимательство',
    payment_type: 'income_tax',
    applies_to: { entity_type: 'too', regime: 'oyr', size_category: 'medium' },
    law_ref: 'НК РК Раздел 7, ст. 222-313',
    payer_role: 'self',
  },
  {
    code: '101112',
    label: 'КПН (малый бизнес)',
    full_name: 'Корпоративный подоходный налог с юридических лиц-резидентов, малое предпринимательство',
    payment_type: 'income_tax',
    applies_to: { entity_type: 'too', regime: 'oyr', size_category: 'small' },
    law_ref: 'НК РК Раздел 7, ст. 222-313',
    payer_role: 'self',
  },
  {
    code: '101105',
    label: 'КПН на дивиденды',
    full_name: 'Корпоративный подоходный налог на чистый доход юридических лиц-нерезидентов',
    payment_type: 'dividend_tax',
    applies_to: { entity_type: 'too' },
    law_ref: 'НК РК ст. 320-322',
    payer_role: 'self',
  },

  // ── НДС ────────────────────────────────────────────────────────────────────
  {
    code: '105101',
    label: 'НДС',
    full_name: 'Налог на добавленную стоимость на товары, работы, услуги, реализуемые на территории РК',
    payment_type: 'vat',
    applies_to: { is_vat_payer: true },
    law_ref: 'НК РК Раздел 9, ст. 379-461',
    payer_role: 'self',
  },
  {
    code: '105102',
    label: 'НДС за нерезидента',
    full_name: 'НДС за нерезидента',
    payment_type: 'vat_nonresident',
    applies_to: { is_vat_payer: true },
    law_ref: 'НК РК ст. 415',
    payer_role: 'self',
  },

  // ── СОЦИАЛЬНЫЙ НАЛОГ ───────────────────────────────────────────────────────
  {
    code: '103101',
    label: 'Социальный налог',
    full_name: 'Социальный налог с юридических лиц и индивидуальных предпринимателей',
    payment_type: 'social_tax',
    applies_to: { has_employees: true },
    law_ref: 'НК РК Раздел 11, ст. 482-489',
    payer_role: 'employer',
    note: 'Для ТОО — 6% от ФОТ (новый НК-2026, без вычета СО). ИП на упрощёнке — 0%.',
  },

  // ── СОЦИАЛЬНЫЕ ОТЧИСЛЕНИЯ И ВЗНОСЫ ─────────────────────────────────────────
  {
    code: '104101',
    label: 'СО (соц.отчисления) за себя',
    full_name: 'Социальные отчисления в Государственный фонд социального страхования',
    payment_type: 'social_self',
    applies_to: { entity_type: 'ip' },
    law_ref: 'Закон РК "Об обязательном социальном страховании", ст. 14',
    payer_role: 'self',
    note: '5% от 1 МЗП — за ИП самого. С 2026 максимум 7 МЗП.',
  },
  {
    code: '104102',
    label: 'СО за работников',
    full_name: 'Социальные отчисления в ГФСС за наёмных работников',
    payment_type: 'social_employees',
    applies_to: { has_employees: true },
    law_ref: 'Закон РК "Об обязательном соц. страховании"',
    payer_role: 'employer',
    note: '5% от з/п работника, максимум 7 МЗП.',
  },

  // ── ПЕНСИОННЫЕ ВЗНОСЫ ──────────────────────────────────────────────────────
  {
    code: '104301',
    label: 'ОПВ за себя',
    full_name: 'Обязательные пенсионные взносы в ЕНПФ — за индивидуального предпринимателя',
    payment_type: 'pension_self',
    applies_to: { entity_type: 'ip' },
    law_ref: 'Закон РК "О пенсионном обеспечении", ст. 25',
    payer_role: 'self',
    note: '10% от 1 МЗП — за себя.',
  },
  {
    code: '104302',
    label: 'ОПВР работодателя',
    full_name: 'Обязательные пенсионные взносы работодателя в ЕНПФ',
    payment_type: 'pension_employer',
    applies_to: { has_employees: true },
    law_ref: 'Закон РК "О пенсионном обеспечении", ст. 25-1',
    payer_role: 'employer',
    note: '3.5% в 2026 (рост до 5% к 2028).',
  },
  {
    code: '104311',
    label: 'ОПВ работников',
    full_name: 'ОПВ удерживаемые из зарплаты работника',
    payment_type: 'pension_employees',
    applies_to: { has_employees: true },
    law_ref: 'Закон РК "О пенсионном обеспечении", ст. 25',
    payer_role: 'employer',
    note: '10% удерживается с з/п работника.',
  },

  // ── МЕДИЦИНСКОЕ СТРАХОВАНИЕ ────────────────────────────────────────────────
  {
    code: '104405',
    label: 'ВОСМС за себя (ИП)',
    full_name: 'Взносы на обязательное социальное медицинское страхование — самозанятый/ИП',
    payment_type: 'medical_self',
    applies_to: { entity_type: 'ip' },
    law_ref: 'Закон РК "Об обязательном соц. мед. страховании", ст. 28',
    payer_role: 'self',
    note: '5% от 1.4 МЗП за ИП самого.',
  },
  {
    code: '104406',
    label: 'ВОСМС работника',
    full_name: 'ВОСМС удерживаемые из зарплаты работника',
    payment_type: 'medical_employees',
    applies_to: { has_employees: true },
    law_ref: 'Закон РК "Об обязательном соц. мед. страховании"',
    payer_role: 'employer',
    note: '2% удерживается с з/п работника, база до 20 МЗП.',
  },
  {
    code: '104407',
    label: 'ООСМС работодателя',
    full_name: 'Отчисления работодателя на ОСМС',
    payment_type: 'medical_employer',
    applies_to: { has_employees: true },
    law_ref: 'Закон РК "Об обязательном соц. мед. страховании"',
    payer_role: 'employer',
    note: '3% работодатель платит сверху, база до 40 МЗП.',
  },

  // ── ЕСП И САМОЗАНЯТЫЕ ──────────────────────────────────────────────────────
  {
    code: '104501',
    label: 'ЕСП',
    full_name: 'Единый совокупный платёж',
    payment_type: 'esp',
    applies_to: { regime: 'esp' },
    law_ref: 'НК РК ст. 774-776',
    payer_role: 'self',
  },

  // ── ИМУЩЕСТВО, ТРАНСПОРТ, ЗЕМЛЯ ────────────────────────────────────────────
  {
    code: '104001',
    label: 'Налог на имущество (физлица)',
    full_name: 'Налог на имущество физических лиц',
    payment_type: 'property_individual',
    applies_to: { entity_type: 'individual' },
    law_ref: 'НК РК ст. 528-535',
    payer_role: 'self',
  },
  {
    code: '104002',
    label: 'Налог на имущество (юрлица)',
    full_name: 'Налог на имущество юридических лиц и индивидуальных предпринимателей',
    payment_type: 'property_legal',
    applies_to: { entity_type: 'too' },
    law_ref: 'НК РК ст. 517-527',
    payer_role: 'self',
  },
  {
    code: '104004',
    label: 'Транспортный налог (физлица)',
    full_name: 'Налог на транспортные средства с физических лиц',
    payment_type: 'transport_individual',
    applies_to: { entity_type: 'individual' },
    law_ref: 'НК РК ст. 504-510',
    payer_role: 'self',
  },
  {
    code: '104005',
    label: 'Транспортный налог (юрлица)',
    full_name: 'Налог на транспортные средства с юридических лиц',
    payment_type: 'transport_legal',
    applies_to: { entity_type: 'too' },
    law_ref: 'НК РК ст. 489-503',
    payer_role: 'self',
  },
  {
    code: '104301_zem',
    code_real: '104303',
    label: 'Земельный налог',
    full_name: 'Земельный налог',
    payment_type: 'land',
    law_ref: 'НК РК ст. 511-516',
    payer_role: 'self',
  },
];

// Нормализуем code_real -> code (для записей где есть)
for (const k of KBK) {
  if (k.code_real) { k.code = k.code_real; delete k.code_real; }
}

// ── Группы платежей по типу для UI и логики ──────────────────────────────────

const PAYMENT_TYPE_LABELS = {
  income_tax:           'Подоходный налог',
  income_tax_employees: 'ИПН с зарплаты сотрудников',
  income_tax_general:   'ИПН по ОУР',
  vat:                  'НДС',
  vat_nonresident:      'НДС за нерезидента',
  social_tax:           'Социальный налог',
  social_self:          'Социальные отчисления (СО) за себя',
  social_employees:     'СО за сотрудников',
  pension_self:         'Пенсионные взносы (ОПВ) за себя',
  pension_employer:     'Пенсионные взносы работодателя (ОПВР)',
  pension_employees:    'ОПВ удерживаемые из зарплаты',
  medical_self:         'Медстрахование (ВОСМС) за себя',
  medical_employees:    'ВОСМС работника',
  medical_employer:     'ООСМС работодателя',
  esp:                  'ЕСП (единый совокупный платёж)',
  property_individual:  'Налог на имущество (физлица)',
  property_legal:       'Налог на имущество (юрлица)',
  transport_individual: 'Транспортный налог (физлица)',
  transport_legal:      'Транспортный налог (юрлица)',
  land:                 'Земельный налог',
  dividend_tax:         'Налог на дивиденды',
};

module.exports = { KBK, PAYMENT_TYPE_LABELS };
