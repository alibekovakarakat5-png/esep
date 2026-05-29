// Node-репликация логики form300_service.dart (dart.exe заблокирован локально).
const VAT = 0.16; // НК 2026
const round2 = v => Math.round(v * 100) / 100;
const max = Math.max;

function calc(salesAmount, purchaseAmount, includeVat) {
  let netSales = salesAmount, netPurchase = purchaseAmount;
  if (includeVat) {
    netSales = salesAmount / (1 + VAT);
    netPurchase = purchaseAmount / (1 + VAT);
  }
  netSales = round2(netSales);
  netPurchase = round2(netPurchase);
  const outputVat = round2(netSales * VAT);
  const inputVat = round2(netPurchase * VAT);
  const payable = max(0, round2(outputVat - inputVat));
  const excess = max(0, round2(inputVat - outputVat));
  return { netSales, netPurchase, outputVat, inputVat, payable, excess };
}

const fmt = n => new Intl.NumberFormat('ru-RU').format(n);
function show(name, r) {
  console.log(`\n=== ${name} ===`);
  console.log(`  Оборот реализации:  ${fmt(r.netSales)} ₸`);
  console.log(`  НДС начислен (012): ${fmt(r.outputVat)} ₸`);
  console.log(`  Оборот приобретения:${fmt(r.netPurchase)} ₸`);
  console.log(`  НДС в зачёт (023):  ${fmt(r.inputVat)} ₸`);
  console.log(`  К уплате (030 I):   ${fmt(r.payable)} ₸`);
  console.log(`  Превышение (030 II):${fmt(r.excess)} ₸`);
  return r;
}
function assertEq(label, got, want) {
  const ok = Math.abs(got - want) < 0.5;
  console.log(`  [${ok ? 'OK ' : 'FAIL'}] ${label}: got ${fmt(got)}, want ${fmt(want)}`);
  if (!ok) process.exitCode = 1;
}

// Сценарий 1: продажи 10М, покупки 6М (без НДС) → к уплате
const s1 = show('Продажи 10М, покупки 6М (без НДС)', calc(10000000, 6000000, false));
assertEq('НДС начислен', s1.outputVat, 1600000);
assertEq('НДС в зачёт', s1.inputVat, 960000);
assertEq('К уплате', s1.payable, 640000);
assertEq('Превышение', s1.excess, 0);

// Сценарий 2: продажи 5М, покупки 8М → превышение зачёта
const s2 = show('Продажи 5М, покупки 8М (без НДС)', calc(5000000, 8000000, false));
assertEq('К уплате', s2.payable, 0);
assertEq('Превышение', s2.excess, 480000);

// Сценарий 3: суммы С НДС — продажи 11.6М, покупки 5.8М
const s3 = show('Продажи 11.6М, покупки 5.8М (с НДС)', calc(11600000, 5800000, true));
assertEq('Оборот реализации (выделен)', s3.netSales, 10000000);
assertEq('Оборот приобретения (выделен)', s3.netPurchase, 5000000);
assertEq('НДС начислен', s3.outputVat, 1600000);
assertEq('К уплате', s3.payable, 800000);

// Сценарий 4: нули
show('Нулевые обороты', calc(0, 0, false));

console.log('\n' + (process.exitCode ? '❌ ЕСТЬ ОШИБКИ' : '✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ'));
