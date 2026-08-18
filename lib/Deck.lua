-- The command deck: what the pad means while BattlePad owns the battle
-- menu, and what "queued" means while the foe is still acting.
--
-- Layout is a compass on both hands.  D-pad / left stick, moves:
--     north = move 1, west = move 2, east = move 3, south = move 4
-- Face buttons / right stick, commands (SDL-positional, brand-proof):
--     south = FIGHT/confirm, east = RUN, north = POKEMON, west = PACK
-- Keyboard stays whole: arrows are the move compass, A confirms, B backs
-- out (hold to run), SELECT opens the party, START opens the pack.
--
-- Nothing destructive fires from a single touch unless the player opted in:
-- QUICK MOVES commits a move on one tap; RUN always wants a hold or a
-- highlight-then-confirm.

local V = ...
local Config = V.require("Config")
local Capture = V.require("Capture")

local Deck = {}

-- seconds of held B before RUN commits; the RUN HOLD option row decides
function Deck.runHoldSeconds(game)
  return Config.get(game, "run_hold") or 3
end

-- direction -> move slot
Deck.DIR_MOVE = { north = 1, west = 2, east = 3, south = 4 }
-- command compass
Deck.DIR_CMD = { south = "fight", east = "run", north = "party", west = "pack" }

-- Per-battle scratch state, living on the battle instance so it dies with it.
function Deck.state(battle)
  local st = battle._bp
  if not st then
    st = {
      highlight = nil,   -- { kind = "move", index } | { kind = "cmd", cmd }
      queued = nil,      -- { kind, index?, mon } chosen while the foe acts
      runHold = 0,
      disabled = false,  -- an error stood BattlePad down for this battle
      lrad = { peak = 0 },
      rrad = { peak = 0 },
    }
    battle._bp = st
  end
  return st
end

-- Does BattlePad own this battle's menus right now?  Safari, the old-man
-- demo and link battles keep the classic flow: the first two have their own
-- scripted menus, and a link battle's lockstep protocol must see exactly
-- the input the vanilla loop expects (affects_link stays false).
-- Set at game.ready when a Dramatic Shape family mod is loaded; with the
-- 3D BATTLES row on CLASSIC (the default), BattlePad hands every battle to
-- the voxel mod's own presentation and stays fully out of the way.
Deck.voxelPresent = false

local function voxelDefers(game)
  return Deck.voxelPresent and Config.get(game, "voxel_battles") ~= "on"
end

function Deck.owns(battle)
  if not battle or battle.safari or battle.demo then return false end
  if battle.kind == "link" or battle.net or battle.linkRole then return false end
  if voxelDefers(battle.game) then return false end
  local st = battle._bp
  if st and st.disabled then return false end
  return Config.get(battle.game, "enabled") == true
end

-- ---- radial math (pure; unit-tested headlessly) ----

-- SDL stick axes: +x right, +y down.  Returns quadrant, magnitude.
function Deck.quadrant(x, y)
  local mag = math.sqrt(x * x + y * y)
  if mag < 0.001 then return nil, 0 end
  local deg = math.atan2(y, x) * 180 / math.pi
  local q
  if deg > -45 and deg <= 45 then q = "east"
  elseif deg > 45 and deg <= 135 then q = "south"
  elseif deg > -135 and deg <= -45 then q = "north"
  else q = "west" end
  return q, mag
end

-- One episode of stick deflection.  Highlight while deflected; commit on
-- the release edge after a full push (or immediately at full push when
-- `quick`).  Returns quadrant, verb: "hold" | "commit" | "idle".
function Deck.radialStep(episode, x, y, quick)
  local q, mag = Deck.quadrant(x, y)
  if mag >= 0.5 then
    episode.quad = q
    episode.peak = math.max(episode.peak or 0, mag)
    if quick and mag >= 0.85 and not episode.fired then
      episode.fired = true
      return q, "commit"
    end
    return q, "hold"
  end
  if mag < 0.3 then
    local peak, quad, fired = episode.peak, episode.quad, episode.fired
    episode.peak, episode.quad, episode.fired = 0, nil, nil
    if (peak or 0) >= 0.8 and quad and not fired then return quad, "commit" end
    return nil, "idle"
  end
  return episode.quad, "hold"
end

-- ---- queue validation (pure; unit-tested headlessly) ----

