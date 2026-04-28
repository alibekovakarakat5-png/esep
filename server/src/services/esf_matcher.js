// ── Алгоритм сверки ЭСФ ↔ извещение ф.300 ────────────────────────────────────
// На вход: список ЭСФ (esf_invoice) и список строк извещения (esf_notice_row).
// На выход: расхождения по 4 категориям:
//   matched      — всё совпало
//   amount_diff  — поставщик и № совпали, но сумма НДС разнится > 1 ₸
//   only_esf     — ЭСФ есть, в извещение не попал → можно дозаявить в зачёт
//   only_notice  — в извещении есть, ЭСФ нет / отозван / аннулирован → риск отказа
//   status_red   — ЭСФ найден но статус ANNULLED/REVOKED → исключить из зачёта

const VAT_TOLERANCE_KZT = 1.00;
const DATE_TOLERANCE_DAYS = 2;

function keyOf(row) {
  // ключ: {seller_iin}|{invoice_no_normalized}
  const no = String(row.invoice_no || '').trim().replace(/^[#№]/, '').toLowerCase();
  return `${row.seller_iin || ''}|${no}`;
}

function dateDiffDays(a, b) {
  if (!a || !b) return 9999;
  const da = new Date(a), db = new Date(b);
  return Math.abs(Math.round((da - db) / 86400000));
}

function statusIsRed(s) {
  if (!s) return false;
  const u = String(s).toUpperCase();
  return u.includes('ANNUL') || u.includes('REVOK') || u.includes('ОТОЗВ') || u.includes('АННУЛ');
}

/**
 * @param {Array} esfList     — записи esf_invoice
 * @param {Array} noticeRows  — записи esf_notice_row
 * @returns {Array<{esf_id?, notice_row_id?, match_type, confidence, diff}>}
 */
function match(esfList, noticeRows) {
  const esfByKey    = new Map();
  for (const e of esfList) {
    const k = keyOf(e);
    if (!esfByKey.has(k)) esfByKey.set(k, []);
    esfByKey.get(k).push(e);
  }

  const noticeByKey = new Map();
  for (const n of noticeRows) {
    const k = keyOf(n);
    if (!noticeByKey.has(k)) noticeByKey.set(k, []);
    noticeByKey.get(k).push(n);
  }

  const consumedEsf    = new Set(); // id
  const consumedNotice = new Set(); // id
  const results = [];

  // 1) Проход: точные пары по ключу
  for (const [key, notices] of noticeByKey) {
    const esfs = esfByKey.get(key) || [];
    if (esfs.length === 0) continue;

    for (const n of notices) {
      // Найдём лучший match в esfs по сумме НДС / дате
      const candidates = esfs.filter(e => !consumedEsf.has(e.id));
      if (candidates.length === 0) break;

      let best = null;
      let bestScore = Infinity;
      for (const e of candidates) {
        const vatDiff  = Math.abs(Number(e.amount_vat) - Number(n.amount_vat || 0));
        const dateDiff = dateDiffDays(e.invoice_date, n.invoice_date);
        const score    = vatDiff * 1000 + dateDiff;
        if (score < bestScore) { bestScore = score; best = e; }
      }

      if (!best) continue;
      consumedEsf.add(best.id);
      consumedNotice.add(n.id);

      const vatDiff = Math.abs(Number(best.amount_vat) - Number(n.amount_vat || 0));
      if (statusIsRed(best.status)) {
        results.push({
          esf_id: best.id,
          notice_row_id: n.id,
          match_type: 'status_red',
          confidence: 1.0,
          diff: {
            esf_status: best.status,
            comment: 'ЭСФ отозван/аннулирован, но строка в зачёте — риск отказа',
          },
        });
      } else if (vatDiff > VAT_TOLERANCE_KZT) {
        results.push({
          esf_id: best.id,
          notice_row_id: n.id,
          match_type: 'amount_diff',
          confidence: 0.85,
          diff: {
            esf_amount_vat: Number(best.amount_vat),
            notice_amount_vat: Number(n.amount_vat || 0),
            vat_delta: Number((Number(best.amount_vat) - Number(n.amount_vat || 0)).toFixed(2)),
          },
        });
      } else {
        results.push({
          esf_id: best.id,
          notice_row_id: n.id,
          match_type: 'matched',
          confidence: 1.0,
          diff: {},
        });
      }
    }
  }

  // 2) Только в извещении — нет ЭСФ под этим ключом
  for (const n of noticeRows) {
    if (consumedNotice.has(n.id)) continue;
    results.push({
      notice_row_id: n.id,
      match_type: 'only_notice',
      confidence: 0.9,
      diff: {
        comment: 'В вашем извещении есть строка, но ЭСФ под этим № от поставщика не найден. Возможно отозван или ещё не загружен.',
      },
    });
  }

  // 3) Только в ЭСФ — пришёл, но не попал в зачёт
  for (const e of esfList) {
    if (consumedEsf.has(e.id)) continue;
    if (statusIsRed(e.status)) continue; // отозванные не считаем
    results.push({
      esf_id: e.id,
      match_type: 'only_esf',
      confidence: 0.95,
      diff: {
        comment: 'ЭСФ от поставщика есть, но в извещении его нет — можно дозаявить в зачёт.',
      },
    });
  }

  return results;
}

function buildStats(matches) {
  const by = { matched: 0, amount_diff: 0, status_red: 0, only_esf: 0, only_notice: 0 };
  let vatAtRisk = 0;
  for (const m of matches) {
    by[m.match_type] = (by[m.match_type] || 0) + 1;
    if (m.match_type === 'amount_diff') vatAtRisk += Math.abs(m.diff.vat_delta || 0);
    if (m.match_type === 'only_notice') vatAtRisk += 0; // считаем отдельно
    if (m.match_type === 'status_red') vatAtRisk += 0;
  }
  return { ...by, total: matches.length, vat_at_risk: Number(vatAtRisk.toFixed(2)) };
}

module.exports = { match, buildStats, statusIsRed };
