-- Every pixel BattlePad puts on screen.  All drawing happens in WINDOW
-- space inside the engine's render.hud hook -- after the finished game
-- frame is composited -- so panels are crisp at any window size and the
-- battle scene above them stays exactly the engine's own.
--
-- The vanilla GB-space text area keeps drawing underneath; these panels are
-- opaque and sit exactly over it.  Skinned screens (bag / party) have their
-- GB draw swapped for a plain white fill, and the whole modern face is
-- painted here from the *live vanilla instance state* -- cursor, scroll,
-- items, party, heal animation -- so behavior stays byte-for-byte vanilla.

local V = ...
local Config = V.require("Config")
local Capture = V.require("Capture")
local Deck = V.require("Deck")
local PadIcons = V.require("PadIcons")
local TextRead = V.require("TextRead")

local Skin = {}

-- ---- palette ----

local C = {
  panel   = { 0.070, 0.080, 0.110, 1 },
  border  = { 1, 1, 1, 0.100 },
  card    = { 0.130, 0.150, 0.200, 1 },
  cardHi  = { 0.210, 0.250, 0.350, 1 },
  inset   = { 0.100, 0.115, 0.155, 1 },
  text    = { 0.930, 0.940, 0.970, 1 },
  dim     = { 0.550, 0.580, 0.660, 1 },
  faint   = { 0.360, 0.385, 0.450, 1 },
  accent  = { 0.360, 0.620, 0.960, 1 },
  danger  = { 0.900, 0.300, 0.300, 1 },
  ok      = { 0.350, 0.780, 0.450, 1 },
  amber   = { 0.950, 0.770, 0.240, 1 },
}

local TYPE_COLORS = {
  NORMAL = { 0.66, 0.66, 0.55 }, FIGHTING = { 0.75, 0.30, 0.25 },
  FLYING = { 0.66, 0.56, 0.95 }, POISON = { 0.63, 0.35, 0.63 },
  GROUND = { 0.85, 0.75, 0.41 }, ROCK = { 0.71, 0.63, 0.42 },
  BUG = { 0.65, 0.72, 0.20 }, GHOST = { 0.44, 0.35, 0.60 },
  FIRE = { 0.93, 0.50, 0.19 }, WATER = { 0.39, 0.56, 0.94 },
  GRASS = { 0.48, 0.78, 0.30 }, ELECTRIC = { 0.97, 0.82, 0.19 },
  PSYCHIC = { 0.98, 0.33, 0.53 }, ICE = { 0.60, 0.85, 0.85 },
  DRAGON = { 0.44, 0.21, 0.98 },
  -- generation 2 (Gold): the type chart grows two entries
  DARK = { 0.37, 0.31, 0.28 }, STEEL = { 0.72, 0.72, 0.79 },
}

-- ---- small helpers ----

local fonts = {}
local function font(px)
  px = math.max(9, math.floor(px + 0.5))
  local f = fonts[px]
  if not f then
    f = love.graphics.newFont(px)
    fonts[px] = f
  end
  return f
end

local function col(c, alpha)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
end

local function rrect(mode, x, y, w, h, r)
  love.graphics.rectangle(mode, x, y, w, h, r, r)
end

local function label(text, x, y, px, c, alpha)
  local f = font(px)
  love.graphics.setFont(f)
  col(c or C.text, alpha)
  love.graphics.print(text, math.floor(x), math.floor(y))
  return f:getWidth(text), f:getHeight()
end

local function labelRight(text, xRight, y, px, c, alpha)
  local f = font(px)
  love.graphics.setFont(f)
  col(c or C.text, alpha)
  love.graphics.print(text, math.floor(xRight - f:getWidth(text)), math.floor(y))
end

local function labelCenter(text, cx, y, px, c, alpha)
  local f = font(px)
  love.graphics.setFont(f)
  col(c or C.text, alpha)
  love.graphics.print(text, math.floor(cx - f:getWidth(text) / 2), math.floor(y))
end

local function panel(x, y, w, h, r)
  col(C.panel)
  rrect("fill", x, y, w, h, r)
  love.graphics.setLineWidth(1)
  col(C.border)
  rrect("line", x + 0.5, y + 0.5, w - 1, h - 1, r)
end

local function now()
  return (love.timer and love.timer.getTime()) or 0
end

-- ---- geometry ----

