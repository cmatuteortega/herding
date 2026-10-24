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
    -- rates are the brief's; the costs past the dog are raised so a first night
    -- lasts 18-23 minutes with the chain (the brief's: 120, 1.2K, 14K, 180K,
    -- 2.5M ran out in 9).
    generators = {
        { id = "dog", name = "Shepherd Dog", desc = "Herds the stragglers", rate = 1, base = 15 },
        { id = "meadow", name = "Meadow", desc = "Sheep wander in to graze", rate = 8, base = 150 },
        { id = "pen", name = "Breeding Pen", desc = "More sheep. Somehow.", rate = 50, base = 2500 },
        { id = "mill", name = "Wool Mill", desc = "Wool in, pajama sheep out", rate = 300, base = 90000, builds = 0.01 },
        { id = "drones", name = "Counting Drones", desc = "They count from above", rate = 2000, base = 2e6, builds = 0.01 },
        { id = "os", name = "Sheep-OS", desc = "An AI that counts for you", rate = 15000, base = 5e7, builds = 0.01 },
    },
    -- The chain (Antimatter Dimensions' trick): a helper with `builds` makes
    -- that many of the helper before it a second, each. Built helpers count
    -- like bought ones but don't raise the price, and don't stay the night.

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
        paceMax = 20,
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
        -- Warm Bed: each level, a night starts with this share of every helper
        -- you had when you fell asleep, up to all of them.
        { id = "warmBed", group = "boost", name = "Warm Bed", desc = "Keeps 20% of your helpers each night", base = 50, growth = 2, max = 5, keep = 0.2 },
        { id = "dreamCatcher", group = "boost", name = "Dream Catcher", desc = "+50% Dream Points", base = 20, growth = 4, add = 0.5 },
        -- The way you sleep: one or the other, never both. Buying the other
        -- one turns you over, and the points spent on the first come back.
        -- Light Sleeper pays the hand that taps (yours, not Sleepwalking's)
        -- and the golden sheep; Heavy Sleeper pays the helpers, and sleeps
        -- through the golden sheep.
        { id = "lightSleeper", group = "path", name = "Light Sleeper", desc = "Your taps count 20% of a second's sheep",
            base = 6, growth = 3, max = 3, tapShare = 0.2, goldenFaster = 2, other = "heavySleeper", opens = 2 },
        { id = "heavySleeper", group = "path", name = "Heavy Sleeper", desc = "Helpers x1.4. No golden sheep",
            base = 6, growth = 3, max = 3, helperMult = 1.4, other = "lightSleeper", opens = 2 },
    },

    -- Restless nights (Antimatter Dimensions' challenges): a night under a
    -- rule, started from the Dream shop. Fall asleep under it and its reward
    -- is yours forever. One opens a night, from the night `opens` dreams in.
    -- Starting one ends the night you're in, with nothing kept.
    challenges = {
        { id = "insomnia", name = "Insomnia", rule = "You need 4x the sheep to fall asleep",
            reward = "Nights need half the sheep", opens = 2, target = 4, rewardTarget = 0.5 },
        { id = "shortage", name = "Sheep Shortage", rule = "Helpers get dearer much faster (x1.3 each)",
            reward = "Helpers get dearer slower (x1.13 each)", opens = 3, growth = 1.3, rewardGrowth = 1.13 },
        { id = "wideAwake", name = "Wide Awake", rule = "The Dream shop's helpers stay in bed",
            reward = "Deep Sleep triples instead of doubling", opens = 4, noAuto = true, rewardDeep = 3 },
        { id = "coldFeet", name = "Cold Feet", rule = "No Barns or Lullabies",
            reward = "Barns and Lullabies twice as strong", opens = 5, noKind = "mult", rewardComforts = 2 },
    },

    -- What the automation does, each step.
    auto = {
        -- Seconds between the auto-buyers' shopping trips: quick, or a night
        -- near the end would be over before the first trip came back.
        buyEvery = 0.05,
        -- The most of the sheep held that one trip spends on any one thing, so
        -- the cheap helpers don't eat what the next big thing needs.
        share = 0.25,
        goldenAfter = 1.2, -- seconds a golden sheep crosses before it comes to you
    },

    -- When a night is shorter than this many seconds, the dream turns lucid:
    -- the gate to what comes after counting.
    lucid = { under = 1 },

    -- The save's shape. 1: phase 1 only. 2: the lucid phase's block, `lucid`.
    -- 3: the roots and the bouncing sheep in `lucid`, and the void. 4: phase
    -- 3 is "astral" (it was "void", a placeholder), with its block, `astral`.
    saveVersion = 4,

    -- PHASE 2, LUCID DREAMING. The night runs itself (auto-wake), six dream
    -- layers each dream the one above them (a dream within a dream), and Dream
    -- Points build a town on a grid (a city builder: where a building stands
    -- matters): phase 1's farm, the barn and the field, rebuilt piece by piece
    -- on the dream's hill. Dream Points buy upgrades kept for good too, a section
    -- for each of the dream's games.
    -- Every amount in here is a plain number; lucid/game.lua turns them into Num.
    dream = {
        -- What you start with: one sleeper on the Hill, so the first run comes
        -- in a minute (sheepPerRun / its 1 a second).
        startDims = { 1, 0, 0, 0, 0, 0 },
        -- Auto-wake: a run is over once the layers have counted this many
        -- dream sheep, so runs a second = sheep a second / sheepPerRun, and
        -- never more than runCap (Better Fences raise it).
        sheepPerRun = 60,
        runCap = 1,
        -- Dream Points a run pays, times the legacy of phase 1:
        -- 1 + log10(1 + Dream Points ever earned there) * legacyPerDecade.
        dpPerRun = 1,
        legacyPerDecade = 0.5,
        -- Every Dream Point earned in this phase lifts every layer:
        -- x(1 + sqrt(earned) * multPerRootDP). The root keeps the loop
        -- (layers, runs, points, layers) from running away.
        multPerRootDP = 0.01,
        -- Past this many runs a second there is no run to show, only the flow.
        flowAt = 30,
        -- Auto-buyers shop this often, spending at most this share of the
        -- sheep on each layer, so there's wool left to build with.
        autoEvery = 0.1,
        autoShare = 0.5,

        -- The six layers, a dream within a dream: layer 1 counts dream sheep,
        -- each deeper one dreams up sleepers in the one above it, `rate` a
        -- second each. Price in dream sheep, base * growth^bought. Deeper,
        -- time runs faster: every `bonusEvery` sleepers in a layer, its time
        -- runs `bonus` times as fast.
        bonusEvery = 10,
        bonus = 2,
        dims = {
            { name = "The Hill", sleeper = "Dream Sheep", desc = "Dream sheep, counting", rate = 1, base = 10, growth = 1.8 },
            { name = "The Clouds", sleeper = "Cloud Flock", desc = "Dreams up the Hill's sheep", rate = 0.5, base = 120, growth = 2.5 },
            { name = "The Sky Meadow", sleeper = "Sky Lamb", desc = "Dreams up the Cloud Flock", rate = 0.3, base = 3000, growth = 3.5 },
            { name = "The Moon", sleeper = "Moon Ram", desc = "Dreams up the Sky Lambs", rate = 0.2, base = 1e5, growth = 5 },
            { name = "The Stars", sleeper = "Star Shepherd", desc = "Dreams up the Moon Rams", rate = 0.15, base = 5e6, growth = 7 },
            { name = "The Aurora", sleeper = "Aurora", desc = "Dreams up the Star Shepherds", rate = 0.1, base = 4e8, growth = 10 },
        },

        -- The town: a grid, the middle `start` by `start` open at first. More
        -- land costs Dream Points, plotBase * plotGrowth^plots bought, and
        -- must touch land you have.
        grid = { w = 5, h = 5, start = 3, plotBase = 400, plotGrowth = 1.7 },
        -- A building does more for each neighbour (up, down, left, right):
        -- +sameDistrict for one of its own district, +plaza for a Haystack.
        adjacency = { sameDistrict = 0.25, plaza = 0.5 },
        -- Every building is a piece of phase 1's farm, dreamt back: the fence,
        -- the dogs, the meadow, the pen, the mill, the drones, the barn.
        -- Districts: speed (gold), auto (lilac), park (mint: the pasture),
        -- lucid (the way on). The ids are the old town's, so saves keep their farm.
        -- Price: dp and sheep, each times growth^built (levels count as
        -- built). `max` caps how many. Effects grow with S, the sum of every
        -- building of a kind's strength (its level, times its neighbours):
        -- run cap * (1 + S)^capPower, sheep a run / (1 + needDiv * S),
        -- layers * (1 + dimAdd * S), points a run * (1 + dpAdd * S). Never
        -- an exponential in S: prices are, and the effect has to lose to them.
        -- Each one built rises out of the dream's hill, where its plot is.
        buildings = {
            { id = "clock", district = "speed", name = "Better Fence", desc = "A wider fence: raises the most runs a second", dp = 250, sheep = 400, growth = 3, capPower = 1.7 },
            { id = "inn", district = "speed", name = "Dog Kennel", desc = "Sheepdogs bring the flock: fewer sheep a run", dp = 150, sheep = 100, growth = 2.5, needDiv = 1 },
            { id = "bakery", district = "speed", name = "Meadow", desc = "+50% Dream Points a run", dp = 600, sheep = 3000, growth = 2.5, dpAdd = 0.5 },
            { id = "hut", district = "auto", name = "Breeding Pen", desc = "Auto-buys sleepers for the Hill and the Clouds", dp = 500, sheep = 2000, max = 1, autoDims = { 1, 2 } },
            { id = "workshop", district = "auto", name = "Wool Mill", desc = "Auto-buys sleepers for the Sky Meadow and the Moon", dp = 8000, sheep = 5e5, max = 1, autoDims = { 3, 4 } },
            { id = "observatory", district = "auto", name = "Counting Drones", desc = "Auto-buys sleepers for the Stars and the Aurora", dp = 2e5, sheep = 2e9, max = 1, autoDims = { 5, 6 } },
            { id = "mill", district = "auto", name = "Barn", desc = "Every layer +100%", dp = 900, sheep = 1e4, growth = 4, dimAdd = 1 },
            { id = "plaza", district = "park", name = "Haystack", desc = "+50% to every building beside it", dp = 1500, sheep = 2e4, growth = 3 },
            { id = "fountain", district = "park", name = "Wishing Well", desc = "Golden sheep come 50% more often", dp = 2500, sheep = 5e4, growth = 3, max = 2, goldenAdd = 0.5 },
            { id = "fold", district = "park", name = "Sheepfold", desc = "Nightmares: a wider pen, +50% reward", dp = 2000, sheep = 3e4, growth = 3, max = 3, penAdd = 0.2, rewardAdd = 0.5 },
            -- Lucidity: the lake opens the dream challenges, and each one
            -- mastered is a step of lucidity. At its most, Sheep-OS can be
            -- bought (`lucidity`): the Gate of Horn. It takes no plot: bought
            -- from its card, the dream boots down into astral projection.
            { id = "mirror", district = "lucid", name = "Mirror Lake", desc = "Opens the dream challenges, on UPGRADES", dp = 4e5, sheep = 1e30, max = 1 },
            { id = "lighthouse", district = "lucid", name = "Sheep-OS", desc = "The Gate of Horn: out of the dream, into astral projection", dp = 3e8, sheep = 1e90, max = 1, lucidity = true, gate = true },
        },

        -- The upgrades, kept for good (in the code and the save still the
        -- `roots`): a rank at a time for Dream Points (dp * growth^rank, up to
        -- `max`). Each is in the section of what it helps, a game first: the
        -- bouncing sheep, counting sheep, the nightmares, the golden sheep,
        -- then the layers and the farm. In a section each opens once the one
        -- before it (`at`) has a rank. Then the dream challenges: the Mirror
        -- Lake (grown when the farm has one), a challenge each, opening once
        -- the one before it is mastered, and last the Gate of Horn, the way
        -- out of the dream: Sheep-OS, bought on the farm.
        sections = {
            { id = "sky", name = "THE BOUNCING SHEEP", how = "HOLD THE FIELD: IT CLIMBS" },
            { id = "count", name = "COUNTING SHEEP", how = "A FLOCK AT THE FENCE: TAP IT" },
            { id = "nightmare", name = "NIGHTMARES", how = "DRAG THE DOG: HERD THEM HOME" },
            { id = "gold", name = "THE GOLDEN SHEEP", how = "TAP IT AS IT CROSSES" },
            { id = "layers", name = "THE LAYERS" },
            { id = "town", name = "THE FARM" },
            { id = "dream", name = "DREAM CHALLENGES", how = "A DREAM UNDER A RULE" },
        },
        roots = {
            -- The bouncing sheep.
            { id = "spring", section = "sky", name = "Springy Wool", desc = "The sheep bounces 8% higher", dp = 300, growth = 3, max = 5, jumpAdd = 0.08 },
            { id = "starbag", at = "spring", section = "sky", name = "Star Bag", desc = "Stars in the sky pay +50%", dp = 2500, growth = 3, max = 5, starAdd = 0.5 },
            { id = "steps", at = "starbag", section = "sky", name = "Cloud Steps", desc = "Clouds to bounce on are 15% wider", dp = 2e4, growth = 4, max = 3, widthAdd = 0.15 },
            { id = "moonpull", at = "steps", section = "sky", name = "Moon Pull", desc = "Your best height lifts the layers 50% more", dp = 2e5, growth = 4, max = 3, recordAdd = 0.5 },
            -- Counting sheep.
            { id = "bell", section = "count", name = "Sheep Bell", desc = "A flock comes to the fence 25% more often", dp = 400, growth = 3, max = 4, flockAdd = 0.25 },
            { id = "slowsong", at = "bell", section = "count", name = "Slow Song", desc = "The beat is 15% easier to hit", dp = 3000, growth = 4, max = 3, windowAdd = 0.15 },
            { id = "lullaby", at = "slowsong", section = "count", name = "Lullaby", desc = "A song pays +50%", dp = 2e4, growth = 3, max = 5, songAdd = 0.5 },
            { id = "encore", at = "lullaby", section = "count", name = "Encore", desc = "The tune after a song lasts 50% longer", dp = 2e5, growth = 4, max = 3, tuneAdd = 0.5 },
            -- The nightmares.
            { id = "quickdog", section = "nightmare", name = "Quick Dog", desc = "The dog runs 15% faster", dp = 1500, growth = 3, max = 3, dogAdd = 0.15 },
            { id = "dog", at = "quickdog", section = "nightmare", name = "Good Dog", desc = "A flock brought home pays 25% more", dp = 1e4, growth = 3, max = 4, herdAdd = 0.25 },
            { id = "nightlight", at = "dog", section = "nightmare", name = "Night Light", desc = "The dark cloud is 20% slower", dp = 6e4, growth = 4, max = 3, cloudCut = 0.25 },
            -- The golden sheep.
            { id = "totem", section = "gold", name = "Spinning Top", desc = "A golden gift lasts 25% longer", dp = 1000, growth = 3, max = 4, giftAdd = 0.25 },
            { id = "slowgold", at = "totem", section = "gold", name = "Slow Gold", desc = "The golden sheep takes 30% longer to cross", dp = 5000, growth = 3, max = 3, crossAdd = 0.3 },
            -- The layers.
            { id = "architect", section = "layers", name = "The Architect", desc = "Every sleeper costs a third less", dp = 800, growth = 4, max = 5, costCut = 0.5 },
            { id = "well", at = "architect", section = "layers", name = "Deep Well", desc = "Your points lift the layers 50% more", dp = 8000, growth = 4, max = 5, wellAdd = 0.5 },
            { id = "dilation", at = "well", section = "layers", name = "Time Dilation", desc = "Every ten sleepers: time x0.1 faster again", dp = 9e4, growth = 5, max = 5, bonusAdd = 0.1 },
            -- The farm.
            { id = "surveyor", section = "town", name = "Surveyor", desc = "Land costs 20% less", dp = 600, growth = 3, max = 3, landCut = 0.8 },
            { id = "market", at = "surveyor", section = "town", name = "Night Market", desc = "Buildings cost half the wool", dp = 6000, growth = 4, max = 3, woolCut = 0.5 },
            { id = "bellows", at = "market", section = "town", name = "Bellows", desc = "Auto-buyers spend 10% more of the wool", dp = 6e4, growth = 4, max = 3, shareAdd = 0.1 },
            -- The dream challenges, one after the other, and the way out.
            { id = "lake", section = "dream", kind = "lake", name = "Mirror Lake", desc = "Build it on the farm: the dream challenges open" },
            { id = "c.season", at = "lake", section = "dream", kind = "challenge", challenge = "season" },
            { id = "c.stoppedClocks", at = "c.season", section = "dream", kind = "challenge", challenge = "stoppedClocks" },
            { id = "c.skyHigh", at = "c.stoppedClocks", section = "dream", kind = "challenge", challenge = "skyHigh" },
            { id = "c.onlyOne", at = "c.skyHigh", section = "dream", kind = "challenge", challenge = "onlyOne" },
            { id = "c.shallow", at = "c.onlyOne", section = "dream", kind = "challenge", challenge = "shallow" },
            { id = "c.falling", at = "c.shallow", section = "dream", kind = "challenge", challenge = "falling" },
            { id = "c.emptySquares", at = "c.falling", section = "dream", kind = "challenge", challenge = "emptySquares" },
            { id = "gate", at = "c.emptySquares", section = "dream", kind = "gate", name = "Gate of Horn", desc = "Sheep-OS, on the farm: the way out of the dream" },
        },

        -- Dream challenges, once the Mirror Lake is built, on UPGRADES: a
        -- dream under a rule. Starting one wakes the flock (the layers and
        -- dream sheep back to the start; the town and the points stay), and
        -- while it lasts the dream forgets your points: they don't lift the
        -- layers. Meet its goal under the rule and its reward is yours for
        -- good. Giving up just lifts the rule. Goals: `runs` (that many runs a
        -- second under the rule), `sheep` (that many dream sheep counted
        -- under it), `herd` (that many flocks brought home) or `height` (a
        -- climb that high, bouncing).
        challenges = {
            { id = "season", name = "Nightmare Season", rule = "Nightmares come one after another", goal = "herd", herd = 3,
                reward = "A wider fold, and nightmares pay double", nightmareEvery = 8, rewardPen = 0.5, rewardPay = 2 },
            { id = "stoppedClocks", name = "Broken Fences", rule = "Better Fences work at half strength", goal = "runs", runs = 40,
                reward = "Better Fences raise the cap faster", clockMult = 0.5, rewardCapPower = 0.15 },
            { id = "skyHigh", name = "Thin Air", rule = "The clouds are half as wide", goal = "height", height = 300,
                reward = "Stars pay double, and so does your best height", widthMult = 0.5, rewardStars = 2, rewardRecord = 2 },
            { id = "onlyOne", name = "Only One", rule = "One sleeper a layer, no more", goal = "sheep", sheep = 1e18,
                reward = "Every ten sleepers: time x2.5, not x2", dimMax = 1, rewardBonus = 2.5 },
            { id = "shallow", name = "Shallow Sleep", rule = "Only the first three layers dream", goal = "sheep", sheep = 1e20,
                reward = "The first three layers x3", layersMax = 3, rewardShallow = 3 },
            { id = "falling", name = "Falling", rule = "No auto-buyers: every sleeper by hand", goal = "runs", runs = 300,
                reward = "Every layer x2", noAuto = true, rewardLayers = 2 },
            { id = "emptySquares", name = "Empty Squares", rule = "No building helps its neighbours", goal = "runs", runs = 120,
                reward = "Neighbours of a district count double", noNeighbours = true, rewardSame = 2 },
        },

        -- The lucid golden sheep: catch it and choose one of three.
        golden = {
            firstDelay = 40, minDelay = 60, maxDelay = 110, crossTime = 10,
            frenzy = { mult = 7, seconds = 30 },    -- layers and Dream Points a run x7
            points = { seconds = 240, least = 25 }, -- Dream Points: this many seconds' worth now
            warp = { mult = 2, seconds = 60 },      -- time runs twice as fast
        },

        -- Nightmares: the flock scatters and a dark cloud comes for it. Herd
        -- it into the fold with the dog (herding's pressure field). Until it
        -- passes, runs go at half speed. Bring them all in for a reward of
        -- rewardSeconds of Dream Points, by the share saved.
        nightmare = {
            firstDelay = 200, minDelay = 240, maxDelay = 400,
            seconds = 60, sheep = 8, slow = 0.5, rewardSeconds = 180, least = 40,
        },

        -- The bouncing sheep, always in front of the field: hold a finger on
        -- the field and it climbs, doodle-jump style, cloud to cloud, towards
        -- the finger. Field units: `w` across; heights in the same units.
        -- Stars on the way pay `starSeconds` of Dream Points each (at least
        -- `starLeast`); now and then a moon is a golden gift. Falling off the
        -- bottom ends the climb. The best height ever lifts every layer:
        -- x(1 + recordPer * best / 100).
        bounce = {
            w = 100, gravity = 90, jump = 62, idleJump = 30, launch = 80, spring = 1.6,
            follow = 6, maxVx = 70, cloudW = 18, gapMin = 8, gapMax = 15,
            springChance = 0.08, darkChance = 0.12, darkFrom = 80, moveFrom = 160,
            starChance = 0.35, moonEvery = 400,
            starSeconds = 4, starLeast = 3, recordPer = 0.06,
        },

        -- Counting sheep, the rhythm game: now and then (minDelay..maxDelay,
        -- less with Sheep Bells) a flock lines up at the fence and waits
        -- `wait` seconds for you to tap it. Then `sheep` of them jump it, a
        -- beat apart, from `beat` seconds down to `beatEnd`, after a count-in
        -- of `lead` beats. Tap on each one's top: within `perfect` seconds is
        -- perfect (1), within `good` is good (`goodScore`), and a sheep let
        -- past or a tap with none near breaks the count. Over, it pays
        -- `rewardSeconds` of Dream Points (at least `least`) by the share
        -- counted, and leaves a tune: the most runs a second x(1 + tune.cap *
        -- share) for tune.seconds.
        count = {
            firstDelay = 75, minDelay = 150, maxDelay = 260, wait = 20,
            sheep = 16, beat = 0.75, beatEnd = 0.45, lead = 2,
            perfect = 0.08, good = 0.17, goodScore = 0.5,
            rewardSeconds = 45, least = 30,
            tune = { cap = 0.5, seconds = 40 },
        },
    },

    -- PHASE 3, ASTRAL PROJECTION: past the Gate of Horn (Sheep-OS). The
    -- dreamer's sheep leaves the body, tied to it by a silver cord. Drift out
    -- (the further, the faster, and the more Ether a second), but the cord
    -- strains as it goes: come back in time and the Ether is banked, with a
    -- bonus the closer to the limit you dared; let it snap and you lose half.
    -- Ether buys the cord longer and the drift quicker, then a Silver Thread
    -- that comes back by itself and a Trance that goes out again: the cord
    -- runs itself, the way the night did. Further out are the planes, the
    -- dreamers (other sleepers, dreaming Ether for you), and the
    -- constellations, lit a star at a time, each a reward kept for good. The
    -- Akashic Library remembers every sheep you ever counted, in every
    -- phase, as a multiplier. Light the Sleeper at the Edge, cut the cord,
    -- and the sheep count you: phase 4.
    -- Every amount in here is a plain number; astral/game.lua uses num.lua.
    astral = {
        -- The way in's length in seconds: Sheep-OS boots, its screen types,
        -- the digital rain falls, and the dreamer drifts up out of it. And
        -- the way out's: the cord cut, the sheep counting you, the light.
        outro = 10, ending = 14,

        -- The cord: strain = (distance / cord)^2, plus any tug. At 1 it snaps.
        cord = 60,
        -- Out, the distance grows by speed * (distance + speedFrom) a second:
        -- the further out, the faster. A projection to the end of the cord
        -- takes about log(cord) / speed seconds, however long the cord.
        speed = 0.15, speedFrom = 5,
        -- Ether a second while out: etherBase * (1 + distance)^etherPower,
        -- times the plane you're in and every multiplier.
        etherBase = 0.5, etherPower = 0.6,
        -- Back in the body: the Ether gathered is banked, times
        -- 1 + closeCall * strain^3 (a close call pays). Snapped: only
        -- 1 - snapLoss of it, and a longer rest before going out again.
        closeCall = 1, snapLoss = 0.5,
        rest = 3, snapRest = 6,
        -- Silver Thread's setting: come back at this strain. 0.5 to 0.95.
        autoAt = 0.8, autoMin = 0.5, autoMax = 0.95, autoStep = 0.05,
        -- Tugs: the body stirs (a door, a dream, a dog). Every tugMin to
        -- tugMax seconds out, strain jumps by tugLow to tugHigh, half at
        -- once and half over tugRise seconds, and drains at tugDrain a
        -- second. A tap on the dark (a breath) calms a tug by `steady`.
        tugMin = 6, tugMax = 14, tugLow = 0.1, tugHigh = 0.3, tugRise = 1.2, tugDrain = 0.04,
        steady = 0.3,
        -- Away: the dreamers dream on, and with the Thread and the Trance
        -- the cord runs at this share of how it was running.
        awayShare = 0.5,

        -- The planes: how far out (distance), what the Ether there is worth,
        -- and the sky (two palette keys, dithered).
        planes = {
            { id = "etheric", name = "The Etheric", at = 0, mult = 1, sky = { "n", "v" } },
            { id = "astral", name = "The Astral", at = 300, mult = 2, sky = { "k", "n" } },
            { id = "mental", name = "The Mental", at = 1e4, mult = 4, sky = { "u", "k" } },
            { id = "causal", name = "The Causal", at = 5e5, mult = 8, sky = { "t", "k" } },
            { id = "edge", name = "The Edge", at = 6e6, mult = 16, sky = { "p", "u" } },
        },

        -- The Akashic Library: every record of every phase, a decade at a
        -- time, adds `per` to the multiplier on all Ether: phase 1's sheep
        -- counted, phase 2's dream sheep, runs (x2), nights dreamt (a fifth
        -- each), lucidity steps, the best height (a hundredth), and the
        -- Ether earned out here (x2).
        akashic = { per = 0.02 },

        -- The dreamers: other sleepers, found out along the cord once your
        -- reach (the farthest ever) passes `at`. Bought with Ether, each
        -- dreams `rate` Ether a second, x2 every `every` of a kind, all of
        -- them x(1 + reachPer * log10(1 + reach)).
        dreamerEvery = 25, reachPer = 0.25,
        dreamers = {
            { id = "child", name = "The Child", desc = "Dreams of ponies, and of you", at = 0, rate = 0.4, base = 20, growth = 1.2 },
            { id = "shepherd", name = "The Shepherd", desc = "Counts sheep in their sleep, out of habit", at = 150, rate = 5, base = 2000, growth = 1.2 },
            { id = "insomniac", name = "The Insomniac", desc = "Barely dreams. When they do, it's vivid", at = 3e3, rate = 60, base = 1e5, growth = 1.21 },
            { id = "collie", name = "The Old Collie", desc = "Runs in its sleep, herding stars", at = 6e4, rate = 900, base = 1e7, growth = 1.22 },
            { id = "astronaut", name = "The Astronaut", desc = "Asleep in orbit. Closer than anyone", at = 4e5, rate = 1.5e4, base = 1e9, growth = 1.23 },
            { id = "moon", name = "The Moon", desc = "Dreams the tides, and every night", at = 4e6, rate = 3e5, base = 1e11, growth = 1.25 },
        },

        -- Upgrades, kept: a rank at a time for ether * growth^rank, up to
        -- `max`, each section's after the one before it (`at`) has a rank.
        sections = {
            { id = "cord", name = "THE SILVER CORD", how = "GO OUT, COME BACK IN TIME" },
            { id = "auto", name = "LETTING GO", how = "THE CORD RUNS ITSELF" },
            { id = "ether", name = "THE ETHER" },
        },
        ups = {
            { id = "cord", section = "cord", name = "Longer Cord", desc = "The cord x1.5", ether = 50, growth = 2.6, max = 40, cordMult = 1.5 },
            { id = "drift", at = "cord", section = "cord", name = "Swift Drift", desc = "Drift out 25% faster", ether = 80, growth = 3.2, max = 20, speedAdd = 0.25 },
            { id = "close", at = "drift", section = "cord", name = "Close Call", desc = "A close call pays +50% more", ether = 300, growth = 5, max = 8, closeAdd = 0.5 },
            { id = "calm", at = "close", section = "cord", name = "Calm Body", desc = "Tugs 15% softer", ether = 200, growth = 5, max = 6, calmCut = 0.85 },
            { id = "breath", at = "calm", section = "cord", name = "Steady Breath", desc = "A breath (tap the dark) calms a tug 15% more", ether = 600, growth = 6, max = 4, steadyAdd = 0.15 },
            { id = "thread", section = "auto", name = "Silver Thread", desc = "Comes back by itself, at the strain you set", ether = 250, max = 1 },
            { id = "trance", at = "thread", section = "auto", name = "Trance", desc = "Goes out again by itself", ether = 1000, max = 1 },
            { id = "light", at = "trance", section = "auto", name = "Light Body", desc = "Rest 30% shorter in the body", ether = 1500, growth = 8, max = 4, restCut = 0.7 },
            { id = "lens", section = "ether", name = "Ether Lens", desc = "+50% Ether, everywhere", ether = 200, growth = 5, max = 25, etherAdd = 0.5 },
            { id = "librarian", at = "lens", section = "ether", name = "Librarian", desc = "The Akashic records count 25% more", ether = 3000, growth = 8, max = 8, akashicAdd = 0.25 },
            { id = "farsight", at = "librarian", section = "ether", name = "Far Sight", desc = "Your reach lifts the dreamers 50% more", ether = 2e4, growth = 8, max = 6, reachAdd = 0.5 },
        },

        -- Constellations, lit a star at a time (each star `star` *
        -- starGrowth^i Ether), each once your reach is into its plane and the
        -- one before it is lit. Stars are where they stand in a 1 x 1 box;
        -- each is drawn joined to the one before it (and to `join`, if set).
        -- Lit, the reward is kept for good. The Sleeper, at the Edge, is
        -- the last: then the cord can be cut.
        starGrowth = 1.35,
        constellations = {
            { id = "aries", name = "Aries, the Ram", plane = 1, star = 30, reward = "All Ether x2", etherMult = 2,
                stars = { { 0.15, 0.55 }, { 0.3, 0.4 }, { 0.55, 0.42 }, { 0.75, 0.3 }, { 0.85, 0.12 } } },
            { id = "crook", name = "The Crook", plane = 1, star = 500, reward = "The cord x2", cordMult = 2,
                stars = { { 0.5, 0.95 }, { 0.5, 0.65 }, { 0.5, 0.35 }, { 0.58, 0.12 }, { 0.75, 0.1 }, { 0.8, 0.28 } } },
            { id = "lamb", name = "The Lamb", plane = 2, star = 2e4, reward = "Tugs half as often, a quarter softer", tugEvery = 2, tugSoft = 0.75,
                stars = { { 0.2, 0.5 }, { 0.35, 0.35 }, { 0.6, 0.35 }, { 0.78, 0.25 }, { 0.65, 0.6 }, { 0.3, 0.65 } }, join = { 6, 1 } },
            { id = "dog", name = "The Collie", plane = 2, star = 3e5, reward = "A snapped cord keeps 90%", snapKeep = 0.9,
                stars = { { 0.1, 0.4 }, { 0.3, 0.5 }, { 0.6, 0.5 }, { 0.8, 0.35 }, { 0.92, 0.2 }, { 0.6, 0.8 }, { 0.3, 0.8 } }, join = { 3, 6 } },
            { id = "fence", name = "The Fence", plane = 3, star = 2e7, reward = "Drift x1.5, rest halved", speedMult = 1.5, restMult = 0.5,
                stars = { { 0.1, 0.8 }, { 0.1, 0.3 }, { 0.5, 0.3 }, { 0.5, 0.8 }, { 0.9, 0.8 }, { 0.9, 0.3 }, { 0.5, 0.3 } } },
            { id = "fleece", name = "The Golden Fleece", plane = 3, star = 4e8, reward = "Close calls and dreamers x2", closeMult = 2, dreamerMult = 2,
                stars = { { 0.2, 0.3 }, { 0.45, 0.2 }, { 0.75, 0.25 }, { 0.85, 0.5 }, { 0.7, 0.75 }, { 0.4, 0.8 }, { 0.15, 0.6 }, { 0.5, 0.5 } }, join = { 7, 1 } },
            { id = "flock", name = "The Great Flock", plane = 4, star = 4e11, reward = "The Akashic records count double", akashicMult = 2,
                stars = { { 0.1, 0.6 }, { 0.25, 0.45 }, { 0.4, 0.6 }, { 0.55, 0.42 }, { 0.7, 0.58 }, { 0.85, 0.4 }, { 0.6, 0.2 }, { 0.3, 0.2 }, { 0.1, 0.6 } } },
            { id = "sleeper", name = "The Sleeper", plane = 5, star = 5e12, reward = "The cord can be cut", last = true,
                stars = { { 0.1, 0.7 }, { 0.3, 0.6 }, { 0.5, 0.62 }, { 0.7, 0.6 }, { 0.9, 0.7 }, { 0.78, 0.4 }, { 0.82, 0.25 }, { 0.68, 0.18 }, { 0.62, 0.35 } } },
        },

        -- The comet, the guide's gift: now and then it crosses the sky, and
        -- tapped, it offers one of three: Ether now (`seconds` of what's
        -- coming in), the cord slack (x2 for a while), or a wind (drift x3).
        comet = {
            firstDelay = 45, minDelay = 70, maxDelay = 130, crossTime = 9,
            ether = { seconds = 120, least = 50 },
            slack = { mult = 2, seconds = 30 },
            wind = { mult = 3, seconds = 30 },
        },

        -- The way out, once the Sleeper is lit: the cord cut, for Ether.
        cut = 2e14,
    },

    -- PHASE 4: past the cut cord. A placeholder: the void, or enlightenment.
    beyond = {},

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
