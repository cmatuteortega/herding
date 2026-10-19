-- The tracer, herding's: the 3D method of Survive School (3dmethod.md there)
-- as underroot carries it (src/tracer.lua), with Survive School's camera:
-- looking up the field from the front and tilted down, orthographic.
--
-- A body is a list of ellipsoids. Each pixel is traced once at its centre and
-- its colour *chosen* off a ramp of palette keys (glint, lit, middle, shadow),
-- never blended. Then the two passes that make it read as drawn rather than
-- rendered: creases (a step down the ramp where neighbouring normals of one
-- material disagree) and ink (round the silhouette, and along any step in depth
-- onto another part). With no perspective a picture of a thing is the same
-- wherever it stands, so a pose is painted once and kept (models.lua).
--
-- Room space: x right, y up, z towards the viewer (down the screen). The ground
-- is the field: a field point (x, z) lands on screen at (x, z * SE), lifted by
-- y * CE.

local G = require "gfx"

local sqrt, cos, sin, max, min, floor, ceil = math.sqrt, math.cos, math.sin, math.max, math.min, math.floor, math.ceil

local T = {}

-- herding looked down at 52 degrees, to read the gaps in a flock from above.
-- Counting sheep is a side view: a sheep is read by its profile mid-hop.
local ELEV = math.rad(22)
local CE, SE = cos(ELEV), sin(ELEV)
T.CE, T.SE = CE, SE

-- The camera's axes in the room: screen right, screen up, towards you.
local UY, UZ = CE, -SE -- screen right is room x
local NX, NY, NZ = 0, SE, CE
local DX, DY, DZ = -NX, -NY, -NZ

-- The lamp lives in the room: up, to the left and a little towards you.
local LX, LY, LZ = -0.55, 0.85, 0.45
do
    local n = sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local HX, HY, HZ = LX + NX, LY + NY, LZ + NZ
do
    local n = sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end

local CREASE = 0.55

-- Room point to screen pixel (i right, j down) and depth (bigger is nearer).
function T.project(x, y, z)
    return x, z * SE - y * CE, y * NY + z * NZ
end

-- Where the ray through screen point (i, j) starts, `back` towards the viewer.
local function origin(i, j, back)
    return i, -j * UY + back * NY, -j * UZ + back * NZ
end

--- ramps -----------------------------------------------------------------------

function T.ramp(g, l, m, s) return { g, l, m, s } end

local function shade(r, nx, ny, nz)
    local d = nx * LX + ny * LY + nz * LZ
    local h = nx * HX + ny * HY + nz * HZ
    if h > 0 and h ^ 40 > 0.6 then return r[1], 1 end
    if d > 0.72 then return r[2], 2 end
    if d > 0.15 then return r[3], 3 end
    -- Bounce light: an underside lit a little from the ground stays mid-tone,
    -- or it reads as a hole.
    if ny < 0 and d > 0.02 then return r[3], 3 end
    return r[4], 4
end

--- affine maps: twelve numbers, row-major, 3x3 then the shift per row ---------

local A = {}
T.A = A

function A.move(x, y, z) return { 1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z } end
function A.scale(x, y, z) return { x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0 } end
function A.rotY(a)
    local c, s = cos(a), sin(a)
    return { c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0 }
end
function A.rotZ(a)
    local c, s = cos(a), sin(a)
    return { c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0 }
end

function A.mul(a, b, ...)
    local r = {}
    for row = 0, 2 do
        local a1, a2, a3, a4 = a[row * 4 + 1], a[row * 4 + 2], a[row * 4 + 3], a[row * 4 + 4]
        for col = 1, 4 do
            r[row * 4 + col] = a1 * b[col] + a2 * b[4 + col] + a3 * b[8 + col]
        end
        r[row * 4 + 4] = r[row * 4 + 4] + a4
    end
    if ... then return A.mul(r, ...) end
    return r
end

function A.inv(m)
    local a, b, c, d, e, f, g, h, i = m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]
    local A1, B1, C1 = e * i - f * h, -(d * i - f * g), d * h - e * g
    local det = a * A1 + b * B1 + c * C1
    local r = {
        A1 / det, -(b * i - c * h) / det, (b * f - c * e) / det, 0,
        B1 / det, (a * i - c * g) / det, -(a * f - c * d) / det, 0,
        C1 / det, -(a * h - b * g) / det, (a * e - b * d) / det, 0,
    }
    for row = 0, 2 do
        r[row * 4 + 4] = -(r[row * 4 + 1] * m[4] + r[row * 4 + 2] * m[8] + r[row * 4 + 3] * m[12])
    end
    return r
end

-- A part: a unit ball scaled to radii (rx, ry, rz) and set at (cx, cy, cz).
function T.ell(cx, cy, cz, rx, ry, rz, ramp, id)
    return { at = A.mul(A.move(cx, cy, cz), A.scale(rx, ry, rz)), ramp = ramp, id = id or 1 }
end

-- Every part's map put through m (a heading, a squash), outermost first.
function T.place(parts, m)
    for _, p in ipairs(parts) do p.at = A.mul(m, p.at) end
    return parts
end

--- painting --------------------------------------------------------------------