local function playfield(vp)
  return vp.gameX or 0, vp.gameY or 0,
         vp.gameWidth or (love.graphics and love.graphics.getWidth()) or 0,
         vp.gameHeight or (love.graphics and love.graphics.getHeight()) or 0
end

-- the band the GB text area occupies: bottom third of the playfield
local function bandRect(vp)
  local gx, gy, gw, gh = playfield(vp)
  local y = gy + gh * (96 / 144)
  return gx, y, gw, gy + gh - y
end

-- ---- battle data reads ----

local function moveInfo(battle, index)
  -- Gold battle screens carry the engine battle at .battle and Gold move
  -- records already fold PP-Ups into maxPp; Gen 1 keeps curMoves + ppUps.
  local gen2 = battle.battle and battle.battle.player
  if gen2 then
    local mv = gen2.moves and gen2.moves[index]
    if not mv then return nil end
    local data = battle.battle.data
    local def = data and data.moves and data.moves[mv.id]
    return {
      name = (def and def.name) or tostring(mv.id or "?"),
      type = def and def.type,
      pp = mv.pp or 0,
      maxPP = mv.maxPp or (def and def.pp) or 0,
      disabled = false,
    }
  end
  local mv = battle.player and battle.player.curMoves
             and battle.player.curMoves[index]
  if not mv then return nil end
  local def = battle.data and battle.data.moves and battle.data.moves[mv.id]
  local maxPP = def and (def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)) or 0
  return {
    name = (def and def.name) or tostring(mv.id or "?"),
    type = def and def.type,
    pp = mv.pp or 0,
    maxPP = maxPP,
    disabled = battle.player.disabledSlot == index,
  }
end

local function iconStyle(game)
  return PadIcons.styleFor(Config.get(game, "icons"), Capture.joystick)
end

-- ---- shared pieces ----

local COMPASS = { north = { 0, -1 }, west = { -1, 0 }, east = { 1, 0 }, south = { 0, 1 } }
local CMD_LABEL = { fight = "FIGHT", run = "RUN", party = "PKMN", pack = "PACK" }
local CMD_POS = { south = "fight", east = "run", north = "party", west = "pack" }

-- a small directional tick on a move card's compass edge
local function dirTick(x, y, w, h, dir)
  local cx, cy = x + w / 2, y + h / 2
  local s = math.max(3, h * 0.10)
  col(C.dim)
  if dir == "north" then
    love.graphics.polygon("fill", cx, y - s * 1.6, cx - s, y - 0.5, cx + s, y - 0.5)
  elseif dir == "south" then
    love.graphics.polygon("fill", cx, y + h + s * 1.6, cx - s, y + h + 0.5, cx + s, y + h + 0.5)
  elseif dir == "west" then
    love.graphics.polygon("fill", x - s * 1.6, cy, x - 0.5, cy - s, x - 0.5, cy + s)
  else
    love.graphics.polygon("fill", x + w + s * 1.6, cy, x + w + 0.5, cy - s, x + w + 0.5, cy + s)
  end
end

local function moveCard(battle, index, x, y, w, h, opts)
  opts = opts or {}
  local info = moveInfo(battle, index)
  if not info then
    col(C.inset, 0.5)
    rrect("fill", x, y, w, h, h * 0.16)
    return
  end
  -- one alpha says "can this be committed right now": disabled and empty
  -- slots are grey, and the whole compass greys while the turn resolves
  local usable = not info.disabled and info.pp > 0
  local alpha = usable and 1 or 0.45
  if opts.cooldown then alpha = alpha * 0.60 end
  col(opts.highlight and C.cardHi or C.card, alpha)
  rrect("fill", x, y, w, h, h * 0.16)
  if opts.highlight then
    love.graphics.setLineWidth(math.max(1.5, h * 0.05))
    col(opts.queued and C.amber or C.accent)
    rrect("line", x, y, w, h, h * 0.16)
  end
  -- type stripe
  local tc = TYPE_COLORS[info.type] or { 0.5, 0.5, 0.5 }
  love.graphics.setColor(tc[1], tc[2], tc[3], alpha)
  rrect("fill", x + h * 0.08, y + h * 0.16, math.max(2, w * 0.025), h * 0.68, 2)
  -- text
  local pad = w * 0.08
  label(info.name, x + pad, y + h * 0.12, h * 0.26, C.text, alpha)
  local ppc = info.pp <= 0 and C.danger
              or (info.pp <= math.max(1, math.floor(info.maxPP / 4)) and C.amber)
              or C.dim
  label(info.disabled and "DISABLED"
        or string.format("PP %d/%d", info.pp, info.maxPP),
        x + pad, y + h * 0.55, h * 0.20, info.disabled and C.danger or ppc, alpha)
  if info.type then
    labelRight(tostring(info.type), x + w - pad, y + h * 0.55, h * 0.18, C.faint, alpha)
  end
  if opts.dir then dirTick(x, y, w, h, opts.dir) end
  if opts.queued then
    labelRight("NEXT", x + w - w * 0.06, y + h * 0.10, h * 0.18, C.amber)
  end
