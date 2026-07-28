// Порт ключевой логики kaspi_parser.dart для проверки алгоритма (Dart заблокирован Device Guard)
const DATE=['дата','күні','кунi','куні','date','мерзім','мерзімі','опер.день','операционный день','дата проводки','дата операции','дата валютирования','дата документа'];
const AMOUNT=['сумма','сома','сомасы','amount','сумм','оборот','сумма операции','сумма в валюте','сумма платежа','мөлшер','молшер'];
const DEBIT=['дебет','debit','расход','шығыс','шыгыс','списан','снятие','дт','дб','выдач','уменьшен','исходящ','outgoing','out','төлем','тольем'];
const CREDIT=['кредит','credit','приход','кіріс','кiрiс','түсім','тусим','зачислен','поступлен','пополнен','кт','увеличен','входящ','incoming','in'];

function headerMatches(header, words){
  const h=(header||'').trim().toLowerCase();
  if(!h) return false;
  for(const w of words){
    if(w.length<=3){
      const re=new RegExp('(^|[^0-9a-zа-яёәғқңөұүһі])'+w+'([^0-9a-zа-яёәғқңөұүһі]|$)');
      if(re.test(h)) return true;
    } else if(h.includes(w)) return true;
  }
  return false;
}
const findCol=(row,words)=>row.findIndex(h=>headerMatches(h,words));

function parseAmount(s){
  if(!s) return null;
  let c=String(s).replace(/[\s   ']/g,'')
    .replace(/₸/g,'').replace(/kzt/gi,'').replace(/тенге/gi,'')
    .replace(/тңг/gi,'').replace(/тг/gi,'')
    .replace(/[−–—]/g,'-').trim();
  if(!c) return null;
  if(c.startsWith('(')&&c.endsWith(')')) c='-'+c.slice(1,-1);
  if(c.endsWith('-')) c='-'+c.slice(0,-1); else if(c.endsWith('+')) c=c.slice(0,-1);
  if(c.startsWith('+')) c=c.slice(1);
  const ci=c.lastIndexOf(','), di=c.lastIndexOf('.');
  if(ci>di) c=c.replace(/\./g,'').replace(/,/g,'.');
  else if(di>ci) c=c.replace(/,/g,'');
  const v=parseFloat(c);
  return (isNaN(v)||!/^-?\d*\.?\d+$/.test(c))?null:v;
}

const MONTHS={'янв':1,'jan':1,'қаңтар':1,'кантар':1,'фев':2,'feb':2,'ақпан':2,'акпан':2,'мар':3,'mar':3,'наурыз':3,'апр':4,'apr':4,'сәуір':4,'сауир':4,'мая':5,'май':5,'may':5,'мамыр':5,'июн':6,'jun':6,'маусым':6,'июл':7,'jul':7,'шілде':7,'шилде':7,'авг':8,'aug':8,'тамыз':8,'сен':9,'sep':9,'қыркүйек':9,'кыркуйек':9,'окт':10,'oct':10,'қазан':10,'казан':10,'ноя':11,'nov':11,'қараша':11,'караша':11,'дек':12,'dec':12,'желтоқсан':12,'желтоксан':12};
function parseDate(s){
  let t=String(s||'').trim(); if(!t) return null;
  if(t.includes('T')&&/^\d{4}-\d{2}-\d{2}T/.test(t)){const d=new Date(t); if(!isNaN(d)) return `${d.getUTCFullYear()}-${d.getUTCMonth()+1}-${d.getUTCDate()}`;}
  const m=t.match(/^(\d{1,2})\s+([^\s\d]+)\.?\s+(\d{4})$/);
  if(m){const day=+m[1],yr=+m[3],mw=m[2].toLowerCase();
    for(const k in MONTHS) if(mw.startsWith(k)){ if(day<1||day>31) return null; return `${yr}-${MONTHS[k]}-${day}`; }}
  t=t.replace(/\s+/g,' ');
  let mm;
  if((mm=t.match(/^(\d{2})\.(\d{2})\.(\d{4})(\s|$)/))) return `${mm[3]}-${+mm[2]}-${+mm[1]}`;
  if((mm=t.match(/^(\d{2})[\/\-](\d{2})[\/\-](\d{4})(\s|$)/))) return `${mm[3]}-${+mm[2]}-${+mm[1]}`;
  if((mm=t.match(/^(\d{4})[-\/\.](\d{2})[-\/\.](\d{2})(\s|$)/))) return `${mm[1]}-${+mm[2]}-${+mm[3]}`;
  if((mm=t.match(/^(\d{2})[.\/\-](\d{2})[.\/\-](\d{2})$/))) return `20${mm[3]}-${+mm[2]}-${+mm[1]}`;
  return null;
}

function detectFormat(headerRow){
  const dateIdx=findCol(headerRow,DATE); if(dateIdx<0) return null;
  const debitIdx=findCol(headerRow,DEBIT), creditIdx=findCol(headerRow,CREDIT);
  let amountIdx=findCol(headerRow,AMOUNT);
  if(amountIdx>=0&&(amountIdx===debitIdx||amountIdx===creditIdx)) amountIdx=-1;
  if(!(debitIdx>=0||creditIdx>=0)&&amountIdx<0) return null;
  return {date:dateIdx,amount:amountIdx,debit:debitIdx,credit:creditIdx};
}
function parseRowAmt(row,c){
  const credit=(c.credit>=0&&c.credit<row.length)?parseAmount(row[c.credit]):null;
  const debit=(c.debit>=0&&c.debit<row.length)?parseAmount(row[c.debit]):null;
  if(credit!==null&&Math.abs(credit)>0) return {amount:Math.abs(credit),isIncome:true};
  if(debit!==null&&Math.abs(debit)>0) return {amount:Math.abs(debit),isIncome:false};
  if(c.amount>=0&&c.amount<row.length){
    const p=parseAmount(row[c.amount]); if(p===null||p===0) return null;
    let inc=p>0; if(c.debit>=0&&c.credit<0&&p>0) inc=false;
    return {amount:Math.abs(p),isIncome:inc};
  }
  return null;
}
export {headerMatches,findCol,parseAmount,parseDate,detectFormat,parseRowAmt,DATE,AMOUNT,DEBIT,CREDIT};
