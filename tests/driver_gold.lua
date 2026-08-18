-- BattlePad Gold (Gen 2) end-to-end driver: a real Gold wild battle driven
-- through the pad path, stick path, keyboard path, queueing, pack/party
-- opening and hold-to-run, with screenshots.  Report to BP_OUT.
--
--   POKEPORT_IDENTITY=battlepad-test POKEPORT_VERSION=gold POKEPORT_SPEED=8 \
--   POKEPORT_DRIVER=C:/Users/User/Projects/battlepad/tests/driver_gold.lua \
--   SHOT_DIR=C:/Users/User/Projects/battlepad/.shots_gold \
--   BP_OUT=C:/Users/User/Projects/battlepad/.shots_gold/report.txt love .

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
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
  local function padTap(button)
    Input:gamepadpressed(nil, button)
    U.wait(2)
    Input:gamepadreleased(nil, button)
    U.wait(2)
  end
  local function tap(button)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(2)
  end
  -- advance held messages with B: in the deck a second bare A would COMMIT
  -- a move, so an A-mash fights turns; B only advances text (and harmlessly
  -- clears a highlight)
  local function mashUntil(cond, max)
    for _ = 1, max or 250 do
      if cond() then return true end
      tap("b")
      U.wait(4)
    end
    return false
  end

  U.wait(45)
  local world = game.world
  ck("gold world booted", world ~= nil and world.map ~= nil)

  local player = Mon.new(game.data, "CYNDAQUIL", 25)
  ck("player mon built from cart data", player and #player.moves > 0)
  game.save.party = { player }
  game.save.inventory = { POKE_BALL = 5, POTION = 3 }

  local wild = Mon.new(game.data, "CHANSEY", 35)
  ck("wild CHANSEY built", wild ~= nil)
  ck("battle started", world:startBattle({ wild = wild }))

  local battle
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  ck("battle screen came up", battle ~= nil)
  if not battle then flush() return end
  mashUntil(function() return battle.phase == "menu" end)
  U.wait(6)

  say("== A. PAD PATH ==")
  ck("gold deck owns the menu", battle.phase == "menu")
  U.shot(game, DIR .. "/g_a0_deck.png")
  padTap("a") -- FIGHT: enter the move compass
  U.wait(2)
  ck("A opens the move compass", battle.phase == "moves")
  U.shot(game, DIR .. "/g_a0b_moves.png")
  padTap("dpup")
  local bp = battle._bp or {}
  ck("d-pad north highlights move 1", bp.highlight
      and bp.highlight.kind == "move" and bp.highlight.index == 1)
  ck("vanilla cursor never moved", battle.menuIndex == 1)
  padTap("a")
  U.wait(4)
  ck("A commits: the turn resolves", battle.phase == "resolving")
  U.shot(game, DIR .. "/g_a1_resolve.png")

  say("== B. QUEUE ==")
  padTap("dpup")
  bp = battle._bp or {}
  ck("a direction queues while resolving", bp.queued
      and bp.queued.kind == "move" and bp.queued.index == 1)
  U.shot(game, DIR .. "/g_b0_queued.png")
  -- advance with A here (B would clear the wish); the flush consumes the
  -- menu frame instantly, so "queued gone while resolving" = it fired
  local fired = false
  for _ = 1, 200 do
    bp = battle._bp or {}
    if bp.queued == nil then
      fired = battle.phase == "resolving"
      break
    end
    tap("a")
    U.wait(4)
  end
  ck("the queued move fired by itself", fired)

  say("== C. SCREENS ==")
  mashUntil(function() return battle.phase == "menu" end)
  U.wait(4)
  padTap("x")
  local opened = false
  for _ = 1, 240 do
    local top = game.stack:top()
    if top ~= battle and top and top.pocketIndex ~= nil then opened = true break end
    U.wait(1)
  end
  ck("X opens Gold's pack", opened)
  U.shot(game, DIR .. "/g_c0_pack.png")
  padTap("b")
  mashUntil(function() return game.stack:top() == battle
                          and battle.phase == "menu" end)
  ck("B backs out of the pack", game.stack:top() == battle)

  padTap("y")
  opened = false
  for _ = 1, 240 do
    local top = game.stack:top()
    if top ~= battle and top and top.party ~= nil then opened = true break end
    U.wait(1)
  end
  ck("Y opens Gold's party", opened)
  U.shot(game, DIR .. "/g_c1_party.png")
  padTap("b")
  mashUntil(function() return game.stack:top() == battle
                          and battle.phase == "menu" end)
  ck("B backs out of the party", game.stack:top() == battle)

  say("== D. STICK + KEYBOARD ==")
  padTap("a") -- FIGHT first
  U.wait(2)
  Input:gamepadaxis(nil, "leftx", 1.0)
  U.wait(3)
  bp = battle._bp or {}
  local idx3 = bp.highlight and bp.highlight.kind == "move"
               and bp.highlight.index == 3
  ck("stick east highlights move 3 (or slot empty)",
     idx3 or (battle.battle.player.moves[3] == nil))
  Input:gamepadaxis(nil, "leftx", 0.0)
  U.wait(4)
  if idx3 then
    ck("flick release commits", battle.phase == "resolving")
    mashUntil(function() return battle.phase == "menu" end)
  end
  say("  [dbg] pre-kb phase=%s top==battle=%s moves2=%s",
      tostring(battle.phase), tostring(game.stack:top() == battle),
      tostring(battle.battle.player.moves[2] and battle.battle.player.moves[2].id))
  if battle.phase == "menu" then tap("a") U.wait(2) end -- FIGHT
  tap("left")
  U.wait(2)
  bp = battle._bp or {}
  say("  [dbg] post-kb hl=%s idx=%s phase=%s",
      tostring(bp.highlight and bp.highlight.kind),
      tostring(bp.highlight and bp.highlight.index), tostring(battle.phase))
  ck("arrow west highlights move 2", bp.highlight
      and bp.highlight.kind == "move" and bp.highlight.index == 2)
  tap("a")
  U.wait(4)
  ck("keyboard A commits", battle.phase == "resolving")
  mashUntil(function() return battle.phase == "menu" end)

  say("== F. RUN ==")
  local escaped = false
  for _ = 1, 6 do
    mashUntil(function() return battle.phase == "menu" end, 120)
    if game.stack:top() ~= battle then escaped = true break end
    Input:gamepadpressed(nil, "b")
    U.wait(200)
    Input:gamepadreleased(nil, "b")
    U.wait(4)
    if mashUntil(function() return game.stack:top() ~= battle end, 120) then
      escaped = true
      break
    end
  end
  ck("holding B runs from the wild battle", escaped)

  flush()
  U.log("battlepad gold driver done:", pass .. " passed, " .. fail .. " failed")
end