end

-- The diamond of four move cards.  ONE geometry for every battle state:
-- the cards never move; what changes is the grey (cooldown) and the
-- highlight.  A layout that repositions the moves between phases reads as
-- the UI jumping around -- these coordinates are the fixed home.
local DIR_OF_INDEX = { "north", "west", "east", "south" }
local function moveDiamond(battle, cx, cy, cw, ch, gapX, gapY, opts)
  opts = opts or {}
  local st = Deck.state(battle)
  for index = 1, 4 do
    local dir = DIR_OF_INDEX[index]
    local dx, dy = COMPASS[dir][1], COMPASS[dir][2]
    local x = cx + dx * gapX - cw / 2
    local y = cy + dy * gapY - ch / 2
    local highlight = st.highlight and st.highlight.kind == "move"
                      and st.highlight.index == index
    local queued = st.queued and st.queued.kind == "move"
                   and st.queued.index == index
    moveCard(battle, index, x, y, cw, ch, {
      highlight = highlight or queued,
      queued = queued,
      dir = dir,
      cooldown = opts.cooldown and moveInfo(battle, index) ~= nil,
    })
  end
end

-- shared fixed geometry for the battle band, both phases
local function deckLayout(vp)
  local bx, by, bw, bh = bandRect(vp)
  return {
    bx = bx, by = by, bw = bw, bh = bh,
    textX = bx + bw * 0.025, textW = bw * 0.34,
    movesX = bx + bw * 0.545, movesY = by + bh * 0.53,
    cardH = bh * 0.25,
    cmdX = bx + bw * 0.868, cmdY = by + bh * 0.47,
    cmdR = bh * 0.115, cmdGap = bh * 0.28,
  }
end