-- A queued wish survives only into the situation it was made for: same
-- battler on the field, alive, and (for a move) a slot that still has PP
-- and is not disabled.  Anything else quietly dissolves.
function Deck.validQueued(battle, queued)
  if not queued then return nil end
  local player = battle.player
  if not player or not player.mon then return nil end
  if queued.mon ~= player.mon or player.mon.hp <= 0 then return nil end
  if queued.kind == "move" then
    local mv = player.curMoves and player.curMoves[queued.index]
    if not mv then return nil end
    if (mv.pp or 0) <= 0 then return nil end
    if player.disabledSlot == queued.index then return nil end
  end
  return queued
end

function Deck.takeValidQueued(battle)
  local st = Deck.state(battle)
  local queued = st.queued
  st.queued = nil
  return Deck.validQueued(battle, queued)
end

-- ---- per-frame input reading ----

-- Merge consumed pad edges with keyboard GB edges into one intent set.
-- `battle` only needs .game.input, so both generations' screens qualify.
local function readIntents(battle)
  local intents = {
    dir = nil, confirm = false, cancel = false,
    pack = false, party = false, stickClick = false,
  }
  for _, button in ipairs(Capture.takeEdges()) do
    if button == "dpup" then intents.dir = "north"
    elseif button == "dpleft" then intents.dir = "west"
    elseif button == "dpright" then intents.dir = "east"
    elseif button == "dpdown" then intents.dir = "south"
    elseif button == "a" then intents.confirm = true
    elseif button == "b" then intents.cancel = true
    elseif button == "x" then intents.pack = true
    elseif button == "y" then intents.party = true
    elseif button == "leftstick" or button == "rightstick" then
      intents.stickClick = true
    end
  end
  local input = battle.game.input
  if input:wasPressed("up") then intents.dir = "north" end
  if input:wasPressed("left") then intents.dir = "west" end
  if input:wasPressed("right") then intents.dir = "east" end
  if input:wasPressed("down") then intents.dir = "south" end
  if input:wasPressed("a") then intents.confirm = true end
  if input:wasPressed("b") then intents.cancel = true end
  if input:wasPressed("select") then intents.party = true end
  if input:wasPressed("start") then intents.pack = true end
  return intents
end

local function playPress(battle)
  pcall(function()
    require("src.core.Sound").play(battle.game.data, "Press_AB")
  end)
end

-- ---- the two-step deck ----
--
-- The deck mirrors the classic two-step flow: the COMMAND step shows only
-- FIGHT / RUN / POKEMON / PACK, and the move compass appears after FIGHT.
-- step is "menu" or "moves"; moves/remembered come from the caller so both
-- generations share the logic.

local function commandStep(battle, dt, st, intents)
  if intents.confirm or intents.stickClick then
    local h = st.highlight
    if h and h.kind == "cmd" and h.cmd == "run" then
      playPress(battle)
      st.highlight = nil
      return { kind = "run" }
    end
    playPress(battle)
    st.highlight = nil
    return { kind = "fight" }
  end
  if intents.cancel then st.highlight = nil end
  if intents.pack then playPress(battle) return { kind = "item" } end
  if intents.party then playPress(battle) return { kind = "party" } end

  -- hold-to-run lives on the command step only
  local holdingRun = Capture.isDown("b") or battle.game.input:isDown("b")
  if holdingRun then
    st.runHold = (st.runHold or 0) + (dt or 1 / 60)
    if st.runHold >= Deck.runHoldSeconds(battle.game) then
      st.runHold = 0
      playPress(battle)
      return { kind = "run" }
    end
  else
    st.runHold = 0
  end
  return nil
end

