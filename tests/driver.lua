-- BattlePad end-to-end driver: boots the real engine headlessly
-- (POKEPORT_DRIVER), fights real wild battles through the pad path, the
-- stick path and the keyboard path, exercises queueing, the bag/party
-- skins, the hold-to-run gate and the stand-down fallback, and captures
-- screenshots of every surface.  Writes a PASS/FAIL report to BP_OUT.
--
-- Run from the engine root (shots land in the repo's dot-dir so neither
-- git nor modkit pack ever carries them):
--   POKEPORT_IDENTITY=battlepad-test POKEPORT_VERSION=red POKEPORT_SPEED=8 \
--   POKEPORT_DRIVER=C:/Users/User/Projects/battlepad/tests/driver.lua \
--   SHOT_DIR=C:/Users/User/Projects/battlepad/.shots \
--   BP_OUT=C:/Users/User/Projects/battlepad/.shots/report.txt love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"
  local OUT = os.getenv("BP_OUT") or (DIR .. "/report.txt")

  local lines, pass, fail = {}, 0, 0
  local function say(fmt, ...)
    lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
  end
  local function ck(label, cond)
    if cond then pass = pass + 1 else fail = fail + 1 end
    say("  %s  %s", cond and "PASS" or "FAIL", label)
  end
  local function flush()
    os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
    say("")
    say("%d passed, %d failed", pass, fail)
    local f = io.open(OUT, "w")
    if f then f:write(table.concat(lines, "\n") .. "\n") f:close() end
  end

  local Input = require("src.core.Input")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  local function waitFor(cond, max)
    for _ = 1, max or 900 do
      if cond() then return true end
      U.wait(1)
    end
    return false
  end
  local function mashUntil(cond, max)
    for _ = 1, max or 200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return false
  end

  -- pad helpers: drive the wrapped raw funnel exactly like SDL would
  local function padTap(button)
    Input:gamepadpressed(nil, button)
    U.wait(2)
    Input:gamepadreleased(nil, button)
    U.wait(2)
  end

  -- ---- boot state -------------------------------------------------
  say("== LOADER ==")
  local st = game.modStatus or (game.mods and game.mods.status and game.mods:status()) or {}
  local seenBP, seenUBC = false, false
  for _, m in ipairs(st.available or {}) do
    say("  %-20s v%-8s state=%s", tostring(m.id), tostring(m.version), tostring(m.state))
    if m.id == "battle_pad" and m.state == "loaded" then seenBP = true end
    if m.id == "USEFUL_BATTLE_CAM" and m.state == "loaded" then seenUBC = true end
  end
  ck("battle_pad loaded", seenBP)
  ck("USEFUL_BATTLE_CAM not co-loaded", not seenUBC)

  -- a fixed, lock-free moveset (level-up RAGE would arm Gen 1's menu lock
  -- mid-test) against a foe with the HP to survive the whole scripted fight
  local mon = Pokemon.new(game.data, "CHARMANDER", 25)
  mon.moves = {
    { id = "SCRATCH", pp = 35 },
    { id = "GROWL", pp = 40 },
    { id = "EMBER", pp = 25 },
    { id = "LEER", pp = 30 },
  }
  table.insert(game.save.party, 1, mon)
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local function newBattle(species, level)
    local battle = BattleState.newWild(game, species or "CHANSEY", level or 35)
    battle.onFinish = function() end
    ow:pushBattle(battle)
    mashUntil(function() return battle.phase == "menu" end)
    U.wait(6)
    return battle
  end
  local function endBattle()
    while game.stack:top() ~= ow do game.stack:pop() end
    U.wait(5)
  end
  -- battle attrition (failed escape rolls cost turns) can faint the fixture
  -- mon mid-suite; each section starts from a healed party like a fresh
  -- fixture, or the engine rightly refuses the next wild battle
  local function healParty()
    for _, m in ipairs(game.save.party) do
      m.hp = m.stats.hp
      m.status = nil
    end
  end

  -- ---- A. pad path: d-pad highlight, A commit ---------------------
  say("== A. PAD PATH ==")
  local battle = newBattle()
  ck("deck owns the menu", battle._bp == nil or battle._bp.disabled ~= true)
  U.shot(game, DIR .. "/a0_deck_menu.png")
  padTap("a") -- FIGHT: enter the move compass
  U.wait(2)
  ck("A opens the move compass", battle.phase == "moveSelect")
  U.shot(game, DIR .. "/a0b_deck_moves.png")
  padTap("dpup")
  local bp = battle._bp or {}
  ck("d-pad north highlights move 1", bp.highlight
      and bp.highlight.kind == "move" and bp.highlight.index == 1)
  ck("vanilla cursor never moved", battle.menuIndex == 1)
  U.shot(game, DIR .. "/a1_deck_highlight.png")
  padTap("a")
  U.wait(4)
  ck("A commits the highlighted move", (battle.turnCount or 0) == 1)
  ck("the turn is resolving", battle.phase == "messages")
  U.shot(game, DIR .. "/a2_resolve_spinners.png")

  -- ---- B. queueing while the foe acts -----------------------------
  say("== B. QUEUE ==")
  padTap("dpup")
  bp = battle._bp or {}
  ck("a direction queues during the foe's turn", bp.queued
      and bp.queued.kind == "move" and bp.queued.index == 1)
  U.shot(game, DIR .. "/b0_queued.png")
  mashUntil(function() return (battle.turnCount or 0) >= 2 end)
  ck("the queued move fired by itself", (battle.turnCount or 0) >= 2)

  -- ---- C. face buttons open the skinned screens -------------------
  say("== C. SCREENS ==")
  mashUntil(function() return battle.phase == "menu" end)
  U.wait(4)
  say("  [dbg] pre-X phase=%s top==battle=%s claim=%s",
      tostring(battle.phase), tostring(game.stack:top() == battle),
      tostring(require("src.core.Input").gamepadpressed ~= nil))
  padTap("x")
  U.wait(6)
  local dbgTop = game.stack:top()
  say("  [dbg] post-X phase=%s top==battle=%s topSkin=%s topType=%s queued=%s hl=%s",
      tostring(battle.phase), tostring(dbgTop == battle),
      tostring(dbgTop and dbgTop._bpSkin),
      tostring(dbgTop and (dbgTop.title or (dbgTop.isOpaque and "opaque") or "?")),
      tostring(battle._bp and battle._bp.queued and battle._bp.queued.kind),
      tostring(battle._bp and battle._bp.highlight and battle._bp.highlight.kind))
  local opened = waitFor(function()
    local top = game.stack:top()
    return top ~= battle and top and top._bpSkin == "bag"
  end, 240)
  ck("X opens the bag, skinned", opened)
  U.shot(game, DIR .. "/c0_bag_skin.png")
  padTap("b")
  waitFor(function() return game.stack:top() == battle end, 240)
  mashUntil(function() return battle.phase == "menu" end)
  ck("B backs out of the bag to the deck", game.stack:top() == battle)

  padTap("y")
  opened = waitFor(function()
    local top = game.stack:top()
    return top ~= battle and top and top._bpSkin == "party"
  end, 240)
  ck("Y opens the party, skinned", opened)
  U.shot(game, DIR .. "/c1_party_skin.png")
  padTap("b")
  waitFor(function() return game.stack:top() == battle end, 240)
  mashUntil(function() return battle.phase == "menu" end)
  ck("B backs out of the party to the deck", game.stack:top() == battle)

  -- ---- D. left-stick radial ---------------------------------------
  say("== D. STICK RADIAL ==")
  say("  [dbg] pre-stick phase=%s top==battle=%s",
      tostring(battle.phase), tostring(game.stack:top() == battle))
  padTap("a") -- FIGHT first: sticks pick moves on the compass step
  U.wait(2)
  Input:gamepadaxis(nil, "leftx", 1.0)
  U.wait(3)
  bp = battle._bp or {}
  say("  [dbg] post-stick hl=%s idx=%s phase=%s",
      tostring(bp.highlight and bp.highlight.kind),
      tostring(bp.highlight and bp.highlight.index), tostring(battle.phase))
  ck("stick east highlights move 3", bp.highlight
      and bp.highlight.kind == "move" and bp.highlight.index == 3)
  U.shot(game, DIR .. "/d0_stick_highlight.png")
  Input:gamepadaxis(nil, "leftx", 0.0)
  U.wait(4)
  ck("flick release commits move 3", (battle.turnCount or 0) >= 3
      and battle.phase == "messages")
  mashUntil(function() return battle.phase == "menu" end)

  -- ---- E. keyboard path -------------------------------------------
  say("== E. KEYBOARD ==")
  local before = battle.turnCount or 0
  U.tap(game, "a") -- FIGHT
  U.wait(2)
  U.tap(game, "left")
  U.wait(2)
  bp = battle._bp or {}
  ck("arrow west highlights move 2", bp.highlight
      and bp.highlight.kind == "move" and bp.highlight.index == 2)
  U.tap(game, "a")
  U.wait(4)
  ck("keyboard A commits", (battle.turnCount or 0) == before + 1)
  mashUntil(function() return battle.phase == "menu" end)

  -- ---- F. hold-to-run ---------------------------------------------
  say("== F. RUN ==")
  -- the escape roll is Gen 1's own; a failed roll costs the turn, so hold
  -- again until it lands, like a player would
  local escaped = false
  for _ = 1, 6 do
    mashUntil(function() return battle.phase == "menu" end, 120)
    if game.stack:top() ~= ow then
      Input:gamepadpressed(nil, "b")
      U.wait(60)
      Input:gamepadreleased(nil, "b")
      U.wait(4)
    end
    if mashUntil(function() return game.stack:top() == ow end, 120) then
      escaped = true
      break
    end
  end
  ck("holding B runs from the wild battle", escaped)

  -- ---- G. stand-down fallback -------------------------------------
  say("== G. FALLBACK ==")
  healParty()
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  ow = game.overworld
  local battle2 = newBattle("CHANSEY", 35)
  say("  [dbg] G phase=%s party1hp=%s", tostring(battle2.phase),
      tostring(game.save.party[1] and game.save.party[1].hp))
  battle2._bp = { disabled = true, lrad = { peak = 0 }, rrad = { peak = 0 } }
  U.wait(2)
  U.tap(game, "a")
  U.wait(4)
  ck("stood down, vanilla FIGHT opens the move list",
     battle2.phase == "moveSelect")
  U.shot(game, DIR .. "/g0_vanilla_fallback.png")
  U.tap(game, "b")
  U.wait(4)
  endBattle()

  -- ---- H. wide layout ---------------------------------------------
  say("== H. WIDE LAYOUT ==")
  healParty()
  game.save.options.battleLayout = "wide"
  local battle3 = newBattle("CHANSEY", 35)
  say("  [dbg] H phase=%s wide=%s", tostring(battle3.phase),
      tostring(battle3:wideLayout()))
  ck("wide battle reaches the deck", battle3.phase == "menu")
  U.shot(game, DIR .. "/h0_deck_wide.png")
  padTap("a") -- FIGHT: enter the move compass
  U.wait(2)
  U.shot(game, DIR .. "/h0b_moves_wide.png")
  padTap("dpdown")
  bp = battle3._bp or {}
  ck("wide: d-pad south highlights move 4", bp.highlight
      and bp.highlight.kind == "move" and bp.highlight.index == 4)
  padTap("dpup")
  padTap("a")
  U.wait(4)
  ck("wide: a turn resolves", (battle3.turnCount or 0) >= 1)
  U.shot(game, DIR .. "/h1_resolve_wide.png")
  mashUntil(function() return battle3.phase == "menu" end)
  Input:gamepadpressed(nil, "b")
  U.wait(60)
  Input:gamepadreleased(nil, "b")
  mashUntil(function() return game.stack:top() == ow end, 300)
  game.save.options.battleLayout = "og"

  flush()
  U.log("battlepad driver done:", pass .. " passed, " .. fail .. " failed")
end
