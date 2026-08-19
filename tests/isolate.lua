-- Isolation probe: start one wild battle and report, in a file, exactly how
-- far the boot got and whether the battle survived.  Used to tell "which
-- mod combination breaks a battle" apart from "the driver hung".
--
--   POKEPORT_IDENTITY=battlepad-test POKEPORT_VERSION=red POKEPORT_SPEED=4 \
--   POKEPORT_DRIVER=<this> ISO_OUT=<file> love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local OUT = os.getenv("ISO_OUT") or "iso.txt"
  local log = {}
  local function say(fmt, ...)
    log[#log + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
    local f = io.open(OUT, "w")            -- rewrite every step: a hard crash
    if f then f:write(table.concat(log, "\n") .. "\n") f:close() end
  end

  say("boot: driver entered")
  local st = game.modStatus or (game.mods and game.mods.status and game.mods:status()) or {}
  for _, m in ipairs(st.available or {}) do
    if m.state == "loaded" then say("mod loaded: %s v%s", tostring(m.id), tostring(m.version)) end
  end
  for _, e in ipairs(st.errors or {}) do say("loader error: %s", tostring(e)) end

  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local mon = Pokemon.new(game.data, "CHARMANDER", 25)
  table.insert(game.save.party, 1, mon)
  say("party ready")

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  say("teleported")
  local ow = game.overworld

  local battle = BattleState.newWild(game, "CHANSEY", 35)
  battle.onFinish = function() end
  say("battle constructed")
  ow:pushBattle(battle)
  say("battle pushed")

  for i = 1, 400 do
    U.wait(1)
    if i % 50 == 0 then say("survived %d frames (phase=%s)", i, tostring(battle.phase)) end
  end
  say("battle survived 400 frames, phase=%s", tostring(battle.phase))

  for _ = 1, 60 do
    U.tap(game, "a")
    U.wait(4)
    if battle.phase == "menu" then break end
  end
  say("reached phase=%s", tostring(battle.phase))
  U.shot(game, (os.getenv("SHOT_DIR") or ".") .. "/iso_battle.png")
  say("DONE ok")
end
