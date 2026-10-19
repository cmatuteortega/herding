// Counting Sheep: every balance number lives here, so the game can be tuned
// without touching game.js. Costs follow cost = base * growth^owned; growth is
// 1.15 unless an item says otherwise (the multipliers grow faster, or a few of
// them would be worth more than every generator together).
//
// Amounts here are plain numbers; game.js turns them into Num values.

const CONFIG = {
  // Logic ticks a second (the fixed timestep). Rendering runs on every frame.
  tickRate: 30,

  // Sheep counted by one tap before any upgrade.
  tapBase: 1,

  // The default cost growth.
  growth: 1.15,

  // An upgrade (tap or multiplier) shows up once this run has counted this
  // share of its base cost, so the shop grows with you instead of all at once.
  revealAt: 0.5,

  tapUpgrades: [
    { id: 'tapPower', name: 'Tap Power', desc: '+1 sheep per tap', base: 10, growth: 1.15, add: 1 },
    { id: 'betterFence', name: 'Better Fence', desc: 'Doubles every tap', base: 300, growth: 7, mult: 2 },
  ],

  // In unlock order: each is revealed once the one before it is owned.
  generators: [
    { id: 'dog', name: 'Shepherd Dog', desc: 'Herds the stragglers over', rate: 1, base: 15 },
    { id: 'meadow', name: 'Meadow', desc: 'Sheep graze, sheep wander over', rate: 8, base: 150 },
    { id: 'pen', name: 'Breeding Pen', desc: 'More sheep. Somehow.', rate: 50, base: 2500 },
    { id: 'mill', name: 'Wool Mill', desc: 'Wool in, pajama sheep out', rate: 300, base: 90000 },
    { id: 'drones', name: 'Counting Drones', desc: 'They count from above', rate: 2000, base: 2e6 },
    { id: 'os', name: 'Sheep-OS', desc: 'An AI that counts for you', rate: 15000, base: 5e7 },
  ],

  // Added together per copy owned, then multiplied with each other and with
  // the Dream Point bonus: production = sum(gens) * (1 + barn) * (1 + lullaby) * (1 + dream).
  multipliers: [
    { id: 'barn', name: 'Barn', desc: '+25% all production', base: 1000, growth: 4, add: 0.25 },
    { id: 'lullaby', name: 'Lullaby', desc: '+50% all production, and a new layer of music', base: 6000, growth: 6, add: 0.5, max: 5 },
  ],

  golden: {
    firstDelay: 75, // seconds into a run before the first one can appear
    minDelay: 70, // then a new one every minDelay..maxDelay seconds
    maxDelay: 140,
    crossTime: 9, // seconds it takes to cross the screen (and the time you have to tap it)
    rewardSeconds: 60, // a catch is worth this many seconds of production...
    minTaps: 40, // ...or this many taps, whichever is more (so it is worth something early on)
  },

  drowsiness: {
    // Total sheep counted this run that puts you to sleep.
    target: 1.5e9,
    // The bar is (total / target) ^ curve. Production grows fast early and
    // slower late, and a quarter power turns that into a bar that fills at
    // roughly even speed over a run (about 25-30 minutes).
    curve: 0.25,
  },

  // Each stage begins once this run has counted `at` sheep in total.
  stages: [
    { at: 0, name: 'Dusk', title: 'One fence, a few sheep' },
    { at: 2000, name: 'The Field', title: 'The flock grows' },
    { at: 1e6, name: 'The Factory', title: 'Pajamas are mandatory' },
    { at: 2e8, name: 'Orbit', title: 'Sheep have left the atmosphere' },
  ],

  prestige: {
    divisor: 1e5, // Dream Points = floor(sqrt(totalSheep / divisor))
    bonusPerPoint: 0.05, // +5% global production per Dream Point, forever
  },

  offline: {
    maxHours: 8,
    minSeconds: 60, // away for less than this, no summary is shown (the sheep still count)
  },

  save: {
    key: 'countingSheep.v1',
    intervalSeconds: 10,
  },

  // The narrator, under the counter: the last line whose condition holds is
  // shown. `total` is sheep counted this run, `own` an item owned, `drowsy` the bar (0..1).
  lines: [
    { text: 'Tap the fence. Count a sheep.' },
    { total: 5, text: 'One... two... three...' },
    { total: 30, text: 'The sheep queue politely for their turn.' },
    { own: 'dog', text: 'A good dog. It counts with its nose.' },
    { own: 'meadow', text: 'The meadow hums. Sheep wander in from nowhere.' },
    { total: 2000, text: 'You can no longer see where the field ends.' },
    { own: 'pen', text: 'The Breeding Pen is very busy. Do not look.' },
    { total: 1e6, text: 'The sheep are wearing pajamas now. You did not ask them to.' },
    { own: 'mill', text: 'Wool goes in. Sheep come out. Nobody knows how.' },
    { own: 'drones', text: 'Your drones now count the drones.' },
    { total: 2e8, text: 'Some sheep have achieved orbit. They are still being counted.' },
    { own: 'os', text: 'Sheep-OS has counted every sheep. It is now counting you.' },
    { drowsy: 0.92, text: 'Your eyelids weigh about one sheep each.' },
    { drowsy: 0.97, text: 'Just... one... more...' },
  ],

  // How busy the scene gets. Visual only.
  visual: {
    maxHoppers: 14, // sheep in the air at once (taps beyond it still count)
    autoHopsPerSecond: 1.6, // the most sheep the generators send over the fence a second
  },
};
