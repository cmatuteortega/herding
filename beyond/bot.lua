-- A simple player for phase 4, for the balance sim and the dev autoplay: it
-- whispers at a tap rate, jumps to calm the Dogs, pairs the best two, buys the
-- cheapest upgrade it can, descends, and once the flock is awake saves up
-- for the vote.

local C = require "config"
local Beyond = require "beyond.game"

local B = C.beyond
local Bot = {}

-- A step of play (half a second is fine). `opts.tap` whispers a second, `opts.jump` is how often (seconds)
-- a jump comes round. Returns what it did, for the sim's log.
function Bot.act(b, dt, rand, opts)
    opts = opts or {}
    local did = {}
    local tap = opts.tap or 1.5
    b.botTap = (b.botTap or 0) + tap * dt
    while b.botTap >= 1 do
        b.botTap = b.botTap - 1
        if Beyond.whisper(b) then did.whisper = (did.whisper or 0) + 1 end
    end
    b.botJump = (b.botJump or 0) - dt
    if (b.suspicion > (opts.calmAt or 0.5)) and b.botJump <= 0 then
        Beyond.comply(b)
        b.botJump = opts.jump or 6
        did.jump = true
    end
    if Beyond.canRally(b) then Beyond.rally(b) did.rally = true end
    if b.ready then
        local a, c = Beyond.bestPair(b)
        if a and c and Beyond.breed(b, a.id, c.id, rand) then did.breed = true end
    end
    if Beyond.canDescend(b) and Beyond.descend(b, rand) then did.descend = true end
    if b.awake then
        if Beyond.vote(b) then did.vote = true end
    else
        local best, bp
        for _, u in ipairs(Beyond.UPS) do
            if Beyond.upState(b, u.id) == "open" then
                local p = Beyond.upPrice(b, u.id)
                if not bp or p < bp then best, bp = u.id, p end
            end
        end
        if best and Beyond.grow(b, best) then did.grow = best end
    end
    return did
end

return Bot
