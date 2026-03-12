// Tier limits — единый источник правды
const LIMITS = {
  free:        { txPerMonth: 25, invoicesPerMonth: 5 },
  ip:          { txPerMonth: Infinity, invoicesPerMonth: Infinity },
  accountant:  { txPerMonth: Infinity, invoicesPerMonth: Infinity },
  corporate:   { txPerMonth: Infinity, invoicesPerMonth: Infinity },
};

function limitsFor(tier) {
  return LIMITS[tier] ?? LIMITS.free;
}

module.exports = { limitsFor };
