// Every piece of game math goes through Num, so the plain JS numbers here can
// be swapped for break_infinity.js (Decimal) later by rewriting this file only.
// Counts of things owned stay plain integers; amounts of sheep are Num values.

const Num = (() => {
  const from = (x) => (typeof x === 'number' ? x : Number(x) || 0);

  const add = (a, b) => a + b;
  const sub = (a, b) => a - b;
  const mul = (a, b) => a * b;
  const div = (a, b) => a / b;
  const pow = (a, b) => Math.pow(a, b);
  const gte = (a, b) => a >= b;
  const lt = (a, b) => a < b;
  const max = (a, b) => (a > b ? a : b);
  const min = (a, b) => (a < b ? a : b);
  const floor = (a) => Math.floor(a);
  const sqrt = (a) => Math.sqrt(a);
  const log10 = (a) => Math.log10(a);
  const toNumber = (a) => a;
  const zero = () => 0;

  // What n more of a thing cost, when k are owned: base * g^k * (g^n - 1) / (g - 1).
  function sumGeometric(base, growth, owned, n) {
    if (n <= 0) return 0;
    return (base * Math.pow(growth, owned) * (Math.pow(growth, n) - 1)) / (growth - 1);
  }

  // How many more can be bought with `budget`, k owned (the inverse of sumGeometric).
  function maxAffordable(base, growth, owned, budget) {
    const first = base * Math.pow(growth, owned);
    if (budget < first) return 0;
    let n = Math.floor(Math.log((budget * (growth - 1)) / first + 1) / Math.log(growth));
    // Floating point can land one either side of the edge.
    while (n > 0 && sumGeometric(base, growth, owned, n) > budget) n--;
    while (sumGeometric(base, growth, owned, n + 1) <= budget) n++;
    return n;
  }

  // 999, 1.2K, 34.5M, 678B, then 5.6e12.
  const SUFFIX = ['', 'K', 'M', 'B'];
  function format(a, decimals) {
    const x = Number(a);
    if (!isFinite(x)) return '∞';
    if (x < 0) return '-' + format(-x, decimals);
    if (x < 1000) {
      // Whole sheep, unless asked for a decimal on a small number (a rate like 1.5/s).
      if (decimals && x < 100 && x !== Math.floor(x)) return x.toFixed(1).replace(/\.0$/, '');
      return String(Math.floor(x));
    }
    let tier = Math.floor(Math.log10(x) / 3);
    if (tier < SUFFIX.length) {
      let v = x / Math.pow(1000, tier);
      let s = v < 100 ? (Math.floor(v * 10) / 10).toFixed(1).replace(/\.0$/, '') : String(Math.floor(v));
      if (s === '1000' && tier + 1 < SUFFIX.length) { tier++; s = '1'; }
      return s + SUFFIX[tier];
    }
    const e = Math.floor(Math.log10(x));
    const m = Math.floor((x / Math.pow(10, e)) * 10) / 10;
    return m.toFixed(1) + 'e' + e;
  }

  // For saves: a Num to something JSON can hold, and back.
  const serialize = (a) => a;
  const deserialize = (x) => from(x);

  return {
    from, add, sub, mul, div, pow, gte, lt, max, min, floor, sqrt, log10, toNumber, zero,
    sumGeometric, maxAffordable, format, serialize, deserialize,
  };
})();
