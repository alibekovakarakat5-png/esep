/**
 * ТЕСТ Platform API Esep — защита от превышения лимита 300 МРП/мес + валидация ИИН.
 *
 * Что проверяет (в РЕАЛЬНОСТИ, не «в коде есть»):
 *   1) Валидация ИИН — валидные принимаются, битый отклоняется.
 *   2) Защита лимита — платим водителю по кругу; система ДОЛЖНА заблокировать
 *      выплату (409 BLOCK) ровно когда накопленный доход + выплата > 1 297 500 ₸.
 *   3) Несколько «сотрудников» (водителей) — каждый со своим лимитом.
 *
 * ── ЗАПУСК ──────────────────────────────────────────────────────────────────
 *   1. Возьми свой API-ключ из кабинета app.esepkz.com/#/platform (поле «API-ключ»)
 *   2. Вставь его ниже в API_KEY  (или: set ESEP_PLATFORM_KEY=pk_xxx)
 *   3. cd C:\Users\USER\Desktop\esep
 *      node test-platform-limit.js
 *
 * Чеки уйдут в ТЕСТОВЫЙ Webkassa (devkkm) — реальных фискальных не будет.
 * ИИН каждый запуск — свежие (привязаны к времени), накопления прошлого прогона
 * не мешают. Каждая выплата с уникальным order_id (идемпотентность).
 */

'use strict';

// ── КОНФИГ ───────────────────────────────────────────────────────────────────
const API_BASE = process.env.ESEP_API_BASE || 'https://api.esepkz.com/api/platform';
const API_KEY  = process.env.ESEP_PLATFORM_KEY || 'ВСТАВЬ_СЮДА_СВОЙ_API_КЛЮЧ';

const MRP = 4325;                       // МРП 2026
const MONTHLY_LIMIT = 300 * MRP;        // 1 297 500 ₸ — лимит самозанятого/мес
const PAYOUT = 250000;                  // размер одной выплаты водителю, ₸
const DRIVERS = 5;                      // сколько «сотрудников» завести
const runId = Date.now().toString(36);  // метка прогона → свежие order_id

// ── Алгоритм контрольной цифры ИИН (как на сервере iin_algorithm.js) ──────────
function iinChecksum(d11) {
  const w1 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  let s1 = 0;
  for (let i = 0; i < 11; i++) s1 += d11[i] * w1[i];
  let c = s1 % 11;
  if (c === 10) {
    const w2 = [3, 4, 5, 6, 7, 8, 9, 10, 11, 1, 2];
    let s2 = 0;
    for (let i = 0; i < 11; i++) s2 += d11[i] * w2[i];
    c = s2 % 11;
  }
  return c; // 0..9 — валидный, 10 — такой ИИН невозможен (перегенерировать)
}

// Генерим ВАЛИДНЫЙ ИИН: 90 01 DD 3 SSSS C  (1990-01-DD, 1900-е, муж.)
function genValidIin(i) {
  const dd = String((i % 28) + 1).padStart(2, '0');
  let serial = ((Date.now() + i * 137) % 9000) + 1000;
  for (let tries = 0; tries < 30; tries++) {
    const pref = '9001' + dd + '3' + String(serial).padStart(4, '0'); // 11 цифр
    const d11 = pref.split('').map(Number);
    const c = iinChecksum(d11);
    if (c < 10) return pref + c;
    serial = (serial % 9998) + 1;
  }
  return null;
}

// Портим контрольную цифру → заведомо НЕвалидный ИИН
function makeInvalid(iin) {
  return iin.slice(0, 11) + String((Number(iin[11]) + 1) % 10);
}

// ── HTTP ─────────────────────────────────────────────────────────────────────
async function pay(iin, amount, orderId) {
  const r = await fetch(API_BASE + '/process-payment', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Platform-Key': API_KEY },
    body: JSON.stringify({ courier_iin: iin, amount, order_id: orderId, skip_taxpayer_check: true }),
  });
  let data = {};
  try { data = await r.json(); } catch (_) {}
  return { status: r.status, data };
}

async function validateIin(iin) {
  const r = await fetch(API_BASE + '/iin/validate/' + iin);
  try { return await r.json(); } catch (_) { return { valid: false }; }
}

const fmt = (n) => Math.round(Number(n) || 0).toLocaleString('ru-RU');

