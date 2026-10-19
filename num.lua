-- Every amount of sheep goes through Num, so the plain Lua numbers here can be
-- swapped for a big-number library later by rewriting this file only. Counts of
-- things owned stay plain integers.

local floor, log10 = math.floor, math.log10

local Num = {}

function Num.from(x) return tonumber(x) or 0 end
function Num.zero() return 0 end
function Num.add(a, b) return a + b end
function Num.sub(a, b) return a - b end
function Num.mul(a, b) return a * b end
function Num.div(a, b) return a / b end
function Num.gte(a, b) return a >= b end
function Num.lt(a, b) return a < b end
function Num.max(a, b) return a > b and a or b end
function Num.sqrt(a) return math.sqrt(a) end
function Num.toNumber(a) return a end

-- What n more of a thing cost with k owned: base * g^k * (g^n - 1) / (g - 1).
function Num.sumGeometric(base, growth, owned, n)
    if n <= 0 then return 0 end
    return base * growth ^ owned * (growth ^ n - 1) / (growth - 1)
end

-- How many more `budget` buys with k owned (sumGeometric turned round).
function Num.maxAffordable(base, growth, owned, budget)
    local first = base * growth ^ owned
    if budget < first then return 0 end
    local n = floor(math.log(budget * (growth - 1) / first + 1) / math.log(growth))
    -- Floating point can land one either side of the edge.
    while n > 0 and Num.sumGeometric(base, growth, owned, n) > budget do n = n - 1 end
    while Num.sumGeometric(base, growth, owned, n + 1) <= budget do n = n + 1 end
    return n
end

-- 999, 1.2K, 34.5M, 678B, then 5.6E12. `decimals` keeps one place on a small
-- fraction (a rate like 1.5/S).
local SUFFIX = { "", "K", "M", "B" }
local function trim(v) return (("%.1f"):format(floor(v * 10) / 10):gsub("%.0$", "")) end
function Num.format(a, decimals)
    local x = a
    if x ~= x or x == math.huge then return "LOTS" end
    if x < 0 then return "-" .. Num.format(-x, decimals) end
    if x < 1000 then
        if decimals and x < 100 and x ~= floor(x) then return trim(x) end
        return tostring(floor(x))
    end
    local tier = floor(log10(x) / 3)
    if tier < #SUFFIX then
        local v = x / 1000 ^ tier
        local s = v < 100 and trim(v) or tostring(floor(v))
        if s == "1000" and tier + 1 < #SUFFIX then tier, s = tier + 1, "1" end
        return s .. SUFFIX[tier + 1]
    end
    local e = floor(log10(x))
    return ("%.1fE%d"):format(floor(x / 10 ^ e * 10) / 10, e)
end

-- For saves: a Num to something JSON holds, and back.
function Num.serialize(a) return a end
function Num.deserialize(x) return tonumber(x) or 0 end

return Num