local function movesStep(battle, dt, st, intents, moves, remembered, quick)
  local lx, ly = Capture.stick("left")
  local lq, lverb = Deck.radialStep(st.lrad, lx, ly, quick)
  if lverb == "hold" and lq and moves[Deck.DIR_MOVE[lq]] then
    st.highlight = { kind = "move", index = Deck.DIR_MOVE[lq] }
  elseif lverb == "commit" and lq and moves[Deck.DIR_MOVE[lq]] then
    playPress(battle)
    return { kind = "move", index = Deck.DIR_MOVE[lq] }
  end

  if intents.dir then
    local index = Deck.DIR_MOVE[intents.dir]
    if moves[index] then
      local already = st.highlight and st.highlight.kind == "move"
                      and st.highlight.index == index
      if quick or already then
        playPress(battle)
        return { kind = "move", index = index }
      end
      st.highlight = { kind = "move", index = index }
    end
  end
  if intents.confirm or intents.stickClick then
    local h = st.highlight
    if h and h.kind == "move" and moves[h.index] then
      playPress(battle)
      return { kind = "move", index = h.index }
    end
    st.highlight = { kind = "move",
                     index = math.min(remembered or 1, math.max(#moves, 1)) }
  end
  if intents.cancel then
    st.highlight = nil
    return { kind = "back" }
  end
  if intents.pack then playPress(battle) return { kind = "item" } end
  if intents.party then playPress(battle) return { kind = "party" } end
  return nil
end

-- Returns an action for the puppeteer / semantic calls, or nil.
function Deck.frame(battle, dt, step, moves, remembered)
  local st = Deck.state(battle)
  local quick = Config.get(battle.game, "quick_moves") == true
  local intents = readIntents(battle)
  if step == "moves" then
    return movesStep(battle, dt, st, intents, moves, remembered, quick)
  end
  return commandStep(battle, dt, st, intents)
end

-- ---- the queue frame (phase == messages, foe acting) ----

function Deck.queueFrame(battle, dt)
  local st = Deck.state(battle)
  local intents = readIntents(battle)
  local moves = battle.player.curMoves or {}
  local mon = battle.player.mon

  local function queueMove(index)
    if moves[index] then
      st.queued = { kind = "move", index = index, mon = mon }
    end
  end

  if intents.dir then queueMove(Deck.DIR_MOVE[intents.dir]) end
  if intents.pack then st.queued = { kind = "item", mon = mon } end
  if intents.party then st.queued = { kind = "party", mon = mon } end

  local lx, ly = Capture.stick("left")
  local lq, lverb = Deck.radialStep(st.lrad, lx, ly, false)
  if lverb == "commit" and lq then queueMove(Deck.DIR_MOVE[lq]) end

  -- B clears the wish (and still fast-forwards the text, engine-side)
  if intents.cancel then st.queued = nil end
end

-- ---- the Gen 2 (Gold) arm ----
--
-- Gold's battle screen (src/ui/gen2/BattleState.lua) exposes direct
-- semantic calls -- chooseMenu("fight"|"run"|"item"|"party"),
-- chooseMove(index), submit(action) -- so the Gold deck needs no
-- synthetic-input puppeteer: decide, then call.  Phases: "menu"/"moves"
-- are the deck's, "resolving" is the queue window.  The Bug-Catching
-- Contest and the DUDE catch tutorial keep Gold's own classic menus.

function Deck.owns2(screen)
  if not screen or screen.contest or screen.tutorial then return false end
  if voxelDefers(screen.game) then return false end
  local st = screen._bp
  if st and st.disabled then return false end
  return Config.get(screen.game, "enabled") == true
end

-- Gold move records are { id, pp, maxPp } on screen.battle.player.moves.
function Deck.moves2(screen)
  local battle = screen.battle
  return (battle and battle.player and battle.player.moves) or {}
end

-- One deck frame on Gold: same two steps, Gold's records.
function Deck.frame2(screen, dt)
  local step = screen.phase == "moves" and "moves" or "menu"
  return Deck.frame(screen, dt, step, Deck.moves2(screen), screen.moveIndex)
end

-- Queue while Gold resolves the turn (phase == "resolving").
function Deck.queueFrame2(screen, dt)
  local st = Deck.state(screen)
  local intents = readIntents(screen)
  local moves = Deck.moves2(screen)
  local mon = screen.battle and screen.battle.player

  local function queueMove(index)
    if moves[index] then
      st.queued = { kind = "move", index = index, mon = mon }
    end
  end

  if intents.dir then queueMove(Deck.DIR_MOVE[intents.dir]) end
  if intents.pack then st.queued = { kind = "item", mon = mon } end
  if intents.party then st.queued = { kind = "party", mon = mon } end

  local lx, ly = Capture.stick("left")
  local lq, lverb = Deck.radialStep(st.lrad, lx, ly, false)
  if lverb == "commit" and lq then queueMove(Deck.DIR_MOVE[lq]) end

  if intents.cancel then st.queued = nil end
end

-- A Gold wish survives only into the situation it was made for.
function Deck.takeValidQueued2(screen)
  local st = Deck.state(screen)
  local queued = st.queued
  st.queued = nil
  if not queued then return nil end
  local battle = screen.battle
  local player = battle and battle.player
  if not player or queued.mon ~= player then return nil end
  if queued.kind == "move" then
    local mv = player.moves and player.moves[queued.index]
    if not mv or (mv.pp or 0) <= 0 then return nil end
  end
  return queued
end

return Deck