local function commandCluster(battle, cx, cy, r, gap, style, dimmed)
  local st = Deck.state(battle)
  local glyphFont = font(r * 1.05)
  for pos, cmd in pairs(CMD_POS) do
    local dx, dy = COMPASS[pos][1], COMPASS[pos][2]
    local bx, by = cx + dx * gap, cy + dy * gap * 0.92
    local hl = st.highlight and st.highlight.kind == "cmd" and st.highlight.cmd == cmd
    if hl then
      col(cmd == "run" and C.danger or C.accent, 0.9)
      love.graphics.setLineWidth(math.max(1.5, r * 0.14))
      love.graphics.circle("line", bx, by, r * 1.22)
    end
    if Capture.joystick then
      PadIcons.draw(style, pos, bx, by, r, glyphFont)
    else
      -- keyboard sessions: the button IS the key, so the character sits
      -- where the pad glyph would
      local KEY = { south = "Z", east = "X", north = "TAB", west = "ESC" }
      local key = KEY[pos]
      love.graphics.setColor(0.10, 0.11, 0.14, 1)
      love.graphics.circle("fill", bx, by, r)
      love.graphics.setLineWidth(math.max(1, r * 0.10))
      love.graphics.setColor(1, 1, 1, 0.16)
      love.graphics.circle("line", bx, by, r)
      labelCenter(key, bx, by - r * (#key > 1 and 0.32 or 0.52),
                  r * (#key > 1 and 0.62 or 1.0), C.text)
    end
    -- hold-to-run progress ring
    if cmd == "run" and (st.runHold or 0) > 0 then
      local frac = math.min(1, st.runHold / Deck.runHoldSeconds(battle.game))
      love.graphics.setLineWidth(math.max(2, r * 0.18))
      col(C.danger)
      love.graphics.arc("line", "open", bx, by, r * 1.22,
        -math.pi / 2, -math.pi / 2 + frac * 2 * math.pi)
    end
    labelCenter(CMD_LABEL[cmd], bx, by + r * 1.32, r * 0.52,
                hl and C.text or C.dim)
  end
  if dimmed then
    -- resolution scrim: the cluster stays put (X/Y still queue) but reads
    -- as cooling down, like the move cards beside it
    col(C.panel, 0.45)
    rrect("fill", cx - gap - r * 1.5, cy - gap * 0.92 - r * 1.5,
          (gap + r * 1.5) * 2, gap * 0.92 * 2 + r * 3.4, r)
  end
end

-- ---- the deck (phase == menu / moveSelect) ----

function Skin.drawDeck(battle, vp, step)
  local L = deckLayout(vp)
  panel(L.bx, L.by, L.bw, L.bh, L.bh * 0.07)
  -- ONE home for the command cluster across both steps; the move compass
  -- appears beside it after FIGHT.  Nothing ever changes position or size.
  if step == "moves" then
    local cw = math.min(L.bw * 0.22, L.cardH * 4.2)
    moveDiamond(battle, L.bx + L.bw * 0.42, L.movesY,
                cw, L.cardH, cw * 0.55, L.bh * 0.28)
  else
    label("CHOOSE AN ACTION", L.textX, L.by + L.bh * 0.045,
          L.bh * 0.075, C.faint)
  end
  commandCluster(battle, L.cmdX, L.cmdY, L.cmdR, L.cmdGap,
                 iconStyle(battle.game))
end

-- ---- the resolve band (phase == messages) ----

-- Battle text gets the band to itself: no compass, no cluster, so a
-- press can only mean "advance the text".  The one exception is the amber
-- NEXT line when something is queued for the coming turn.
function Skin.drawResolve(battle, vp)
  local L = deckLayout(vp)
  panel(L.bx, L.by, L.bw, L.bh, L.bh * 0.07)
  local lines
  pcall(function() lines = TextRead.visible(battle) end)
  if not lines and type(battle.message) == "string" and battle.message ~= "" then
    lines = {}
    local joined = battle.message .. string.char(10)
    for line in joined:gmatch("([^" .. string.char(10) .. "]*)" .. string.char(10)) do
      if #lines < 2 then lines[#lines + 1] = line end
    end
  end
  if lines then
    for i, line in ipairs(lines) do
      label(line, L.textX, L.by + L.bh * (0.16 + (i - 1) * 0.28),
            L.bh * 0.185, C.text)
    end
    if (battle.msgWaiting or battle.msgPrompt
        or (battle.messageTimer or 0) > 0) and now() % 1.0 < 0.55 then
      local ax = L.bx + L.bw * 0.955
      local ay = L.by + L.bh * 0.82
      col(C.dim)
      love.graphics.polygon("fill", ax, ay + L.bh * 0.07,
        ax - L.bh * 0.05, ay, ax + L.bh * 0.05, ay)
    end
  end
  local st = Deck.state(battle)
  if st.queued then
    local what
    if st.queued.kind == "move" then
      local info = moveInfo(battle, st.queued.index)
      what = (info and info.name) or "?"
    else
      what = CMD_LABEL[st.queued.kind == "item" and "pack"
               or st.queued.kind == "party" and "party" or "run"] or "?"
    end
    label("NEXT: " .. what, L.textX, L.by + L.bh * 0.84, L.bh * 0.11, C.amber)
  end
end

-- ---- skinned screens (bag / party) ----

local function blankDraw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
end

-- Swap a battle-pushed screen's GB draw for a blank fill and remember what
-- modern face to paint over it.  Never touches update(): all input logic,
-- callbacks and the forced-switch contract stay vanilla.
function Skin.tag(screen, id, battle)
  if type(screen) ~= "table" or screen._bpSkin then return end
  if id == "BagMenu" then
    screen._bpSkin = "bag"
  elseif id == "PartyMenu" then
    screen._bpSkin = "party"
  else
    return
  end
  screen._bpBattle = battle
  screen.draw = blankDraw
end

local function screenPanel(vp)
  local gx, gy, gw, gh = playfield(vp)
  local x = gx + gw * 0.05
  local y = gy + gh * 0.05
  local w = gw * 0.90
  local h = gh * 0.90
  panel(x, y, w, h, gh * 0.03)
  return x, y, w, h
end

local function buttonHints(x, yBottom, h, game, hints)
  local style = iconStyle(game)
  local r = h * 0.022
  local cx = x
  local glyphFont = font(r * 1.05)
  for _, hint in ipairs(hints) do
    PadIcons.draw(style, hint[1], cx + r, yBottom, r, glyphFont)
    local w = select(1, label(hint[2], cx + r * 2.4, yBottom - r * 0.75,
                              h * 0.028, C.dim))
    cx = cx + r * 2.4 + w + h * 0.035
  end
end

function Skin.drawBag(list, vp)
  local x, y, w, h = screenPanel(vp)
  local pad = w * 0.045
  label("ITEMS", x + pad, y + h * 0.035, h * 0.055, C.text)
  if type(list.footer) == "string" then
    labelRight(list.footer, x + w - pad, y + h * 0.045, h * 0.035, C.dim)
  end
  local items = list.items or {}
  local rows = list.rows or 7
  local top = y + h * 0.13
  local rowH = (h * 0.75) / rows
  if #items == 0 then
    labelCenter("the pack is empty", x + w / 2, y + h * 0.45, h * 0.04, C.faint)
  end
  for row = 1, rows do
    local i = (list.scroll or 0) + row
    local item = items[i]
    if not item then break end
    local ry = top + (row - 1) * rowH
    if i == list.index then
      col(C.cardHi)
      rrect("fill", x + pad * 0.5, ry, w - pad, rowH * 0.92, rowH * 0.2)
      col(C.accent)
      rrect("fill", x + pad * 0.5, ry + rowH * 0.12, w * 0.006, rowH * 0.68, 2)
    end
    label(tostring(item.label or ""), x + pad * 1.4, ry + rowH * 0.18,
          rowH * 0.42, i == list.index and C.text or C.dim)
    if item.right then
      labelRight(tostring(item.right), x + w - pad * 1.4, ry + rowH * 0.18,
                 rowH * 0.38, C.dim)
    end
  end
  -- scrollbar
  if #items > rows then
    local barX = x + w - pad * 0.45
    col(C.inset)
    rrect("fill", barX, top, w * 0.006, rowH * rows * 0.92, 2)
    local frac = (list.index - 1) / math.max(1, #items - 1)
    col(C.accent)
    love.graphics.circle("fill", barX + w * 0.003,
      top + frac * rowH * rows * 0.92, w * 0.006)
  end
  buttonHints(x + pad, y + h * 0.945, h, list.game, {
    { "south", "USE" }, { "east", "BACK" },
  })
end

local function hpColor(frac)
  if frac > 0.5 then return C.ok end
  if frac > 0.21 then return C.amber end
  return C.danger
end

local function partyPrompt(pm)
  if pm.forceSwitch then return "choose the next POKéMON" end
  if pm.tmhm then return "teach which POKéMON?" end
  if pm.pickOnly then return "use it on which POKéMON?" end
  return "choose a POKéMON"
end

function Skin.drawParty(pm, vp)
  local x, y, w, h = screenPanel(vp)
  local pad = w * 0.045
  label("POKéMON", x + pad, y + h * 0.035, h * 0.055, C.text)
  labelRight(partyPrompt(pm), x + w - pad, y + h * 0.05, h * 0.032, C.dim)
  local party = pm.party or (pm.game and pm.game.save and pm.game.save.party) or {}
  local top = y + h * 0.13
  local rowH = (h * 0.78) / 6
  for i, mon in ipairs(party) do
    local def = pm.game and pm.game.data and pm.game.data.pokemon
                and pm.game.data.pokemon[mon.species]
    local ry = top + (i - 1) * rowH
    local selected = i == pm.index
    col(selected and C.cardHi or C.card, mon.hp > 0 and 1 or 0.55)
    rrect("fill", x + pad * 0.5, ry, w - pad, rowH * 0.90, rowH * 0.16)
    if selected then
      love.graphics.setLineWidth(math.max(1.5, rowH * 0.04))
      col(C.accent)
      rrect("line", x + pad * 0.5, ry, w - pad, rowH * 0.90, rowH * 0.16)
    end
    local name = mon.nickname or (def and def.name) or tostring(mon.species)
    label(name, x + pad * 1.3, ry + rowH * 0.12, rowH * 0.30,
          mon.hp > 0 and C.text or C.faint)
    label("LV " .. tostring(mon.level or "?"), x + pad * 1.3, ry + rowH * 0.50,
          rowH * 0.24, C.dim)
    -- status chip
    local chip = mon.hp <= 0 and "FNT" or mon.status
    if chip then
      local chipW = rowH * 1.1
      col(mon.hp <= 0 and C.danger or C.amber, 0.22)
      rrect("fill", x + w * 0.38, ry + rowH * 0.14, chipW, rowH * 0.32, 4)
      labelCenter(tostring(chip), x + w * 0.38 + chipW / 2, ry + rowH * 0.17,
                  rowH * 0.24, mon.hp <= 0 and C.danger or C.amber)
    end
    -- HP bar + numbers (heal animation shows the travelling value)
    local hp = mon.hp
    if pm.heal and pm.heal.mon == mon then hp = math.floor(pm.heal.shown or hp) end
    local maxHP = (mon.stats and mon.stats.hp) or 1
    local frac = math.max(0, math.min(1, hp / maxHP))
    local barX = x + w * 0.52
    local barW = w * 0.30
    local barY = ry + rowH * 0.30
    col(C.inset)
    rrect("fill", barX, barY, barW, rowH * 0.16, 3)
    if frac > 0 then
      col(hpColor(frac))
      rrect("fill", barX, barY, barW * frac, rowH * 0.16, 3)
    end
    labelRight(string.format("%d/%d", hp, maxHP), x + w - pad * 1.3,
               ry + rowH * 0.14, rowH * 0.26, C.dim)
  end
  -- submenu (SWITCH / STATS / CANCEL ...)
  if pm.submenu and pm.subItems then
    local n = #pm.subItems
    local mw = w * 0.26
    local mh = (h * 0.065) * n + h * 0.02
    local mx = x + w - mw - pad
    local my = y + h * 0.92 - mh
    panel(mx, my, mw, mh, h * 0.012)
    for si, entry in ipairs(pm.subItems) do
      local sy = my + h * 0.012 + (si - 1) * h * 0.065
      if si == pm.subIndex then
        col(C.cardHi)
        rrect("fill", mx + mw * 0.05, sy, mw * 0.90, h * 0.058, 4)
      end
      label(tostring(entry.label or ""), mx + mw * 0.12, sy + h * 0.012,
            h * 0.032, si == pm.subIndex and C.text or C.dim)
    end
  end
  buttonHints(x + pad, y + h * 0.945, h, pm.game, {
    { "south", "CHOOSE" }, { "east", pm.forceSwitch and "—" or "BACK" },
  })
end


-- The last crash, as a screenshot-able panel: Android keeps the save
-- directory unreadable, so with DEBUG LOG on the trace is shown on screen
-- for the first minute of the next boot instead.
function Skin.crashPanel(text, vp)
  local gx, gy, gw, gh = playfield(vp)
  local x, y, w = gx + gw * 0.03, gy + gh * 0.03, gw * 0.94
  local rows = {}
  for line in (text .. string.char(10)):gmatch("([^" .. string.char(10) .. "]*)" .. string.char(10)) do
    if #rows < 16 and line ~= "" then rows[#rows + 1] = line end
  end
  local rowH = gh * 0.028
  local h = rowH * (#rows + 3)
  panel(x, y, w, h, gh * 0.012)
  label("BATTLEPAD - LAST CRASH (screenshot this, then it clears on the next crash)",
        x + w * 0.02, y + rowH * 0.5, rowH * 0.8, C.amber)
  for i, line in ipairs(rows) do
    label(line:sub(1, 120), x + w * 0.02, y + rowH * (i + 1.2), rowH * 0.75, C.text)
  end
end

-- ---- dispatch ----

function Skin.hud(game, vp)
  if not love or not love.graphics or not game or not game.stack then return end
  local top = game.stack:top()
  if not top then return end
  love.graphics.push("all")
  love.graphics.origin()
  if top._bpSkin == "bag" then
    Skin.drawBag(top, vp)
  elseif top._bpSkin == "party" then
    Skin.drawParty(top, vp)
  else
    local Core = V.require("Core")
    local battle = Core.battle
    if battle and top == battle and Deck.owns(battle) then
      local phase = battle.phase
      if phase == "menu" or phase == "moveSelect" then
        Skin.drawDeck(battle, vp, phase == "moveSelect" and "moves" or "menu")
      elseif phase == "messages" then
        Skin.drawResolve(battle, vp)
      end
    else
      local Core2 = V.require("Core2")
      local screen = Core2.installed and Core2.screen
      if screen and top == screen and Deck.owns2(screen) then
        local phase = screen.phase
        if phase == "menu" or phase == "moves" then
          Skin.drawDeck(screen, vp, phase == "moves" and "moves" or "menu")
        elseif phase == "resolving" then
          Skin.drawResolve(screen, vp)
        end
      end
    end
  end
  love.graphics.pop()
end

return Skin
