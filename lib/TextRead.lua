-- Read the battle message box's typing state back into plain strings.
--
-- BattleState types messages as glyph codes into a rolling two-line window
-- (self.shown), split from self.current.text exactly as startMessage does.
-- The typing STATE is plain data on the battle, so BattlePad re-renders the
-- text without touching the typing logic: re-split the same source string,
-- then cut each visible line at the same glyph count the engine has
-- revealed, using Font.split's spans so a cut never lands mid-character.

local V = ...

local TextRead = {}

local Font -- src.render.Font, required on first use (not headless-safe)

-- The same [\n\v] split startMessage performs.
function TextRead.chunks(text)
  local chunks, pos = {}, 1
  while true do
    local npos = text:find("[\n\v]", pos)
    chunks[#chunks + 1] = npos and text:sub(pos, npos - 1) or text:sub(pos)
    if not npos then break end
    pos = npos + 1
  end
  return chunks
end

-- Visible lines right now, partial reveal applied.  nil when no message is
-- on the box.
function TextRead.visible(battle)
  local current, shown = battle.current, battle.shown
  if not current or type(current.text) ~= "string" or not shown or #shown == 0 then
    return nil
  end
  Font = Font or require("src.render.Font")
  local chunks = TextRead.chunks(current.text)
  local lastLine = battle.lineIndex or #chunks
  local lines = {}
  for i = 1, #shown do
    local chunk = chunks[lastLine - #shown + i]
    if chunk then
      local revealed = #shown[i]
      if revealed <= 0 then
        lines[#lines + 1] = ""
      else
        local spans = Font.split(chunk)
        if revealed >= #spans then
          lines[#lines + 1] = chunk
        else
          lines[#lines + 1] = chunk:sub(1, spans[revealed].to)
        end
      end
    end
  end
  return lines
end

return TextRead
