-- Estimation -- game logic (pure Lua, no UI, so it can be unit-tested).
--
-- One game = N questions whose answer is a number. Every player enters a
-- secret guess; then, depending on the scoring mode:
--   closest  -- the guess(es) nearest the answer score 1 point (2 if exact);
--   notover  -- the same, but only among guesses that do not go over;
--   betting  -- the guesses become betting slots (plus "lower than every
--               guess"); each player places 1 or 2 chips; the winning slot
--               is the highest guess that does not go over, and pays its
--               odds per chip. Its owners also score 3 points.

local Game = {}

Game.MODES        = { "closest", "notover", "betting" }
Game.CHIPS        = 2       -- chips each player may bet per question
Game.OWNER_BONUS  = 3       -- points for owning the winning slot (betting)
Game.MAX_DIGITS   = 12
Game.MIN_PLAYERS  = 2
Game.MAX_PLAYERS  = 8
Game.QUESTION_COUNTS = { 5, 10, 15 }

-- ---------------------------------------------------------------------------
-- Number entry (the guess being typed, kept as a string: "", "-", "-12")
-- ---------------------------------------------------------------------------

function Game.entryAppend(s, digit)
    local digits = s:gsub("^%-", "")
    if #digits >= Game.MAX_DIGITS then return s end
    if digits == "0" then                -- no leading zeros: "0" then "5" is "5"
        return (s:sub(1, 1) == "-" and "-" or "") .. tostring(digit)
    end
    return s .. tostring(digit)
end

function Game.entryBackspace(s)
    return s:sub(1, -2)
end

function Game.entryToggleSign(s)
    if s:sub(1, 1) == "-" then return s:sub(2) end
    return "-" .. s
end

-- The number typed so far, or nil when nothing usable has been typed.
function Game.entryValue(s)
    if not s:match("^%-?%d+$") then return nil end
    local v = tonumber(s)
    if v == 0 then v = 0 end             -- "-0" is 0
    return v
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------

-- 1234567 -> "1,234,567" (en) or "1 234 567" (fr, non-breaking spaces).
-- Years are never grouped: "1889", not "1,889".
function Game.formatNumber(n, lang, is_year)
    local neg = n < 0
    local s = tostring(math.floor(math.abs(n) + 0.5))
    if not is_year and #s >= 4 then
        local sep = lang == "fr" and "\u{00A0}" or ","
        local head = (#s - 1) % 3 + 1
        local parts = { s:sub(1, head) }
        for i = head + 1, #s, 3 do parts[#parts + 1] = s:sub(i, i + 2) end
        s = table.concat(parts, sep)
    end
    return (neg and "−" or "") .. s
end

-- ---------------------------------------------------------------------------
-- Closest / closest without going over
-- ---------------------------------------------------------------------------

-- guesses: { [player] = number }. Returns { [player] = points } for the
-- players who score, plus the best distance (nil when nobody qualifies).
function Game.closestWinners(guesses, answer, mode)
    local best
    for _, g in pairs(guesses) do
        if mode ~= "notover" or g <= answer then
            local d = math.abs(g - answer)
            if not best or d < best then best = d end
        end
    end
    local pts = {}
    if not best then return pts, nil end
    for p, g in pairs(guesses) do
        if (mode ~= "notover" or g <= answer) and math.abs(g - answer) == best then
            pts[p] = best == 0 and 2 or 1
        end
    end
    return pts, best
end

-- ---------------------------------------------------------------------------
-- Betting slots
-- ---------------------------------------------------------------------------

-- Distinct guesses sorted ascending, each with its owners and odds, after a
-- slot 0 "lower than every guess". Odds grow from 2 (middle) outward by one
-- per step; slot 0 pays one more than the best outer slot.
--   slots[0] = { low = true, odds = k }
--   slots[i] = { value = v, owners = { p, ... }, odds = k }
function Game.buildSlots(guesses, nplayers)
    local values, owners = {}, {}
    for p = 1, nplayers do
        local g = guesses[p]
        if g ~= nil then
            if not owners[g] then
                owners[g] = {}
                values[#values + 1] = g
            end
            table.insert(owners[g], p)
        end
    end
    table.sort(values)
    local slots = {}
    local n = #values
    local centre = (n + 1) / 2
    local top = 2
    for i, v in ipairs(values) do
        local odds = 2 + math.floor(math.abs(i - centre))
        if odds > top then top = odds end
        slots[i] = { value = v, owners = owners[v], odds = odds }
    end
    slots[0] = { low = true, odds = top + 1 }
    return slots
end

-- Index of the winning slot: the highest guess not above the answer, or 0
-- when every guess went over.
function Game.winningSlot(slots, answer)
    local win = 0
    for i = 1, #slots do
        if slots[i].value <= answer then win = i end
    end
    return win
end

-- bets: { [player] = { [slot] = chips } }. Returns { [player] = points }.
function Game.bettingPoints(slots, bets, answer)
    local win = Game.winningSlot(slots, answer)
    local pts = {}
    if win > 0 then
        for _, p in ipairs(slots[win].owners) do
            pts[p] = (pts[p] or 0) + Game.OWNER_BONUS
        end
    end
    for p, b in pairs(bets) do
        local chips = b[win]
        if chips and chips > 0 then
            pts[p] = (pts[p] or 0) + chips * slots[win].odds
        end
    end
    return pts, win
end

function Game.chipsPlaced(bet)
    local n = 0
    for _, c in pairs(bet or {}) do n = n + c end
    return n
end

-- ---------------------------------------------------------------------------
-- A whole game
-- ---------------------------------------------------------------------------

-- Points for this question in the given mode: { [player] = points }.
function Game.scoreQuestion(mode, guesses, bets, answer, nplayers)
    if mode == "betting" then
        local slots = Game.buildSlots(guesses, nplayers)
        local pts = Game.bettingPoints(slots, bets or {}, answer)
        return pts
    end
    return (Game.closestWinners(guesses, answer, mode))
end

-- Players sorted by score (best first); ties keep seat order.
function Game.ranking(players)
    local order = {}
    for i = 1, #players do order[i] = i end
    table.sort(order, function(a, b)
        if players[a].score ~= players[b].score then
            return players[a].score > players[b].score
        end
        return a < b
    end)
    return order
end

-- Indices of the players tied for the lead.
function Game.leaders(players)
    local best
    for _, p in ipairs(players) do
        if not best or p.score > best then best = p.score end
    end
    local out = {}
    for i, p in ipairs(players) do
        if p.score == best then out[#out + 1] = i end
    end
    return out, best
end

-- Pick n question ids from `pool` (list of ids), preferring ids not in
-- `recent` (set), shuffled with `rng` (math.random-like).
function Game.pickQuestions(pool, n, recent, rng)
    rng = rng or math.random
    local fresh, stale = {}, {}
    for _, id in ipairs(pool) do
        if recent and recent[id] then stale[#stale + 1] = id else fresh[#fresh + 1] = id end
    end
    local function shuffle(t)
        for i = #t, 2, -1 do
            local j = rng(i)
            t[i], t[j] = t[j], t[i]
        end
    end
    shuffle(fresh)
    shuffle(stale)
    local out = {}
    for _, id in ipairs(fresh) do
        if #out >= n then break end
        out[#out + 1] = id
    end
    for _, id in ipairs(stale) do
        if #out >= n then break end
        out[#out + 1] = id
    end
    return out
end

return Game
