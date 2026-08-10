#!/usr/bin/env node
'use strict';
/**
 * ТЕНЕВОЙ ПИЛОТ — отчёт о рисках по выплатам курьерам (НК РК 2026).
 *
 * Прогоняет выгрузку выплат платформы через ту же логику, что и боевой Platform API,
 * и показывает найденные нарушения. НИЧЕГО НЕ БЛОКИРУЕТ и НИЧЕГО НЕ ПИШЕТ В БД —
 * расчёт полностью в памяти (данные клиента у нас не остаются; это аргумент на переговорах).
 *
 * Использование:
 *   node scripts/shadow_pilot_report.js --demo                  # сгенерить пример отчёта
 *   node scripts/shadow_pilot_report.js payments.csv            # по данным клиента
 *   node scripts/shadow_pilot_report.js payments.csv --lookup   # + проверка статуса в stat.gov.kz
 *
 * CSV (заголовки в любом порядке, лишние колонки игнорируются):
 *   iin,amount,date[,order_id][,name]
 */

const fs = require('fs');
const path = require('path');
const { validateIinChecksum } = require('../src/services/iin_algorithm');
const { DEFAULT_RATES, selfEmployedLimit } = require('../src/services/tax');

const RATES = DEFAULT_RATES;
const MRP = RATES.mrp;
const LIMIT_TENGE = selfEmployedLimit(RATES).monthlyTenge;   // 300 МРП/мес
const FINE_MIN_MRP = 15, FINE_MAX_MRP = 50;                  // штраф за операцию

const args = process.argv.slice(2);
const DEMO = args.includes('--demo');
const LOOKUP = args.includes('--lookup');
const csvPath = args.find((a) => !a.startsWith('--'));

const fmt = (n) => new Intl.NumberFormat('ru-RU').format(Math.round(n));
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const monthKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
const monthName = (k) => {
  const [y, m] = k.split('-');
  return `${['январь','февраль','март','апрель','май','июнь','июль','август','сентябрь','октябрь','ноябрь','декабрь'][+m - 1]} ${y}`;
};

// ── Ввод ─────────────────────────────────────────────────────────────────────
function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  if (lines.length < 2) return [];
  const sep = lines[0].includes(';') ? ';' : ',';
  const headers = lines[0].split(sep).map((h) => h.trim().toLowerCase().replace(/^﻿/, ''));
  return lines.slice(1).map((line) => {
    const cells = line.split(sep);
    const r = {};
    headers.forEach((h, i) => { r[h] = (cells[i] ?? '').trim(); });
    return r;
  });
}

/** Демо-данные: правдоподобный поток выплат с заложенными нарушениями. */
function demoPayments() {
  // Валидные ИИН (проверены validateIinChecksum) + намеренно битые.
  const good = ['901120150126', '870315200234', '950712150547', '881201201257', '920430100760'];
  const bad = ['901320150126', '123456789012'];  // неверный месяц (13 и 34)
  const names = ['Асхат Ж.', 'Марат С.', 'Ержан К.', 'Данияр Т.', 'Айбек Н.', 'Нурлан Б.', 'Тимур А.'];
  const rows = [];
  let n = 1;
  const push = (iin, name, amount, day) =>
    rows.push({ iin, name, amount: String(amount), date: `2026-07-${String(day).padStart(2, '0')}`, order_id: 'ORD-' + n++ });

  // Обычные курьеры — в пределах лимита
  good.slice(2).forEach((iin, i) => {
    for (let d = 2; d <= 26; d += 4) push(iin, names[i + 2], 38000 + Math.round(Math.random() * 12000), d);
  });
  // Два курьера ПРЕВЫШАЮТ лимит 300 МРП
  for (let d = 1; d <= 28; d += 2) push(good[0], names[0], 105000, d);
  for (let d = 3; d <= 27; d += 3) push(good[1], names[1], 160000, d);
  // Битые ИИН
  bad.forEach((iin, i) => { push(iin, names[5 + i], 47000, 9); push(iin, names[5 + i], 52000, 21); });
  return rows;
}

