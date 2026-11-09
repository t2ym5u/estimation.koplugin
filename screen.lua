local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonTable     = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local RenderText      = require("ui/rendertext")
local RightContainer  = require("ui/widget/container/rightcontainer")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")

local Game      = lrequire("game")
local Players   = lrequire("players")
local Questions = lrequire("questions")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- Text helpers
--
-- Font:getFace() scales its size by the screen DPI, so a size worked out from
-- pixel dimensions is divided back first.
-- ---------------------------------------------------------------------------

local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local function pxFace(px, bold)
    return Font:getFace(bold and "smallinfofontbold" or "cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

-- One line at up to `px` pixels, shrunk until it fits `max_w`.
local function fitLine(text, px, max_w, bold)
    local face = pxFace(px, bold)
    while px > 12 do
        local m = RenderText:sizeUtf8Text(0, max_w * 10, face, text, true, bold)
        if m.x <= max_w then break end
        px   = math.floor(px * 0.9)
        face = pxFace(px, bold)
    end
    return TextWidget:new{ text = text, face = face, max_width = max_w, bold = bold }
end

-- A centred paragraph at up to `px` pixels, shrunk until it fits max_h.
local function fitBox(text, px, width, max_h, align)
    local box
    while true do
        box = TextBoxWidget:new{ text = text, face = pxFace(px), width = width,
                                 alignment = align or "center" }
        if not max_h or box:getSize().h <= max_h or px <= 14 then break end
        box:free()
        px = math.floor(px * 0.9)
    end
    return box
end

local function vspan(h) return VerticalSpan:new{ width = math.floor(h) } end

local function rule(w)
    return LineWidget:new{
        background = Blitbuffer.COLOR_DARK_GRAY,
        dimen      = Geom:new{ w = math.floor(w), h = Size.line.medium },
    }
end

-- Tapping anywhere on the hand-over card is the same as Ready.
local TapArea = InputContainer:extend{ callback = nil }

function TapArea:init()
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function TapArea:onTap()
    if self.callback then self.callback() end
    return true
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = [[
Estimation — Rules

Every question has a number for an answer: a year, a height, a distance, a count… Nobody is expected to know it — just to be the closest.

Each turn
• The reader goes round the table. When your name shows, take it, tap Ready, and type your guess on the number pad (± makes it negative, for years BC). Validate, then pass the reader on: your guess stays secret.
• Once everybody has guessed, the true answer is revealed with all the guesses, sorted, and a little fact.

Scoring (title-bar menu)
• Closest: the closest guess scores 1 point — 2 points for the exact answer. Ties all score.
• Closest without going over: the same, but guesses above the answer are out.
• Betting: the sorted guesses become betting slots, plus "Lower than every guess". Each player secretly places 1 or 2 chips on the slots they believe will win. The winning slot is the highest guess that does not go over the answer (or "Lower than every guess" if all went over). Each chip on it pays the slot's odds (×2 in the middle, more towards the edges); whoever wrote the winning guess also scores 3 points.

After the last question (5, 10 or 15 per game) the highest score wins. Categories can be filtered from the menu. Questions come in French or English (Language), whatever the interface language.
]]

local GAME_RULES_FR = [[
Estimation — Règles

Chaque question a pour réponse un nombre : une année, une hauteur, une distance, un nombre… Personne n'est censé la connaître — il suffit d'être le plus proche.

À chaque question
• La liseuse fait le tour de la table. Quand votre nom s'affiche, prenez-la, touchez Prêt et tapez votre estimation au pavé numérique (± la rend négative, pour les années av. J.-C.). Validez puis passez la liseuse : votre réponse reste secrète.
• Quand tout le monde a répondu, la vraie réponse s'affiche avec toutes les estimations, triées, et une petite anecdote.

Décompte (menu de la barre de titre)
• Le plus proche : l'estimation la plus proche marque 1 point — 2 points pour la réponse exacte. Les ex æquo marquent tous.
• Le plus proche sans dépasser : pareil, mais les estimations au-dessus de la réponse sont éliminées.
• Paris : les estimations triées deviennent des cases de pari, plus « Plus bas que toutes ». Chacun place en secret 1 ou 2 jetons sur les cases qu'il croit gagnantes. La case gagnante est la plus haute estimation qui ne dépasse pas la réponse (ou « Plus bas que toutes » si toutes dépassent). Chaque jeton dessus rapporte la cote de la case (×2 au milieu, davantage vers les bords) ; l'auteur de l'estimation gagnante marque en plus 3 points.

Après la dernière question (5, 10 ou 15 par partie), le plus haut score l'emporte. Les catégories se filtrent dans le menu. Les questions existent en français et en anglais (Langue), quelle que soit la langue de l'interface.
]]

local MODE_LABELS = {
    closest = _("Closest"),
    notover = _("Closest without going over"),
    betting = _("Betting"),
}

local CAT_LABELS = {
    history   = _("Historical events"),
    geography = _("Geography"),
    monuments = _("Monuments"),
    people    = _("Famous people"),
    science   = _("Science"),
    nature    = _("Nature and animals"),
    space     = _("Space"),
    culture   = _("Arts and culture"),
    sport     = _("Sport and games"),
    food      = _("Food and drink"),
    body      = _("Human body"),
    records   = _("Records"),
    inventions = _("Inventions"),
    literature = _("Books and writers"),
    cities    = _("Cities of the world"),
}

-- "local" questions are close to home for the content language: Paris and
-- France in French, London and Britain in English.
local function catLabel(cat, lang)
    if cat == "local" then
        return lang == "fr" and _("Paris and France") or _("London and Britain")
    end
    return CAT_LABELS[cat] or cat
end

local RECENT_MAX = 250   -- question ids remembered to avoid repeats

-- ---------------------------------------------------------------------------
-- EstimationScreen
-- ---------------------------------------------------------------------------

local EstimationScreen = ScreenBase:extend{}

function EstimationScreen:init()
    local p = self.plugin
    self.lang     = p:getLang({ "fr", "en" })
    self.nplayers = p:getSetting("players", 3)
    self.nq       = p:getSetting("questions", 10)
    self.mode     = p:getSetting("scoring", "closest")
    self.cats     = self:_loadCats()
    self.entry    = ""
    if not self:_restore(p:loadState()) then
        self:_newGame()
    end
    ScreenBase.init(self)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

-- nil = every category; else a set.
function EstimationScreen:_loadCats()
    local s = self.plugin:getSetting("categories", "")
    if not s or s == "" then return nil end
    local set, any = {}, false
    for c in s:gmatch("[^,]+") do set[c] = true; any = true end
    return any and set or nil
end

function EstimationScreen:_saveCats()
    if not self.cats then
        self.plugin:saveSetting("categories", "")
        return
    end
    local parts = {}
    for _i, c in ipairs(Questions.CATEGORIES) do
        if self.cats[c] then parts[#parts + 1] = c end
    end
    self.plugin:saveSetting("categories", table.concat(parts, ","))
end

-- ---------------------------------------------------------------------------
-- Game state
-- ---------------------------------------------------------------------------

function EstimationScreen:_bank()
    return Questions.forLanguage(self.st.lang)
end

function EstimationScreen:_question()
    return self:_bank()[self.st.qids[self.st.qi]]
end

-- Seat of the k-th player to act this question: the first one moves round.
function EstimationScreen:_seat(k)
    local n = #self.st.players
    return ((self.st.qi - 1 + k - 1) % n) + 1
end

function EstimationScreen:_current()
    return self.st.players[self:_seat(self.st.turn)]
end

function EstimationScreen:_newGame()
    local names = Players.load(self.plugin, self.nplayers)
    local players = {}
    for i, s in ipairs(names) do players[i] = { name = s, score = 0 } end
    local recent = {}
    for _i, id in ipairs(self.plugin:getSetting("recent_" .. self.lang, {}) or {}) do
        recent[id] = true
    end
    local pool = Questions.pool(self.lang, self.cats)
    if #pool == 0 then pool = Questions.pool(self.lang, nil) end
    self.st = {
        lang    = self.lang,
        mode    = self.mode,
        players = players,
        qids    = Game.pickQuestions(pool, self.nq, recent),
        qi      = 1,
    }
    self:_startQuestion()
end

function EstimationScreen:_startQuestion()
    local st = self.st
    st.phase   = "handover"
    st.turn    = 1
    st.guesses = {}
    st.bets    = {}
    st.pts     = nil
    self.entry = ""
    self:_save()
end

-- Remember the questions already asked, so the next games pick fresh ones.
function EstimationScreen:_markAsked(id)
    local key = "recent_" .. self.st.lang
    local list = self.plugin:getSetting(key, {}) or {}
    for i = #list, 1, -1 do
        if list[i] == id then table.remove(list, i) end
    end
    list[#list + 1] = id
    while #list > RECENT_MAX do table.remove(list, 1) end
    self.plugin:saveSetting(key, list)
end

function EstimationScreen:serializeState()
    return self.st
end

function EstimationScreen:_save()
    self.plugin:saveState(self.st)
end

-- A saved game comes back on its hand-over screen: whoever was typing a
-- secret guess or bet when the reader went to sleep starts it again.
function EstimationScreen:_restore(st)
    if type(st) ~= "table" or type(st.players) ~= "table" or type(st.qids) ~= "table"
       or #st.players < Game.MIN_PLAYERS or not st.qi or not st.qids[st.qi] then
        return false
    end
    local bank = Questions.forLanguage(st.lang or "en")
    for _i, id in ipairs(st.qids) do
        if not bank[id] then return false end
    end
    st.guesses = st.guesses or {}
    st.bets    = st.bets or {}
    st.turn    = st.turn or 1
    if st.phase == "guess" then st.phase = "handover" end
    if st.phase == "bet" then
        st.phase = "bethand"
        st.bets[self:_seatOf(st)] = nil
    end
    if st.phase ~= "handover" and st.phase ~= "bethand" and st.phase ~= "reveal"
       and st.phase ~= "final" then
        st.phase = "handover"
    end
    self.st = st
    return true
end

function EstimationScreen:_seatOf(st)
    local n = #st.players
    return ((st.qi - 1 + st.turn - 1) % n) + 1
end

function EstimationScreen:isRoundOver()
    return self.st.phase == "final"
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function EstimationScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function EstimationScreen:onNewGame()
    self:_newGame()
    self:_redraw()
end

function EstimationScreen:onReady()
    local st = self.st
    if st.phase == "handover" then
        st.phase = "guess"
        self.entry = ""
    elseif st.phase == "bethand" then
        st.phase = "bet"
        st.bets[self:_seat(st.turn)] = {}
    else
        return
    end
    self:_redraw()
end

function EstimationScreen:onDigit(d)
    if self.st.phase ~= "guess" then return end
    self.entry = Game.entryAppend(self.entry, d)
    self:_redraw()
end

function EstimationScreen:onErase()
    if self.st.phase ~= "guess" then return end
    self.entry = Game.entryBackspace(self.entry)
    self:_redraw()
end

function EstimationScreen:onSign()
    if self.st.phase ~= "guess" then return end
    self.entry = Game.entryToggleSign(self.entry)
    self:_redraw()
end

function EstimationScreen:onValidateGuess()
    local st = self.st
    if st.phase ~= "guess" then return end
    local v = Game.entryValue(self.entry)
    if not v then
        self:updateStatus(_("Type a number first."))
        return
    end
    st.guesses[self:_seat(st.turn)] = v
    self.entry = ""
    st.turn = st.turn + 1
    if st.turn > #st.players then
        st.turn = 1
        if st.mode == "betting" then
            st.phase = "bethand"
        else
            self:_reveal()
        end
    else
        st.phase = "handover"
    end
    self:_save()
    self:_redraw()
end

function EstimationScreen:_slots()
    return Game.buildSlots(self.st.guesses, #self.st.players)
end

function EstimationScreen:onSlotTap(i)
    local st = self.st
    if st.phase ~= "bet" then return end
    local bet = st.bets[self:_seat(st.turn)]
    if Game.chipsPlaced(bet) >= Game.CHIPS then
        self:updateStatus(_("No chips left: tap Remove chips to change your bet."))
        return
    end
    bet[i] = (bet[i] or 0) + 1
    self:_redraw()
end

function EstimationScreen:onClearBet()
    local st = self.st
    if st.phase ~= "bet" then return end
    st.bets[self:_seat(st.turn)] = {}
    self:_redraw()
end

function EstimationScreen:onConfirmBet()
    local st = self.st
    if st.phase ~= "bet" then return end
    if Game.chipsPlaced(st.bets[self:_seat(st.turn)]) == 0 then
        self:updateStatus(_("Place at least one chip."))
        return
    end
    st.turn = st.turn + 1
    if st.turn > #st.players then
        st.turn = 1
        self:_reveal()
    else
        st.phase = "bethand"
    end
    self:_save()
    self:_redraw()
end

function EstimationScreen:_reveal()
    local st = self.st
    local q = self:_question()
    st.pts = Game.scoreQuestion(st.mode, st.guesses, st.bets, q.answer, #st.players)
    for p, n in pairs(st.pts) do
        st.players[p].score = st.players[p].score + n
    end
    st.phase = "reveal"
    self:_markAsked(q.id)
end

function EstimationScreen:onNextQuestion()
    local st = self.st
    if st.phase ~= "reveal" then return end
    if st.qi >= #st.qids then
        st.phase = "final"
        self:_save()
        self:_redraw()
        return
    end
    st.qi = st.qi + 1
    self:_startQuestion()
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

local function countItems(list, fmt)
    local items = {}
    for _i, n in ipairs(list) do
        items[#items + 1] = { id = n, text = fmt and T(fmt, n) or tostring(n) }
    end
    return items
end

function EstimationScreen:_setAndRestart(key, field, value)
    self[field] = value
    self.plugin:saveSetting(key, value)
    self:onNewGame()
end

function EstimationScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = { { id = "fr", text = "Français" }, { id = "en", text = "English" } },
        current_id = self.lang,
        parent     = self,
        on_select  = function(id)
            self.lang = id
            self.plugin:setLang(id)
            self:onNewGame()
        end,
    }
end

function EstimationScreen:openPlayersMenu()
    local list = {}
    for n = Game.MIN_PLAYERS, Game.MAX_PLAYERS do list[#list + 1] = n end
    MenuHelper.openPickerMenu{
        title      = _("Players"),
        items      = countItems(list),
        current_id = self.nplayers,
        parent     = self,
        on_select  = function(n) self:_setAndRestart("players", "nplayers", n) end,
    }
end

function EstimationScreen:openQuestionsMenu()
    MenuHelper.openPickerMenu{
        title      = _("Questions"),
        items      = countItems(Game.QUESTION_COUNTS),
        current_id = self.nq,
        parent     = self,
        on_select  = function(n) self:_setAndRestart("questions", "nq", n) end,
    }
end

function EstimationScreen:openScoringMenu()
    local items = {}
    for _i, m in ipairs(Game.MODES) do items[#items + 1] = { id = m, text = MODE_LABELS[m] } end
    MenuHelper.openPickerMenu{
        title      = _("Scoring"),
        items      = items,
        current_id = self.mode,
        parent     = self,
        on_select  = function(m) self:_setAndRestart("scoring", "mode", m) end,
    }
end

function EstimationScreen:_catsMenuText()
    if not self.cats then return T(_("Categories: %1"), _("All")) end
    local n = 0
    for _k in pairs(self.cats) do n = n + 1 end
    return T(_("Categories: %1"), n .. "/" .. #Questions.CATEGORIES)
end

-- Multi-select: each tap toggles a category and the list comes back. The
-- change applies from the next game.
function EstimationScreen:openCategoriesMenu()
    local bank = Questions.forLanguage(self.lang)
    local items = { { id = "__all__", text = (self.cats and "  " or "★ ") .. _("All") } }
    for _i, c in ipairs(Questions.CATEGORIES) do
        local on = not self.cats or self.cats[c]
        items[#items + 1] = {
            id   = c,
            text = (on and "✓ " or "○ ") .. catLabel(c, self.lang) .. string.format("  (%d)", #bank.by_cat[c]),
        }
    end
    MenuHelper.openPickerMenu{
        title     = _("Categories"),
        items     = items,
        parent    = self,
        on_select = function(id)
            if id == "__all__" then
                self.cats = nil
            else
                if not self.cats then
                    self.cats = {}
                    for _i, c in ipairs(Questions.CATEGORIES) do self.cats[c] = true end
                end
                self.cats[id] = (not self.cats[id]) or nil
                local all, none = true, true
                for _i, c in ipairs(Questions.CATEGORIES) do
                    if self.cats[c] then none = false else all = false end
                end
                if all or none then self.cats = nil end
            end
            self:_saveCats()
            self:openCategoriesMenu()
        end,
    }
end

function EstimationScreen:openNamesMenu()
    local names = {}
    for i, pl in ipairs(self.st.players) do names[i] = pl.name end
    Players.openEditor(self.plugin, names, function()
        for i, pl in ipairs(self.st.players) do pl.name = names[i] end
        self:_save()
        self:_redraw()
    end, self)
end

function EstimationScreen:_titleBar()
    return self:buildTitleBar(_("Estimation"), function()
        return {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Language: %1"), self.lang:upper()), callback = function() self:openLangMenu() end },
            { text = T(_("Players: %1"), self.nplayers), callback = function() self:openPlayersMenu() end },
            { text = T(_("Questions: %1"), self.nq), callback = function() self:openQuestionsMenu() end },
            { text = T(_("Scoring: %1"), MODE_LABELS[self.mode]), callback = function() self:openScoringMenu() end },
            { text = self:_catsMenuText(), callback = function() self:openCategoriesMenu() end },
            { text = _("Player names"), callback = function() self:openNamesMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function EstimationScreen:_fmt(v, q)
    q = q or self:_question()
    local s = Game.formatNumber(v, self.st.lang, q.is_year)
    if q.suffix ~= "" then s = s .. "\u{00A0}" .. q.suffix end
    return s
end

function EstimationScreen:_progress()
    return T(_("Question %1/%2"), self.st.qi, #self.st.qids)
end

function EstimationScreen:buildLayout()
    local phase = self.st.phase
    local title_bar = self:_titleBar()
    local controls = self:_buildControls()
    local bw, bh = self:getBoardBudget(title_bar, controls)
    -- Content is built at full scale, then smaller until it fits the room left.
    local content
    local scale = 1
    while true do
        content = self:_buildContent(phase, bw, bh, scale)
        if content:getSize().h <= bh or scale < 0.5 then break end
        scale = scale * 0.85
    end
    if phase == "handover" or phase == "bethand" then
        content = TapArea:new{ callback = function() self:onReady() end, content }
    end
    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = bw, h = math.min(bh, math.max(content:getSize().h, 1)) }, content },
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function EstimationScreen:_buildControls()
    local phase = self.st.phase
    local w = self:getControlsWidth()
    self.status_text:setMaxWidth(w)
    local group = VerticalGroup:new{ align = "center", self.status_text,
                                     VerticalSpan:new{ width = Size.span.vertical_large } }
    local rows
    if phase == "handover" or phase == "bethand" then
        rows = { { text = _("Ready"), callback = function() self:onReady() end } }
    elseif phase == "guess" then
        local keys = {}
        for d = 1, 10 do
            local digit = d % 10
            keys[d] = { text = tostring(digit), callback = function() self:onDigit(digit) end }
        end
        group[#group + 1] = self:buildNumberPad(keys, w)
        group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
        rows = {
            { text = "±", callback = function() self:onSign() end },
            { text = _("Erase"), callback = function() self:onErase() end },
            { text = _("Validate"), callback = function() self:onValidateGuess() end },
        }
    elseif phase == "bet" then
        rows = {
            { text = _("Remove chips"), callback = function() self:onClearBet() end },
            { text = _("Confirm"), callback = function() self:onConfirmBet() end },
        }
    elseif phase == "reveal" then
        local last = self.st.qi >= #self.st.qids
        rows = { { text = last and _("Final scores") or _("Next question"),
                   callback = function() self:onNextQuestion() end } }
    else
        rows = { { text = _("New game"), callback = function() self:onNewGame() end } }
    end
    group[#group + 1] = self:buildActionBar(rows, w)
    return group
end

function EstimationScreen:_buildContent(phase, bw, bh, k)
    local short = math.min(bw, bh, self.dimen.w)
    local vs = Size.span.vertical_large
    local g = VerticalGroup:new{ align = "center" }
    local function add(w) g[#g + 1] = w end
    local q = self:_question()
    local cat = catLabel(q.cat, self.st.lang)

    if phase == "handover" or phase == "bethand" then
        local who = self:_current().name
        add(fitLine(self:joinStatus(self:_progress(), cat), short * 0.045 * k, bw))
        add(vspan(vs * 3 * k))
        add(fitBox(T(_("Pass the reader to %1"), who), short * 0.06 * k, bw))
        add(vspan(vs * 2 * k))
        add(fitLine(who, short * 0.13 * k, bw, true))
        add(vspan(vs * 3 * k))
        add(fitBox(phase == "bethand" and _("Tap Ready to place your bet in secret.")
                                       or _("Tap Ready to see the question and type your guess in secret."),
                   short * 0.04 * k, bw))
    elseif phase == "guess" then
        add(fitLine(cat, short * 0.045 * k, bw))
        add(vspan(vs * k))
        add(fitBox(q.question, short * 0.065 * k, bw, bh * 0.45))
        add(vspan(vs * 2 * k))
        if q.prompt ~= "" then
            add(fitLine(q.prompt, short * 0.045 * k, bw))
            add(vspan(vs * k))
        end
        local v = Game.entryValue(self.entry)
        local shown
        if v then shown = self:_fmt(v, q)
        elseif self.entry == "-" then shown = "−"
        else shown = "?" end
        local inner_w = bw - 2 * (Size.padding.large + Size.border.window)
        local num = fitLine(shown, short * 0.12 * k, inner_w, true)
        add(FrameContainer:new{
            padding = Size.padding.large, margin = 0,
            bordersize = Size.border.window,
            CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = num:getSize().h }, num },
        })
    elseif phase == "bet" then
        add(fitBox(q.question, short * 0.05 * k, bw, bh * 0.25))
        add(vspan(vs * k))
        add(self:_slotTable(bw, k))
    elseif phase == "reveal" then
        add(fitLine(self:joinStatus(self:_progress(), cat), short * 0.04 * k, bw))
        add(vspan(vs * k))
        add(fitBox(q.question, short * 0.045 * k, bw, bh * 0.2))
        add(vspan(vs * k))
        add(fitLine(self:_fmt(q.answer, q), short * 0.12 * k, bw, true))
        add(vspan(vs * k))
        if q.fact ~= "" then
            add(fitBox(q.fact, short * 0.04 * k, bw, bh * 0.2))
            add(vspan(vs * k))
        end
        add(rule(bw * 0.6))
        add(vspan(vs * k))
        add(self:_revealRows(bw, short * 0.042 * k))
    else
        add(fitLine(_("Final scores"), short * 0.08 * k, bw, true))
        add(vspan(vs * 2 * k))
        local rows = {}
        local order = Game.ranking(self.st.players)
        local prev, rank = nil, 0
        for i, p in ipairs(order) do
            local pl = self.st.players[p]
            if pl.score ~= prev then rank = i; prev = pl.score end
            rows[#rows + 1] = { tostring(rank) .. ".", pl.name, tostring(pl.score), bold = rank == 1 }
        end
        add(self:_table(rows, bw, short * 0.055 * k, { { 0.12, "left" }, { 0.6, "left" }, { 0.28, "right" } }))
    end
    return g
end

-- Rows of cells: { { c1, c2, ..., bold = bool }, ... }; cols = { { fraction,
-- "left"|"right" }, ... }.
function EstimationScreen:_table(rows, w, px, cols)
    local g = VerticalGroup:new{ align = "left" }
    local face, bface = pxFace(px), pxFace(px, true)
    for _i, r in ipairs(rows) do
        local h = HorizontalGroup:new{ align = "center" }
        for c, col in ipairs(cols) do
            local cw = math.floor(w * col[1])
            local txt = TextWidget:new{ text = r[c] or "", face = r.bold and bface or face,
                                        bold = r.bold, max_width = cw - Size.padding.small }
            local box = col[2] == "left" and LeftContainer or RightContainer
            h[#h + 1] = box:new{ dimen = Geom:new{ w = cw, h = txt:getSize().h }, txt }
        end
        g[#g + 1] = h
        g[#g + 1] = vspan(px * 0.25)
    end
    return g
end

-- After a question: every guess, sorted, with the points it brought.
function EstimationScreen:_revealRows(w, px)
    local st = self.st
    local q = self:_question()
    local order = {}
    for p = 1, #st.players do order[#order + 1] = p end
    table.sort(order, function(a, b)
        local ga, gb = st.guesses[a], st.guesses[b]
        if ga ~= gb then return ga < gb end
        return a < b
    end)
    local win_slot, slots
    if st.mode == "betting" then
        slots = self:_slots()
        win_slot = Game.winningSlot(slots, q.answer)
    end
    local rows = {}
    for _i, p in ipairs(order) do
        local pts = st.pts and st.pts[p]
        local g = st.guesses[p]
        local mark = ""
        if st.mode == "betting" then
            if win_slot > 0 and slots[win_slot].value == g then mark = "★ " end
        elseif pts then
            mark = "★ "
        end
        rows[#rows + 1] = {
            mark .. st.players[p].name,
            g and self:_fmt(g, q) or "—",
            pts and ("+" .. pts) or "",
            bold = pts ~= nil,
        }
    end
    local g = VerticalGroup:new{ align = "center" }
    if st.mode == "betting" then
        local s = slots[win_slot]
        local what = win_slot == 0 and _("Lower than every guess") or self:_fmt(s.value, q)
        g[#g + 1] = fitLine(T(_("Winning slot: %1 (×%2)"), what, s.odds), px, w)
        g[#g + 1] = vspan(px * 0.4)
    end
    g[#g + 1] = self:_table(rows, w, px, { { 0.45, "left" }, { 0.37, "right" }, { 0.18, "right" } })
    return g
end

-- The betting board: one button per slot; tapping places a chip.
function EstimationScreen:_slotTable(w, k)
    local st = self.st
    local q = self:_question()
    local slots = self:_slots()
    local bet = st.bets[self:_seat(st.turn)] or {}
    local rows = {}
    for i = 0, #slots do
        local s = slots[i]
        local label
        if i == 0 then
            label = _("Lower than every guess")
        else
            local names = {}
            for _i, p in ipairs(s.owners) do names[#names + 1] = st.players[p].name end
            label = self:_fmt(s.value, q) .. " · " .. table.concat(names, ", ")
        end
        label = label .. "  ×" .. s.odds
        if bet[i] then label = string.rep("●", bet[i]) .. "  " .. label end
        local slot = i
        rows[#rows + 1] = { { text = label, callback = function() self:onSlotTap(slot) end } }
    end
    return ButtonTable:new{ width = w, buttons = rows }
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function EstimationScreen:_leaderText()
    local leaders, best = Game.leaders(self.st.players)
    local names = {}
    for _i, i in ipairs(leaders) do names[#names + 1] = self.st.players[i].name end
    if #leaders > 1 then
        return T(_("Tie: %1"), table.concat(names, ", ")) .. " (" .. best .. ")"
    end
    return T(_("%1 wins!"), names[1]) .. " (" .. best .. ")"
end

function EstimationScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local st = self.st
    local s
    if st.phase == "handover" or st.phase == "bethand" then
        s = self:joinStatus(MODE_LABELS[st.mode], T(_("Turn %1/%2"), st.turn, #st.players))
    elseif st.phase == "guess" then
        s = self:joinStatus(self:_current().name, self:_progress())
    elseif st.phase == "bet" then
        local left = Game.CHIPS - Game.chipsPlaced(st.bets[self:_seat(st.turn)])
        s = self:joinStatus(self:_current().name, T(_("Chips left: %1"), left))
    elseif st.phase == "reveal" then
        local any = st.pts and next(st.pts) ~= nil
        s = any and self:_scoreLine() or self:joinStatus(_("Nobody scores this time."), self:_scoreLine())
    else
        s = self:_leaderText()
    end
    ScreenBase.updateStatus(self, s)
end

function EstimationScreen:_scoreLine()
    local parts = {}
    for _i, p in ipairs(Game.ranking(self.st.players)) do
        local pl = self.st.players[p]
        parts[#parts + 1] = T(_("%1: %2"), pl.name, pl.score)
    end
    return self:joinStatus((table.unpack or unpack)(parts))
end

-- The questions are only needed while a game is open: drop them when the
-- screen closes (the next game reads its language's questions again).
function EstimationScreen:onCloseWidget()
    Questions.release()
end

return EstimationScreen
