// Tier limits — единый источник правды
const TIER_ALIASES = {
  ip: 'solo',
  corporate: 'accountant_pro',
  accountantPro: 'accountant_pro',
};

const TIERS = ['free', 'solo', 'accountant', 'accountant_pro'];

const LIMITS = {
  free:           { txPerMonth: 10, invoicesPerMonth: 3 },
  solo:           { txPerMonth: Infinity, invoicesPerMonth: Infinity },
  accountant:     { txPerMonth: Infinity, invoicesPerMonth: Infinity },
  accountant_pro: { txPerMonth: Infinity, invoicesPerMonth: Infinity },
};

function normalizeTier(tier) {
  return TIER_ALIASES[tier] ?? tier ?? 'free';
}

function limitsFor(tier) {
  return LIMITS[normalizeTier(tier)] ?? LIMITS.free;
}

module.exports = { TIERS, normalizeTier, limitsFor };