local BACK = 60

-- Parts to a picture: an Image and the pixel of it the pivot (the ground under
-- the body, room 0,0,0) falls on.
function T.paint(parts, edge)
    edge = edge or 1.5
    local i0, j0, i1, j1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(parts) do
        local m = p.at
        p.inv = A.inv(m)
        local r = 0
        for col = 1, 3 do r = max(r, sqrt(m[col] ^ 2 + m[4 + col] ^ 2 + m[8 + col] ^ 2)) end
        local ci, cj = T.project(m[4], m[8], m[12])
        p.ci, p.cj, p.cr = ci, cj, r + 1
        i0, i1 = min(i0, ci - p.cr), max(i1, ci + p.cr)
        j0, j1 = min(j0, cj - p.cr), max(j1, cj + p.cr)
    end
    i0, j0 = floor(i0) - 1, floor(j0) - 1
    i1, j1 = ceil(i1) + 1, ceil(j1) + 1
    local w, h = i1 - i0 + 1, j1 - j0 + 1
    local n = w * h
    local key, lev, shd, part, mat, dep, dif, nxs, nys, nzs, best = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
    for q = 0, n - 1 do best[q] = 1e9 end

    for _, p in ipairs(parts) do
        local v = p.inv
        local bx = v[1] * DX + v[2] * DY + v[3] * DZ
        local by = v[5] * DX + v[6] * DY + v[7] * DZ
        local bz = v[9] * DX + v[10] * DY + v[11] * DZ
        local qa = bx * bx + by * by + bz * bz
        local rr = p.cr * p.cr
        for pj = max(0, floor(p.cj - p.cr) - j0), min(h - 1, ceil(p.cj + p.cr) - j0) do
            for pi = max(0, floor(p.ci - p.cr) - i0), min(w - 1, ceil(p.ci + p.cr) - i0) do
                local si, sj = i0 + pi + 0.5, j0 + pj + 0.5
                if (si - p.ci) ^ 2 + (sj - p.cj) ^ 2 <= rr then
                    local ox, oy, oz = origin(si, sj, BACK)
                    local ax = v[1] * ox + v[2] * oy + v[3] * oz + v[4]
                    local ay = v[5] * ox + v[6] * oy + v[7] * oz + v[8]
                    local az = v[9] * ox + v[10] * oy + v[11] * oz + v[12]
                    local qb = ax * bx + ay * by + az * bz
                    local disc = qb * qb - qa * (ax * ax + ay * ay + az * az - 1)
                    if disc >= 0 then
                        local t = (-qb - sqrt(disc)) / qa
                        local q = pj * w + pi
                        if t < best[q] then
                            best[q] = t
                            local ux, uy, uz = ax + t * bx, ay + t * by, az + t * bz
                            -- The normal: the transpose of the inverse's linear part.
                            local nx = v[1] * ux + v[5] * uy + v[9] * uz
                            local ny = v[2] * ux + v[6] * uy + v[10] * uz
                            local nz = v[3] * ux + v[7] * uy + v[11] * uz
                            local l = sqrt(nx * nx + ny * ny + nz * nz)
                            nx, ny, nz = nx / l, ny / l, nz / l
                            local r = p.ramp
                            local k, lv = shade(r, nx, ny, nz)
                            local printed = p.print and p.print(ux, uy, uz, lv)
                            if printed then k, lv = printed, 0 end
                            key[q], lev[q], shd[q] = k, lv, r[4]
                            part[q], mat[q] = p.id, p.mat or p.id
                            dep[q] = BACK - t
                            dif[q] = nx * LX + ny * LY + nz * LZ
                            nxs[q], nys[q], nzs[q] = nx, ny, nz
                        end
                    end
                end
            end
        end
    end

    -- Creases, then ink, both decided off the untouched picture.
    local out = {}
    for q = 0, n - 1 do out[q] = key[q] end
    local function crease(p, q)
        if not key[q] or mat[p] ~= mat[q] then return end
        if nxs[p] * nxs[q] + nys[p] * nys[q] + nzs[p] * nzs[q] >= CREASE then return end
        local r = dif[p] < dif[q] and p or q
        if lev[r] == 2 or lev[r] == 3 then out[r] = shd[r] end
    end
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local p = j * w + i
            if key[p] then
                if i < w - 1 then crease(p, p + 1) end
                if j < h - 1 then crease(p, p + w) end
            end
        end
    end
    local function inked(p, q)
        if not key[q] then return true end
        return part[q] ~= part[p] and dep[p] - dep[q] > edge
    end
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local p = j * w + i
            if key[p] and (i == 0 or j == 0 or i == w - 1 or j == h - 1
                or inked(p, p - 1) or inked(p, p + 1) or inked(p, p - w) or inked(p, p + w)) then
                out[p] = "o"
            end
        end
    end

    local data = love.image.newImageData(w, h)
    for j = 0, h - 1 do
        for i = 0, w - 1 do
            local k = out[j * w + i]
            if k then
                local c = G.C[k]
                data:setPixel(i, j, c[1], c[2], c[3], 1)
            end
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return { img = img, oi = -i0, oj = -j0, w = w, h = h }
end

return T
