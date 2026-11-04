-- Logic of a question (number entry, scoring in the three modes) and the
-- integrity of the bundled question bank, which is hand-written: a typo in
-- an entry would only show up when that question is drawn mid-game.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Estimation game", function()
    local Game
    setup(function() Game = require("game") end)

    describe("number entry", function()
        it("appends digits without leading zeros", function()
            local s = ""
            s = Game.entryAppend(s, 0); assert.are.equal("0", s)
            s = Game.entryAppend(s, 7); assert.are.equal("7", s)
            s = Game.entryAppend(s, 3); assert.are.equal("73", s)
            assert.are.equal(73, Game.entryValue(s))
        end)
        it("handles the sign for years BC", function()
            local s = Game.entryToggleSign("")
            assert.are.equal("-", s)
            assert.is_nil(Game.entryValue(s))
            s = Game.entryAppend(s, 4); s = Game.entryAppend(s, 4)
            assert.are.equal(-44, Game.entryValue(s))
            assert.are.equal("44", Game.entryToggleSign(s))
            assert.are.equal(0, Game.entryValue("-0"))
        end)
        it("caps the length and erases", function()
            local s = ""
            for _i = 1, 20 do s = Game.entryAppend(s, 9) end
            assert.are.equal(Game.MAX_DIGITS, #s)
            assert.are.equal(Game.MAX_DIGITS - 1, #Game.entryBackspace(s))
            assert.are.equal("", Game.entryBackspace(""))
        end)
        it("accepts the largest answers in the bank", function()
            assert.is_true(Game.MAX_DIGITS >= #tostring(13800000000))
        end)
    end)

    describe("formatting", function()
        it("groups thousands per language, not years", function()
            assert.are.equal("1,234,567", Game.formatNumber(1234567, "en"))
            assert.are.equal("1\u{00A0}234\u{00A0}567", Game.formatNumber(1234567, "fr"))
            assert.are.equal("1889", Game.formatNumber(1889, "en", true))
            assert.are.equal("−44", Game.formatNumber(-44, "fr", true))
            assert.are.equal("999", Game.formatNumber(999, "en"))
            assert.are.equal("1,000", Game.formatNumber(1000, "en"))
        end)
    end)

    describe("closest", function()
        it("scores the nearest guess, ties included, 2 for exact", function()
            local pts, best = Game.closestWinners({ 1815, 1830, 1827 }, 1821, "closest")
            assert.are.same({ [1] = 1, [3] = 1 }, pts)
            assert.are.equal(6, best)
            pts = Game.closestWinners({ 1821, 1800 }, 1821, "closest")
            assert.are.same({ [1] = 2 }, pts)
        end)
        it("ignores guesses over the answer in notover mode", function()
            local pts = Game.closestWinners({ 1822, 1700, 1800 }, 1821, "notover")
            assert.are.same({ [3] = 1 }, pts)
            pts = Game.closestWinners({ 1900, 2000 }, 1821, "notover")
            assert.are.same({}, pts)
        end)
    end)

    describe("betting", function()
        it("builds sorted distinct slots with odds growing outward", function()
            local slots = Game.buildSlots({ 50, 10, 30, 10, 70 }, 5)
            assert.are.equal(4, #slots)
            assert.are.same({ 10, 30, 50, 70 }, { slots[1].value, slots[2].value, slots[3].value, slots[4].value })
            assert.are.same({ 2, 4 }, slots[1].owners)
            assert.are.same({ 3, 2, 2, 3 }, { slots[1].odds, slots[2].odds, slots[3].odds, slots[4].odds })
            assert.is_true(slots[0].low)
            assert.are.equal(4, slots[0].odds)
            slots = Game.buildSlots({ 1, 2, 3, 4, 5, 6, 7 }, 7)
            assert.are.same({ 5, 4, 3, 2, 3, 4, 5 },
                { slots[1].odds, slots[2].odds, slots[3].odds, slots[4].odds,
                  slots[5].odds, slots[6].odds, slots[7].odds })
            assert.are.equal(6, slots[0].odds)
        end)
        it("picks the highest guess not over, or the low slot", function()
            local slots = Game.buildSlots({ 10, 30, 50 }, 3)
            assert.are.equal(2, Game.winningSlot(slots, 42))
            assert.are.equal(2, Game.winningSlot(slots, 30))
            assert.are.equal(0, Game.winningSlot(slots, 5))
            assert.are.equal(3, Game.winningSlot(slots, 1000))
        end)
        it("pays chips at the slot's odds plus the owner bonus", function()
            local guesses = { 10, 30, 50 }
            local slots = Game.buildSlots(guesses, 3)
            local bets = { [1] = { [2] = 2 }, [2] = { [1] = 1, [2] = 1 }, [3] = { [0] = 2 } }
            local pts, win = Game.bettingPoints(slots, bets, 42)
            assert.are.equal(2, win)
            assert.are.equal(2, slots[2].odds)
            assert.are.equal(4, pts[1])                       -- 2 chips x2
            assert.are.equal(Game.OWNER_BONUS + 2, pts[2])     -- owner + 1 chip x2
            assert.is_nil(pts[3])
            pts = Game.bettingPoints(slots, bets, 1)          -- everyone too high
            assert.are.equal(2 * slots[0].odds, pts[3])
            assert.is_nil(pts[1])
        end)
        it("counts chips", function()
            assert.are.equal(0, Game.chipsPlaced(nil))
            assert.are.equal(2, Game.chipsPlaced({ [0] = 1, [3] = 1 }))
        end)
    end)

    describe("game helpers", function()
        it("ranks and finds leaders", function()
            local players = { { score = 2 }, { score = 5 }, { score = 5 }, { score = 0 } }
            assert.are.same({ 2, 3, 1, 4 }, Game.ranking(players))
            local l, best = Game.leaders(players)
            assert.are.same({ 2, 3 }, l)
            assert.are.equal(5, best)
        end)
        it("picks fresh questions first, no duplicates", function()
            local pool = { "a", "b", "c", "d", "e" }
            local got = Game.pickQuestions(pool, 3, { a = true, b = true, c = true })
            assert.are.equal(3, #got)
            local seen = {}
            for _i, id in ipairs(got) do assert.is_nil(seen[id]); seen[id] = true end
            assert.is_true(seen.d and seen.e)
            assert.are.equal(5, #Game.pickQuestions(pool, 10, nil))
        end)
    end)
end)

describe("Estimation question bank", function()
    local Questions
    setup(function() Questions = require("questions") end)

    for _i, lang in ipairs({ "en", "fr" }) do
        it("has at least 800 well-formed questions in " .. lang, function()
            local bank = Questions.forLanguage(lang)
            assert.is_true(#bank.ids >= 800, lang .. ": " .. #bank.ids)
            local seen = {}
            for _j, id in ipairs(bank.ids) do
                local q = bank[id]
                assert.is_number(q.answer, id)
                assert.are.equal(q.answer, math.floor(q.answer), id .. " must be an integer")
                assert.is_true(#tostring(math.abs(q.answer)) <= 12, id)
                assert.is_not_nil(Questions.UNITS[lang][q.unit], id .. " unit " .. tostring(q.unit))
                assert.is_true(#q.question > 10, id)
                assert.is_true(#q.fact > 3, id .. " needs a fact")
                assert.is_nil(seen[q.question], "duplicate question: " .. q.question)
                seen[q.question] = true
                if q.unit == "yearbc" then assert.is_true(q.answer < 0, id) end
                if q.unit == "year" then assert.is_true(q.answer > 0 and q.answer < 2100, id) end
            end
        end)
        it("has every category represented in " .. lang, function()
            local bank = Questions.forLanguage(lang)
            for _j, cat in ipairs(Questions.CATEGORIES) do
                assert.is_true(#bank.by_cat[cat] >= 20, cat)
            end
        end)
    end

    it("carries a source note on every entry", function()
        for _i, cat in ipairs(Questions.CATEGORIES) do
            local list = dofile(DIR .. "q_" .. cat .. ".lua")
            for j, e in ipairs(list) do
                assert.is_truthy(type(e[7]) == "string" and e[7]:match("^src: %S"), cat .. ":" .. j)
                assert.is_true(e[3] ~= nil or e[5] ~= nil, cat .. ":" .. j)
            end
        end
    end)

    it("keeps the local category to one language per entry", function()
        for j, e in ipairs(dofile(DIR .. "q_local.lua")) do
            assert.is_true((e[3] == nil) ~= (e[5] == nil), "local:" .. j)
        end
    end)

    it("filters the pool by category", function()
        local pool = Questions.pool("en", { space = true })
        assert.is_true(#pool > 0)
        for _i, id in ipairs(pool) do assert.is_truthy(id:match("^space:")) end
    end)

    it("keeps both languages of a shared question on the same answer", function()
        local en, fr = Questions.forLanguage("en"), Questions.forLanguage("fr")
        for _i, id in ipairs(en.ids) do
            if fr[id] then assert.are.equal(en[id].answer, fr[id].answer, id) end
        end
    end)
end)

-- The questions load with the first game of a language, only that language's,
-- and release() (the screen closing) drops them.
describe("Estimation question loading", function()
    it("loads nothing on require, one language on demand, none after release", function()
        local Q = dofile(DIR .. "questions.lua")
        assert.are.same({}, Q.loadedLanguages())
        local ids = Q.pool("fr", nil)
        assert.are.same({ "fr" }, Q.loadedLanguages())
        Q.release()
        assert.are.same({}, Q.loadedLanguages())
        -- Read again, the same ids in the same order (no-repeat history).
        assert.are.same(ids, Q.pool("fr", nil))
        Q.release()
    end)
end)
