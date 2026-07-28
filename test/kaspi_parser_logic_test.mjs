import {headerMatches,parseAmount,parseDate,detectFormat,parseRowAmt,DEBIT,CREDIT,AMOUNT} from './kaspi_parser_harness.mjs';
let pass=0,fail=0;
const ok=(n,c)=>{ if(c){pass++;console.log('  OK  '+n);} else {fail++;console.log('  FAIL '+n);} };

console.log('\n=== 1. Короткие токены (дт/кт) не ловят чужие слова ===');
ok('«фактура» НЕ кредит', !headerMatches('Фактура',CREDIT));
ok('«документ» НЕ дебет', !headerMatches('Документ №',DEBIT));
ok('«контрагент» НЕ кредит', !headerMatches('Контрагент',CREDIT));
ok('«Дт» = дебет', headerMatches('Дт',DEBIT));
ok('«Кт» = кредит', headerMatches('Кт',CREDIT));
ok('«Оборот Дт» = дебет', headerMatches('Оборот Дт',DEBIT));
ok('«Сумма Кт, KZT» = кредит', headerMatches('Сумма Кт, KZT',CREDIT));

console.log('\n=== 2. Даты разных банков ===');
const dates={'28.07.2026':'2026-7-28','28.07.2026 14:30':'2026-7-28','28/07/2026':'2026-7-28','2026-07-28':'2026-7-28','2026-07-28T14:30:00':'2026-7-28','28.07.26':'2026-7-28','12 июля 2026':'2026-7-12','12 шілде 2026':'2026-7-12','5 Jul 2026':'2026-7-5','2026.07.28':'2026-7-28'};
for(const [inp,exp] of Object.entries(dates)) ok(`«${inp}»`, parseDate(inp)===exp);
ok('мусор не дата', parseDate('итого за период')===null);

console.log('\n=== 3. Суммы: пробелы, валюта, знаки ===');
const amts={'1 500,50':1500.5,'1500.50':1500.5,'1 500':1500,'1 500,00':1500,"1'500":1500,'1 500 ₸':1500,'1500 KZT':1500,'−1500':-1500,'(1500)':-1500,'1500-':-1500,'+1500':1500,'12 345,67 тг':12345.67,'1 234 567,89':1234567.89};
for(const [inp,exp] of Object.entries(amts)) ok(`«${inp}» → ${exp}`, parseAmount(inp)===exp);
ok('текст не сумма', parseAmount('Итого')===null);

console.log('\n=== 4. Шапки разных банков ===');
const banks={
 'Kaspi Business':['Дата','Описание','Дебет','Кредит'],
 'Halyk':['Дата операции','Назначение платежа','Сумма','Валюта'],
 'Jusan (только списания)':['Дата проводки','Получатель','Списание'],
 'БЦК (только поступления)':['Дата','Отправитель','Поступление'],
 'Forte (дт/кт)':['Дата','Контрагент','Дт','Кт'],
 'Freedom (англ)':['Date','Description','Amount'],
 'Каз':['Күні','Сипаттама','Сомасы'],
};
for(const [b,h] of Object.entries(banks)){
  const d=detectFormat(h.map(x=>x.toLowerCase()));
  ok(`${b} → распознан`, d!==null && d.date>=0);
}

console.log('\n=== 5. Доход/расход по строкам ===');
const c1=detectFormat(['дата','описание','дебет','кредит']);
ok('Kaspi: кредит=доход', parseRowAmt(['01.07.2026','Оплата','','50 000'],c1)?.isIncome===true);
ok('Kaspi: дебет=расход', parseRowAmt(['01.07.2026','Аренда','30 000',''],c1)?.isIncome===false);
const c2=detectFormat(['дата проводки','получатель','списание']);
ok('Jusan: только списание = расход', parseRowAmt(['01.07.2026','ТОО X','30 000'],c2)?.isIncome===false);
const c3=detectFormat(['дата','отправитель','поступление']);
ok('БЦК: только поступление = доход', parseRowAmt(['01.07.2026','ИП Y','50 000'],c3)?.isIncome===true);
const c4=detectFormat(['дата операции','назначение платежа','сумма']);
ok('Halyk: минус = расход', parseRowAmt(['01.07.2026','Аренда','-30 000'],c4)?.isIncome===false);
ok('Halyk: плюс = доход', parseRowAmt(['01.07.2026','Оплата','50 000'],c4)?.isIncome===true);

console.log("");
console.log("=== 6. Склонения в заголовках (регрессия) ===");
ok('«Сумма списания» = дебет', headerMatches('Сумма списания',DEBIT));
ok('«Сумма поступления» = кредит', headerMatches('Сумма поступления',CREDIT));
ok('«Списано» = дебет', headerMatches('Списано',DEBIT));
ok('«Зачислено» = кредит', headerMatches('Зачислено',CREDIT));
const c5=detectFormat(['дата','контрагент','сумма списания','сумма поступления']);
ok('дебет/кредит по склонениям различаются', c5 && c5.debit===2 && c5.credit===3);
ok('колонка суммы не дублирует дебет', c5 && c5.amount===-1);
ok('поступление=доход', parseRowAmt(['01.07.2026','ИП','','50 000'],c5)?.isIncome===true);
ok('списание=расход', parseRowAmt(['01.07.2026','ТОО','30 000',''],c5)?.isIncome===false);

console.log(`\n${'='.repeat(40)}\nПРОЙДЕНО: ${pass} | ПРОВАЛЕНО: ${fail}`);
process.exit(fail?1:0);
