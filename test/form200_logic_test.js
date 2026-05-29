// Node-репликация логики form200_service.dart для проверки расчётов
// (локально dart.exe заблокирован Device Guard, поэтому проверяем математику тут).
// Формулы и константы скопированы 1:1 из form200_service.dart + kz_tax_constants.dart.

// ─── Константы НК РК 2026 (defaults из kz_tax_constants.dart) ───
const MRP = 4325.0;
const MZP = 85000.0;
const employeeOpvRate = 0.10;
const employeeVosmsRate = 0.02;
const ipnMonthlyDeduction = MRP * 30;        // 30 МРП
const generalIpnRate = 0.10;
const employerSoRate = 0.05;
const employerVosmsRate = 0.03;
const employeeSocialTaxRate = 0.095;          // СН ставка (config)
const ipSocialTaxMrpSelf = 2.0;
const ipSocialTaxMrpPerEmployee = 1.0;

const min = Math.min, max = Math.max;

function calcEmployeeMonth(g) {
  if (g <= 0) return { ipn: 0, opv: 0, sn: 0, so: 0, oosms: 0, vosms: 0 };
  const opv = min(g, MZP * 50) * employeeOpvRate;
  const vosms = min(g, MZP * 20) * employeeVosmsRate;
  const ipnTaxable = max(0, g - opv - ipnMonthlyDeduction);
  const ipn = ipnTaxable * generalIpnRate;
  const soBase = max(MZP, min(g - opv, MZP * 7));
  const so = soBase * employerSoRate;
  const oosms = min(g, MZP * 40) * employerVosmsRate;
  const snBase = max(0, g - opv);
  const sn = max(0, snBase * employeeSocialTaxRate - so);
  return { ipn, opv, sn, so, oosms, vosms };
}

function round2(v) { return Math.round(v * 100) / 100; }

function calcQuarter(employees, kind) {
  // employees: array of monthly salaries (one entry per employee, same all 3 months)
  const agg = [0,1,2].map(() => ({ ipn:0, opv:0, sn:0, so:0, oosms:0, vosms:0 }));
  for (let m = 0; m < 3; m++) {
    for (const g of employees) {
      const r = calcEmployeeMonth(g);
      for (const k of ['ipn','opv','sn','so','oosms','vosms']) agg[m][k] += r[k];
    }
    if (kind === 'ip') {
      agg[m].sn = MRP * (ipSocialTaxMrpSelf + ipSocialTaxMrpPerEmployee * employees.length);
    }
  }
  const line = (sel) => {
    const m1 = round2(agg[0][sel]), m2 = round2(agg[1][sel]), m3 = round2(agg[2][sel]);
    return { m1, m2, m3, total: round2(m1+m2+m3) };
  };
  return {
    ipn: line('ipn'), opv: line('opv'), sn: line('sn'),
    so: line('so'), oosms: line('oosms'), vosms: line('vosms'),
  };
}

function fmt(n) { return new Intl.NumberFormat('ru-RU').format(n); }

function show(name, r) {
  const gt = r.ipn.total + r.opv.total + r.sn.total + r.so.total + r.oosms.total + r.vosms.total;
  console.log(`\n=== ${name} ===`);
  console.log(`  ИПН   (001): мес ${fmt(r.ipn.m1)} | квартал ${fmt(r.ipn.total)}`);
  console.log(`  ОПВ   (002): мес ${fmt(r.opv.m1)} | квартал ${fmt(r.opv.total)}`);
  console.log(`  СН    (005): мес ${fmt(r.sn.m1)} | квартал ${fmt(r.sn.total)}`);
  console.log(`  СО    (008): мес ${fmt(r.so.m1)} | квартал ${fmt(r.so.total)}`);
  console.log(`  ООСМС (010): мес ${fmt(r.oosms.m1)} | квартал ${fmt(r.oosms.total)}`);
  console.log(`  ВОСМС (011): мес ${fmt(r.vosms.m1)} | квартал ${fmt(r.vosms.total)}`);
  console.log(`  ───── ИТОГО за квартал: ${fmt(round2(gt))} ₸`);
  return r;
}

function assertEq(label, got, want) {
  const ok = Math.abs(got - want) < 0.5;
  console.log(`  [${ok ? 'OK ' : 'FAIL'}] ${label}: got ${fmt(got)}, want ${fmt(want)}`);
  if (!ok) process.exitCode = 1;
}

// ─── Сценарий 1: ТОО, 1 работник 250 000 ₸ ───
const s1 = show('ТОО · 1 работник · 250 000 ₸/мес', calcQuarter([250000], 'too'));
console.log('  Проверка месяца 1 (ручной расчёт):');
assertEq('ОПВ',   s1.opv.m1,   25000);     // 250000*10%
assertEq('ВОСМС', s1.vosms.m1, 5000);      // 250000*2%
assertEq('ИПН',   s1.ipn.m1,   9525);      // (250000-25000-129750)*10%
assertEq('СО',    s1.so.m1,    11250);     // 225000*5%
assertEq('ООСМС', s1.oosms.m1, 7500);      // 250000*3%
assertEq('СН',    s1.sn.m1,    10125);     // 225000*9.5% - 11250

// ─── Сценарий 2: ТОО, 3 работника (200к, 350к, 500к) ───
show('ТОО · 3 работника · 200к/350к/500к', calcQuarter([200000, 350000, 500000], 'too'));

// ─── Сценарий 3: ИП на ОУР, 2 работника по 180 000 ───
const s3 = show('ИП на ОУР · 2 работника · 180 000 ₸', calcQuarter([180000, 180000], 'ip'));
console.log('  Проверка СН для ИП (фикс. МРП):');
// СН = МРП * (2 за себя + 1*2 работника) = 4325 * 4 = 17300/мес
assertEq('СН ИП мес', s3.sn.m1, 17300);

// ─── Сценарий 4: высокая ЗП — проверка потолков ───
// ЗП 5 000 000: ОПВ потолок 50 МЗП = 4 250 000, СО потолок 7 МЗП, ООСМС 40 МЗП
const s4 = show('ТОО · 1 работник · 5 000 000 ₸ (проверка потолков)', calcQuarter([5000000], 'too'));
console.log('  Проверка потолков:');
assertEq('ОПВ потолок',   s4.opv.m1,   425000);   // min(5M, 50*85000=4.25M)*10% = 425000
assertEq('СО потолок',    s4.so.m1,    29750);    // 7 МЗП=595000*5% (min(5M-425000, 595000))
assertEq('ООСМС потолок', s4.oosms.m1, 102000);   // 40 МЗП=3.4M*3% = 102000

// ─── Сценарий 5: 0 сотрудников / нулевая ЗП ───
show('ТОО · 0 работников', calcQuarter([], 'too'));
show('ТОО · работник с ЗП 0', calcQuarter([0], 'too'));

console.log('\n' + (process.exitCode ? '❌ ЕСТЬ ОШИБКИ' : '✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ'));