// ── Анализ ───────────────────────────────────────────────────────────────────
function analyze(rows) {
  const people = new Map();   // iin -> {iin, name, months: Map, invalidIin, payments}
  let totalAmount = 0, parsed = 0, skipped = 0;

  for (const r of rows) {
    const iin = String(r.iin || r.iin_bin || '').replace(/\D/g, '');
    const amount = Number(String(r.amount || r.sum || '').replace(/[^\d.,-]/g, '').replace(',', '.'));
    const date = new Date(r.date || r.dt || Date.now());
    if (!iin || !Number.isFinite(amount) || amount <= 0 || isNaN(date.getTime())) { skipped++; continue; }
    parsed++; totalAmount += amount;

    if (!people.has(iin)) {
      // ВАЖНО: validateIinChecksum возвращает объект { valid, reason, details }, а не boolean.
      const check = validateIinChecksum(iin);
      people.set(iin, { iin, name: r.name || '', months: new Map(),
        invalidIin: !check.valid, iinReason: check.reason, payments: 0, total: 0 });
    }
    const p = people.get(iin);
    p.payments++; p.total += amount;
    if (r.name && !p.name) p.name = r.name;
    const mk = monthKey(date);
    const m = p.months.get(mk) || { key: mk, sum: 0, count: 0, overFrom: null };
    // Фиксируем момент, когда накопительно перешагнули лимит
    if (m.sum <= LIMIT_TENGE && m.sum + amount > LIMIT_TENGE) m.overFrom = date;
    m.sum += amount; m.count++;
    p.months.set(mk, m);
  }

  const invalidIins = [...people.values()].filter((p) => p.invalidIin);
  const violations = [];
  for (const p of people.values()) {
    for (const m of p.months.values()) {
      if (m.sum > LIMIT_TENGE) {
        violations.push({ iin: p.iin, name: p.name, month: m.key, sum: m.sum, count: m.count,
          over: m.sum - LIMIT_TENGE, overFrom: m.overFrom });
      }
    }
  }
  violations.sort((a, b) => b.over - a.over);

  // Операции под риском: выплаты сверх лимита + все выплаты по битым ИИН
  const riskyOverLimit = violations.reduce((acc, v) => acc + Math.max(1, Math.round(v.count * (v.over / v.sum))), 0);
  const riskyInvalid = invalidIins.reduce((acc, p) => acc + p.payments, 0);
  const riskyOps = riskyOverLimit + riskyInvalid;

  const months = new Set([...people.values()].flatMap((p) => [...p.months.keys()]));

  return {
    parsed, skipped, totalAmount, people: people.size,
    months: [...months].sort(),
    violations, invalidIins, riskyOps,
    fineMin: riskyOps * FINE_MIN_MRP * MRP,
    fineMax: riskyOps * FINE_MAX_MRP * MRP,
  };
}

