-- Question bank loader.
--
-- Each q_<category>.lua returns a list of positional entries:
--   { answer, unit, en_question, en_fact, fr_question, fr_fact, source }
-- `source` ("src: ...") is a note for whoever checks the numbers again: the
-- reference the answer was checked against. It is never shown.
-- A question that only makes sense in one language leaves the other pair nil
-- (French-flavoured trivia, say). Ids are "<category>:<index>", so new
-- questions must be appended at the end of a file, never inserted.
-- Files are read on first use only.

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local Questions = {}

Questions.CATEGORIES = {
    "history", "geography", "monuments", "people", "science",
    "nature", "space", "culture", "sport",
    "food", "body", "records", "inventions", "literature", "cities", "local",
}

-- Unit id -> { prompt shown under the question, suffix after a number }.
Questions.UNITS = {
    en = {
        year   = { "Year", "" },
        yearbc = { "Year (BC = negative number)", "" },
        n      = { "", "" },
        m      = { "In metres", "m" },
        cm     = { "In centimetres", "cm" },
        km     = { "In kilometres", "km" },
        km2    = { "In square kilometres", "km²" },
        kg     = { "In kilograms", "kg" },
        g      = { "In grams", "g" },
        t      = { "In tonnes", "t" },
        age    = { "Age, in years", "years old" },
        years  = { "In years", "years" },
        months = { "In months", "months" },
        days   = { "In days", "days" },
        hours  = { "In hours", "h" },
        min    = { "In minutes", "min" },
        s      = { "In seconds", "s" },
        degc   = { "In degrees Celsius", "°C" },
        degf   = { "In degrees Fahrenheit", "°F" },
        kmh    = { "In km/h", "km/h" },
        ms     = { "In metres per second", "m/s" },
        kms    = { "In kilometres per second", "km/s" },
        pct    = { "In percent", "%" },
        l      = { "In litres", "L" },
        bpm    = { "Beats per minute", "bpm" },
        mm     = { "In millimetres", "mm" },
        ml     = { "In millilitres", "mL" },
        mg     = { "In milligrams", "mg" },
        kcal   = { "In kilocalories", "kcal" },
        bar    = { "In bars", "bar" },
        floors = { "Floors", "floors" },
        mph    = { "In miles per hour", "mph" },
        m2     = { "In square metres", "m²" },
        hz     = { "In hertz", "Hz" },
        ha     = { "In hectares", "ha" },
        ct     = { "In carats", "ct" },
        m3     = { "In cubic metres", "m³" },
        letters = { "Letters", "letters" },
    },
    fr = {
        year   = { "Année", "" },
        yearbc = { "Année (av. J.-C. = nombre négatif)", "" },
        n      = { "", "" },
        m      = { "En mètres", "m" },
        cm     = { "En centimètres", "cm" },
        km     = { "En kilomètres", "km" },
        km2    = { "En kilomètres carrés", "km²" },
        kg     = { "En kilogrammes", "kg" },
        g      = { "En grammes", "g" },
        t      = { "En tonnes", "t" },
        age    = { "Âge, en années", "ans" },
        years  = { "En années", "ans" },
        months = { "En mois", "mois" },
        days   = { "En jours", "jours" },
        hours  = { "En heures", "h" },
        min    = { "En minutes", "min" },
        s      = { "En secondes", "s" },
        degc   = { "En degrés Celsius", "°C" },
        degf   = { "En degrés Fahrenheit", "°F" },
        kmh    = { "En km/h", "km/h" },
        ms     = { "En mètres par seconde", "m/s" },
        kms    = { "En kilomètres par seconde", "km/s" },
        pct    = { "En pourcentage", "%" },
        l      = { "En litres", "L" },
        bpm    = { "Battements par minute", "bpm" },
        mm     = { "En millimètres", "mm" },
        ml     = { "En millilitres", "mL" },
        mg     = { "En milligrammes", "mg" },
        kcal   = { "En kilocalories", "kcal" },
        bar    = { "En bars", "bar" },
        floors = { "Étages", "étages" },
        mph    = { "En miles par heure", "mph" },
        m2     = { "En mètres carrés", "m²" },
        hz     = { "En hertz", "Hz" },
        ha     = { "En hectares", "ha" },
        ct     = { "En carats", "ct" },
        m3     = { "En mètres cubes", "m³" },
        letters = { "Lettres", "lettres" },
    },
}

local raw      -- category -> list of raw entries
local by_lang  = {}

local function loadRaw()
    if raw then return raw end
    raw = {}
    for _i, cat in ipairs(Questions.CATEGORIES) do
        local chunk = loadfile(_dir .. "q_" .. cat .. ".lua")
        local ok, list = false, nil
        if chunk then ok, list = pcall(chunk) end
        raw[cat] = (ok and type(list) == "table") and list or {}
    end
    return raw
end

-- All questions available in `lang`: { [id] = q, ids = { id, ... } }, where
-- q = { id, cat, answer, unit, is_year, question, fact, prompt, suffix }.
function Questions.forLanguage(lang)
    if by_lang[lang] then return by_lang[lang] end
    local units = Questions.UNITS[lang] or Questions.UNITS.en
    local out = { ids = {}, by_cat = {} }
    for _i, cat in ipairs(Questions.CATEGORIES) do
        out.by_cat[cat] = {}
        for i, e in ipairs(loadRaw()[cat]) do
            local q, f
            if lang == "fr" then q, f = e[5], e[6] else q, f = e[3], e[4] end
            if q then
                local id = cat .. ":" .. i
                local u = units[e[2]] or units.n
                out[id] = {
                    id       = id,
                    cat      = cat,
                    answer   = e[1],
                    unit     = e[2],
                    is_year  = e[2] == "year" or e[2] == "yearbc",
                    question = q,
                    fact     = f or "",
                    prompt   = u[1],
                    suffix   = u[2],
                }
                out.ids[#out.ids + 1] = id
                table.insert(out.by_cat[cat], id)
            end
        end
    end
    by_lang[lang] = out
    return out
end

-- Ids of the questions in the selected categories (`cats` nil = all).
function Questions.pool(lang, cats)
    local bank = Questions.forLanguage(lang)
    if not cats then return bank.ids end
    local out = {}
    for _i, cat in ipairs(Questions.CATEGORIES) do
        if cats[cat] then
            for _i, id in ipairs(bank.by_cat[cat]) do out[#out + 1] = id end
        end
    end
    return out
end

return Questions
