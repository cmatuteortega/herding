-- Counting Sheep: every balance number lives here, so the game can be tuned
-- without touching game.lua. Costs follow cost = base * growth^owned; growth
-- is 1.15 unless an item says otherwise (the multipliers grow faster, or a few
-- of them would be worth more than every generator together).
--
-- Amounts here are plain numbers; game.lua turns them into Num values.

return {
    -- Rule steps a second (the fixed timestep). Drawing runs on every frame.
    tickRate = 30,

    -- Sheep counted by one tap before any upgrade.
    tapBase = 1,

    -- The default cost growth.
    growth = 1.15,

    -- An upgrade (tap or comfort) shows up once this run has counted this
    -- share of its base cost, so the shop grows with you instead of all at once.
    revealAt = 0.5,

    tapUpgrades = {
        { id = "tapPower", name = "Tap Power", desc = "+1 sheep a tap", base = 10, growth = 1.15, add = 1 },
        { id = "betterFence", name = "Better Fence", desc = "Doubles every tap", base = 300, growth = 7, mult = 2 },
    },

    -- In unlock order: each is revealed once the one before it is owned. The
    -- rates are the brief's; the costs past the dog are raised so a night lasts
    -- 25-30 minutes (the brief's: 120, 1.2K, 14K, 180K, 2.5M ran out in 9).
    generators = {
        { id = "dog", name = "Shepherd Dog", desc = "Herds the stragglers", rate = 1, base = 15 },
        { id = "meadow", name = "Meadow", desc = "Sheep wander in to graze", rate = 8, base = 150 },
        { id = "pen", name = "Breeding Pen", desc = "More sheep. Somehow.", rate = 50, base = 2500 },
        { id = "mill", name = "Wool Mill", desc = "Wool in, pajama sheep out", rate = 300, base = 90000 },
        { id = "drones", name = "Counting Drones", desc = "They count from above", rate = 2000, base = 2e6 },
        { id = "os", name = "Sheep-OS", desc = "An AI that counts for you", rate = 15000, base = 5e7 },
    },

    -- Added up per copy owned, then multiplied with each other and with the
    -- Dream Point bonus: production = gens * (1 + barns/4) * (1 + lullabies/2) * (1 + dream).
    multipliers = {
        { id = "barn", name = "Barn", desc = "+25% all production", base = 1000, growth = 4, add = 0.25 },
        { id = "lullaby", name = "Lullaby", desc = "+50% all, and more music", base = 6000, growth = 6, add = 0.5, max = 5 },
    },

    golden = {
        firstDelay = 75, -- seconds into a run before the first one can come
        minDelay = 70, -- then one every minDelay..maxDelay seconds
        maxDelay = 140,
        crossTime = 9, -- seconds it takes to cross, and so to tap it
        rewardSeconds = 60, -- a catch is worth this much production...
        minTaps = 40, -- ...or this many taps, whichever is more (so it is worth it early)
    },

    drowsiness = {
        -- Sheep counted this run that put you to sleep.
        target = 1.5e9,
        -- The bar is (total / target) ^ curve. Production grows fast early and
        -- slowly late; a quarter power makes the bar fill at about even speed.
        curve = 0.25,
    },

    -- Each stage begins once this run has counted `at` sheep.
    stages = {
        { at = 0, name = "Dusk", title = "One fence, a few sheep" },
        { at = 2000, name = "The Field", title = "The flock grows" },
        { at = 1e6, name = "The Factory", title = "Pajamas are mandatory" },
        { at = 2e8, name = "Orbit", title = "Sheep have left the sky" },
    },

    prestige = {
        -- Dream Points = floor(sqrt(total / divisor) * (1 + catchers/2) * pace)
        divisor = 3e6,
        -- The pace bonus, the loop that compounds: a night shorter than
        -- `paceRef` seconds pays (paceRef / night) ^ pacePower times the
        -- points, at most paceMax. Quicker nights buy quicker nights.
        paceRef = 1500,
        pacePower = 0.35,
        paceMax = 8,
        -- Production per Dream Point ever earned, forever. Spending them in the
        -- Dream shop doesn't take this away.
        bonusPerPoint = 0.01,
    },

    -- The Dream shop: bought with Dream Points, kept across nights. Cost is
    -- floor(base * growth^owned). The first group plays the night for you,
    -- the second makes it shorter; together each night is quicker than the
    -- last, until it all but plays itself.
    dreamShop = {
        { id = "sleepwalk", group = "auto", name = "Sleepwalking", desc = "Taps 2 a second for you", base = 2, growth = 2, max = 5, taps = 2 },
        { id = "nightShift", group = "auto", name = "Night Shift", desc = "Buys helpers for you", base = 4, growth = 4, max = 3, tiers = 2 },
        { id = "goldenDreams", group = "auto", name = "Golden Dreams", desc = "Golden sheep come to you", base = 8, max = 1 },
        { id = "sleepTalk", group = "auto", name = "Sleep Talking", desc = "Buys tap upgrades for you", base = 10, max = 1 },
        { id = "tuckedIn", group = "auto", name = "Tucked In", desc = "Buys Barns and Lullabies", base = 16, max = 1 },
        { id = "deepSleep", group = "boost", name = "Deep Sleep", desc = "Doubles every sheep counted", base = 5, growth = 4, mult = 2 },
        { id = "dreamCatcher", group = "boost", name = "Dream Catcher", desc = "+50% Dream Points", base = 20, growth = 4, add = 0.5 },
    },

    -- What the automation does, each step.
    auto = {
        buyEvery = 0.5, -- seconds between the auto-buyers' shopping trips
        -- The most of the sheep held that one trip spends on any one thing, so
        -- the cheap helpers don't eat what the next big thing needs.
        share = 0.25,
        goldenAfter = 1.2, -- seconds a golden sheep crosses before it comes to you
    },

    -- When a night is shorter than this, the dream turns lucid: the gate to
    -- what comes after counting.
    lucid = { under = 60 },

    offline = {
        maxHours = 8,
        minSeconds = 60, -- away for less than this: no summary (the sheep still count)
    },

    save = {
        file = "save.json",
        intervalSeconds = 10,
    },

    -- The narrator under the counter: the last line whose condition holds.
    -- `total` is sheep counted this run, `own` an item owned, `drowsy` the bar (0..1).
    lines = {
        { text = "Tap the fence. Count a sheep." },
        { total = 5, text = "One... two... three..." },
        { total = 30, text = "The sheep queue politely for their turn." },
        { own = "dog", text = "A good dog. It counts with its nose." },
        { own = "meadow", text = "The meadow hums. Sheep wander in from nowhere." },
        { total = 2000, text = "You can no longer see where the field ends." },
        { own = "pen", text = "The Breeding Pen is very busy. Do not look." },
        { total = 1e6, text = "The sheep wear pajamas now. You did not ask them to." },
        { own = "mill", text = "Wool goes in. Sheep come out. Nobody knows how." },
        { own = "drones", text = "Your drones now count the drones." },
        { total = 2e8, text = "Some sheep have reached orbit. They still count." },
        { own = "os", text = "Sheep-OS has counted every sheep. Now it counts you." },
        { drowsy = 0.92, text = "Your eyelids weigh about one sheep each." },
        { drowsy = 0.97, text = "Just... one... more..." },
    },

    -- How busy the scene gets. Looks only.
    visual = {
        maxHoppers = 14, -- sheep in the air at once (taps past it still count)
        autoHopsPerSecond = 1.6, -- the most sheep the helpers send over a second
    },
}