// ── Отчёт (HTML — его и отправляем клиенту) ──────────────────────────────────
function html(a, lookups) {
  const period = a.months.length ? a.months.map(monthName).join(', ') : '—';
  const rowsV = a.violations.map((v) => `<tr>
      <td class="mono">${esc(v.iin)}</td><td>${esc(v.name || '—')}</td>
      <td>${monthName(v.month)}</td><td class="num">${fmt(v.sum)}</td>
      <td class="num over">+${fmt(v.over)}</td><td class="num">${v.count}</td>
      <td>${v.overFrom ? v.overFrom.toLocaleDateString('ru-RU') : '—'}</td></tr>`).join('');
  const rowsI = a.invalidIins.map((p) => `<tr>
      <td class="mono">${esc(p.iin)}</td><td>${esc(p.name || '—')}</td>
      <td class="over">${esc(p.iinReason || 'не проходит проверку')}</td>
      <td class="num">${p.payments}</td><td class="num">${fmt(p.total)}</td></tr>`).join('');
  const rowsL = (lookups || []).map((l) => `<tr>
      <td class="mono">${esc(l.iin)}</td><td>${esc(l.status)}</td><td>${esc(l.snr || '—')}</td><td>${esc(l.oked || '—')}</td></tr>`).join('');

  return `<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8">
<title>Отчёт о рисках по выплатам курьерам — Esep</title>
<style>
 *{box-sizing:border-box;margin:0;padding:0}
 body{font:15px/1.55 -apple-system,"Segoe UI",Roboto,sans-serif;color:#16181d;background:#f4f6f8;padding:32px 18px}
 .p{max-width:940px;margin:0 auto;background:#fff;border-radius:14px;padding:40px;box-shadow:0 2px 20px rgba(0,0,0,.07)}
 h1{font-size:25px;letter-spacing:-.02em;margin-bottom:6px}
 .sub{color:#68707d;font-size:14px;margin-bottom:26px}
 .badge{display:inline-block;background:#eef7d4;color:#4a6b00;border:1px solid #d3e8a0;border-radius:100px;padding:5px 13px;font-size:12px;font-weight:600;margin-bottom:18px}
 h2{font-size:17px;margin:32px 0 12px;padding-top:20px;border-top:1px solid #e6e9ee}
 .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:22px 0}
 .c{border:1px solid #e6e9ee;border-radius:11px;padding:16px}
 .c .v{font-size:25px;font-weight:700;letter-spacing:-.02em}
 .c .l{font-size:11.5px;color:#68707d;margin-top:5px}
 .c.red{background:#fff5f5;border-color:#f3c9c9}.c.red .v{color:#c62828}
 .risk{background:#fff8e6;border:1px solid #f0d692;border-radius:12px;padding:20px;margin:22px 0}
 .risk .v{font-size:29px;font-weight:700;color:#96690a;letter-spacing:-.02em}
 .risk .l{font-size:13px;color:#7a5a10;margin-top:5px}
 table{width:100%;border-collapse:collapse;margin-top:10px;font-size:13.5px}
 th{text-align:left;background:#f7f9fb;color:#5a6472;font-size:11px;text-transform:uppercase;letter-spacing:.06em;padding:9px 10px;border-bottom:1px solid #e6e9ee}
 td{padding:9px 10px;border-bottom:1px solid #eef1f4}
 .mono{font-family:ui-monospace,Consolas,monospace;font-size:12.5px}
 .num{text-align:right;font-variant-numeric:tabular-nums}
 .over{color:#c62828;font-weight:600}
 .empty{padding:16px;color:#68707d;font-size:13.5px;background:#f7f9fb;border-radius:9px}
 ul{margin:10px 0 0 20px}li{margin-bottom:7px;font-size:14px}
 .note{margin-top:30px;padding-top:18px;border-top:1px solid #e6e9ee;font-size:12px;color:#78808d}
 @media print{body{background:#fff;padding:0}.p{box-shadow:none;padding:0}}
</style></head><body><div class="p">
 <div class="badge">ТЕНЕВОЙ ПИЛОТ · НИЧЕГО НЕ БЛОКИРОВАЛОСЬ</div>
 <h1>Отчёт о рисках по выплатам курьерам</h1>
 <div class="sub">Проверка соответствия НК РК 2026 (платформенная занятость). Период: ${esc(period)}.
   Лимит самозанятого: <b>300 МРП = ${fmt(LIMIT_TENGE)} ₸/мес</b> (МРП ${fmt(MRP)} ₸).</div>

 <div class="grid">
  <div class="c"><div class="v">${fmt(a.parsed)}</div><div class="l">выплат проверено</div></div>
  <div class="c"><div class="v">${fmt(a.people)}</div><div class="l">курьеров</div></div>
  <div class="c ${a.violations.length ? 'red' : ''}"><div class="v">${a.violations.length}</div><div class="l">превышений лимита</div></div>
  <div class="c ${a.invalidIins.length ? 'red' : ''}"><div class="v">${a.invalidIins.length}</div><div class="l">невалидных ИИН</div></div>
 </div>

 <div class="risk">
  <div class="v">${fmt(a.fineMin)} — ${fmt(a.fineMax)} ₸</div>
  <div class="l">оценка риска штрафа: ${fmt(a.riskyOps)} операций под вопросом × 15–50 МРП за операцию</div>
 </div>

 <h2>Превышение лимита 300 МРП в месяц</h2>
 ${a.violations.length ? `<table><thead><tr><th>ИИН</th><th>Курьер</th><th>Месяц</th>
   <th class="num">Начислено</th><th class="num">Сверх лимита</th><th class="num">Выплат</th><th>Лимит превышен с</th></tr></thead>
   <tbody>${rowsV}</tbody></table>
   <p style="margin-top:12px;font-size:13.5px;color:#5a6472">При превышении лимита самозанятый теряет право на СНР —
   выплаты после этой даты должны оформляться иначе. Система предупреждает <b>до</b> платежа.</p>`
  : '<div class="empty">Превышений не обнаружено.</div>'}

 <h2>Невалидные ИИН</h2>
 ${a.invalidIins.length ? `<table><thead><tr><th>ИИН</th><th>Курьер</th><th>Причина</th><th class="num">Выплат</th><th class="num">Сумма</th></tr></thead>
   <tbody>${rowsI}</tbody></table>
   <p style="margin-top:12px;font-size:13.5px;color:#5a6472">ИИН не проходит проверку по ПП РК № 853 —
   выплата оформлена на некорректный идентификатор.</p>`
  : '<div class="empty">Все ИИН прошли проверку контрольной цифры.</div>'}

 ${rowsL ? `<h2>Статус налогоплательщика (выборка)</h2>
   <table><thead><tr><th>ИИН/БИН</th><th>Статус</th><th>СНР</th><th>ОКЭД</th></tr></thead><tbody>${rowsL}</tbody></table>` : ''}

 <h2>Что это значит</h2>
 <ul>
  <li>С 2026 года платформа — <b>налоговый агент</b> за курьеров (НК РК, Закон № 214-VIII).</li>
  <li>Превышение лимита 300 МРП/мес лишает курьера права на спецрежим — выплаты нужно оформлять по-другому.</li>
  <li>Штраф — <b>15–50 МРП за каждую</b> неверно оформленную выплату.</li>
  <li>Отследить лимит вручную по сотням курьеров невозможно — нужен автоматический контроль на каждой выплате.</li>
 </ul>

 <h2>Как это предотвращается</h2>
 <ul>
  <li>Один вызов API на каждую выплату → решение <b>PROCEED / WARNING / LIMIT_REACHED</b> до перевода денег.</li>
  <li>Накопительный учёт лимита по каждому курьеру в календарном месяце.</li>
  <li>Проверка ИИН и статуса (ИП / ФЛ / самозанятый, СНР, ОКЭД).</li>
  <li>Аудит-журнал по каждой операции — для проверки КГД.</li>
 </ul>

 <div class="note">
  Отчёт подготовлен Esep (esepkz.com) в режиме теневого пилота: расчёт выполнен по предоставленной
  выгрузке, платежи не блокировались, данные в наших системах не сохранялись.
  Оценка риска штрафа — расчётная, по диапазону санкции 15–50 МРП за операцию; не является юридическим
  заключением. Ставки: МРП ${fmt(MRP)} ₸, лимит 300 МРП/мес по НК РК 2026.
  Сформировано ${new Date().toLocaleDateString('ru-RU')}.
 </div>
</div></body></html>`;
}