// ── ПРОГОН ───────────────────────────────────────────────────────────────────
(async () => {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(' ТЕСТ Platform API Esep — лимит 300 МРП/мес + валидация ИИН');
  console.log(' Лимит/мес:', fmt(MONTHLY_LIMIT), '₸  | Выплата:', fmt(PAYOUT), '₸  | API:', API_BASE);
  console.log('═══════════════════════════════════════════════════════════════\n');

  if (API_KEY.startsWith('ВСТАВЬ')) {
    console.log('❌ Не задан API_KEY. Возьми ключ в кабинете app.esepkz.com/#/platform');
    console.log('   и вставь в начало файла (API_KEY) или: set ESEP_PLATFORM_KEY=pk_xxx');
    process.exit(1);
  }

  // 1) Заводим 5 «сотрудников» (валидные ИИН)
  const drivers = [];
  for (let i = 0; i < DRIVERS; i++) drivers.push(genValidIin(i));
  console.log('👥 Заведено водителей (валидные ИИН):');
  drivers.forEach((iin, i) => console.log(`   #${i + 1}: ${iin}`));

  let iinPass = true, limitPass = true, leak = false;

  // 2) ТЕСТ ВАЛИДАЦИИ ИИН
  console.log('\n── ТЕСТ 1: валидация ИИН ──────────────────────────────────────');
  for (let i = 0; i < drivers.length; i++) {
    const v = await validateIin(drivers[i]);
    const ok = v.valid === true;
    if (!ok) iinPass = false;
    console.log(`   ${drivers[i]} → ${ok ? '✅ валиден' : '❌ ОТКЛОНЁН (а должен быть валиден!)'}`);
  }
  const badIin = makeInvalid(drivers[0]);
  const vBad = await validateIin(badIin);
  const badRejected = vBad.valid === false;
  if (!badRejected) iinPass = false;
  console.log(`   ${badIin} (битая контр.цифра) → ${badRejected ? '✅ отклонён (верно)' : '❌ ПРИНЯТ (защита ИИН не работает!)'}`);

  // 3) ТЕСТ ЛИМИТА: долбим водителя #1 выплатами пока не заблокирует
  console.log('\n── ТЕСТ 2: защита лимита 300 МРП (водитель #1) ────────────────');
  const driver = drivers[0];
  let blocked = false;
  for (let n = 1; n <= 10; n++) {
    const { status, data } = await pay(driver, PAYOUT, `t-${runId}-d1-${n}`);
    const il = data.income_limit || {};
    if (status === 200) {
      console.log(`   #${n}: ✅ PROCEED | накоплено ${fmt(il.would_be_total)}₸ (${il.percent_used_after}%) | остаток ${fmt(il.remaining_after)}₸`);
      // Проверка на «протечку»: приняли выплату, хотя итог уже выше лимита
      if (Number(il.would_be_total) > MONTHLY_LIMIT) {
        leak = true;
        console.log(`      ⚠️ ПРОТЕЧКА: итог ${fmt(il.would_be_total)}₸ > лимит ${fmt(MONTHLY_LIMIT)}₸, но выплата ПРОШЛА!`);
      }
    } else if (status === 409) {
      blocked = true;
      const correctMoment = Number(il.used_before) <= MONTHLY_LIMIT && Number(il.would_be_total) > MONTHLY_LIMIT;
      console.log(`   #${n}: 🛑 BLOCK (409) | было ${fmt(il.used_before)}₸ + ${fmt(PAYOUT)}₸ = ${fmt(il.would_be_total)}₸ > лимит ${fmt(MONTHLY_LIMIT)}₸`);
      console.log(`      ${correctMoment ? '✅ блок сработал ровно на превышении' : '❓ блок сработал, но момент странный — проверь вручную'}`);
      if (!correctMoment) limitPass = false;
      break;
    } else {
      console.log(`   #${n}: ❓ HTTP ${status} | ${JSON.stringify(data.errors || data).slice(0, 160)}`);
    }
  }
  if (!blocked) limitPass = false;
  if (leak) limitPass = false;

  // 4) Остальные водители — по одной выплате (норма)
  console.log('\n── ТЕСТ 3: выплаты остальным водителям (норма) ────────────────');
  for (let i = 1; i < drivers.length; i++) {
    const { status, data } = await pay(drivers[i], PAYOUT, `t-${runId}-d${i + 1}-1`);
    console.log(`   водитель #${i + 1}: HTTP ${status} ${status === 200 ? '✅' : '❌'} | ${data.decision || ''}`);
  }

  // ── ИТОГ ──────────────────────────────────────────────────────────────────
  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log(' ИТОГ');
  console.log(`   Валидация ИИН:        ${iinPass ? '✅ РАБОТАЕТ' : '❌ ПРОВАЛ'}`);
  console.log(`   Защита лимита 300 МРП: ${limitPass ? '✅ РАБОТАЕТ (блок сработал, протечек нет)' : '❌ ПРОВАЛ — см. выше'}`);
  console.log('═══════════════════════════════════════════════════════════════');
  process.exit(iinPass && limitPass ? 0 : 1);
})().catch((e) => {
  console.error('\n❌ Скрипт упал:', e.message);
  console.error('   Проверь: верный ли API_KEY (kабинет), доступен ли', API_BASE);
  process.exit(1);
});