// ── Запуск ───────────────────────────────────────────────────────────────────
(async () => {
  let rows;
  if (DEMO) { rows = demoPayments(); console.log('Режим ДЕМО — сгенерированы примерные данные\n'); }
  else if (!csvPath) { console.error('Укажите CSV или --demo'); process.exit(1); }
  else rows = parseCsv(fs.readFileSync(csvPath, 'utf8'));

  const a = analyze(rows);

  // Опционально: реальная проверка статуса в stat.gov.kz (медленно — только выборка)
  let lookups = null;
  if (LOOKUP) {
    const { lookupTaxpayer } = require('../src/services/taxpayer_lookup');
    const sample = [...new Set(rows.map((r) => String(r.iin || '').replace(/\D/g, '')))].filter(Boolean).slice(0, 10);
    lookups = [];
    for (const iin of sample) {
      try {
        const t = await lookupTaxpayer(iin);
        lookups.push({ iin, status: t?.entity_type?.label || t?.status || 'найден', snr: t?.snr, oked: t?.oked });
      } catch { lookups.push({ iin, status: 'не найден', snr: null, oked: null }); }
    }
  }

  const out = path.join(process.cwd(), `shadow-report-${new Date().toISOString().slice(0, 10)}.html`);
  fs.writeFileSync(out, html(a, lookups), 'utf8');

  console.log('─'.repeat(58));
  console.log(`  Проверено выплат:      ${fmt(a.parsed)}${a.skipped ? `  (пропущено: ${a.skipped})` : ''}`);
  console.log(`  Курьеров:              ${fmt(a.people)}`);
  console.log(`  Сумма выплат:          ${fmt(a.totalAmount)} ₸`);
  console.log(`  Лимит 300 МРП:         ${fmt(LIMIT_TENGE)} ₸/мес`);
  console.log('─'.repeat(58));
  console.log(`  ⚠ Превышений лимита:   ${a.violations.length}`);
  console.log(`  ⚠ Невалидных ИИН:      ${a.invalidIins.length}`);
  console.log(`  ⚠ Операций под риском: ${fmt(a.riskyOps)}`);
  console.log(`  ⚠ Оценка штрафа:       ${fmt(a.fineMin)} — ${fmt(a.fineMax)} ₸`);
  console.log('─'.repeat(58));
  console.log(`\n  Отчёт: ${out}\n`);
})();
