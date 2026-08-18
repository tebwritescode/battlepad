-- Which glyphs to draw on the four face buttons, and how to draw them.
--
-- The engine has no controller-brand detection of its own (its only
-- name-substring heuristic is Game.isAccelerometer), so this module carries
-- one: match the joystick's reported name first, fall back to the vendor id
-- packed into the SDL GUID (bytes 5-6, little-endian), and land on the Xbox
-- lettering when neither says anything.  The player can pin a style from the
-- OPTIONS menu; AUTO is the detection below.
--
-- Positions are SDL-positional ("south" is the bottom face button on every
-- pad), so the FIGHT / RUN / POKEMON / PACK meanings never move between
-- brands -- only the printed glyph changes.

local PadIcons = {}

-- name/GUID -> "xbox" | "ps" | "nin" | nil
function PadIcons.detect(name, guid)
  local n = (name or ""):lower()
  if n:find("dualshock", 1, true) or n:find("dualsense", 1, true)
      or n:find("playstation", 1, true) or n:find("sony", 1, true)
      or n:find("ps5", 1, true) or n:find("ps4", 1, true) or n:find("ps3", 1, true)
      or n:find("wireless controller", 1, true) then
    return "ps"
  end
  if n:find("xbox", 1, true) or n:find("xinput", 1, true)
      or n:find("x360", 1, true) or n:find("microsoft", 1, true) then
    return "xbox"
  end
  if n:find("nintendo", 1, true) or n:find("switch", 1, true)
      or n:find("joy-con", 1, true) or n:find("joycon", 1, true)
      or n:find("pro controller", 1, true) or n:find("wii", 1, true) then
    return "nin"
  end
  -- SDL joystick GUID: byte 5-6 carry the USB vendor id, little-endian, as
  -- hex chars 9-12 of the 32-char string.
  if type(guid) == "string" and #guid >= 12 then
    local vendor = tonumber(guid:sub(11, 12) .. guid:sub(9, 10), 16)
    if vendor == 0x054c then return "ps" end
    if vendor == 0x045e then return "xbox" end
    if vendor == 0x057e then return "nin" end
  end
  return nil
end

-- The style to draw right now: a pinned OPTIONS choice wins, then live
-- detection on the pad most recently heard from, then Xbox lettering.
function PadIcons.styleFor(choice, joystick)
  if choice and choice ~= "auto" then return choice end
  if joystick then
    local okN, name = pcall(joystick.getName, joystick)
    local okG, guid = pcall(joystick.getGUID, joystick)
    local found = PadIcons.detect(okN and name or nil, okG and guid or nil)
    if found then return found end
  end
  return "xbox"
end

-- Letter sets.  Nintendo pads print A east / B south, so the letters swap
-- while the positions (and therefore the actions) stay put.
local XBOX = {
  south = { "A", { 0.42, 0.75, 0.29 } },
  east  = { "B", { 0.88, 0.26, 0.28 } },
  west  = { "X", { 0.31, 0.55, 0.90 } },
  north = { "Y", { 0.95, 0.77, 0.24 } },
}
local NIN = {
  south = { "B", { 0.92, 0.93, 0.96 } },
  east  = { "A", { 0.92, 0.93, 0.96 } },
  west  = { "Y", { 0.92, 0.93, 0.96 } },
  north = { "X", { 0.92, 0.93, 0.96 } },
}

-- Draw one face-button glyph at (cx, cy), radius r, in window space.
-- fontObj sizes the lettered styles; PlayStation shapes are pure vectors.
function PadIcons.draw(style, pos, cx, cy, r, fontObj)
  local g = love.graphics
  g.setColor(0.10, 0.11, 0.14, 1)
  g.circle("fill", cx, cy, r)
  g.setLineWidth(math.max(1, r * 0.10))
  g.setColor(1, 1, 1, 0.16)
  g.circle("line", cx, cy, r)
  if style == "ps" then
    local s = r * 0.48
    g.setLineWidth(math.max(1.5, r * 0.17))
    if pos == "south" then -- cross
      g.setColor(0.55, 0.73, 0.92, 1)
      g.line(cx - s, cy - s, cx + s, cy + s)
      g.line(cx - s, cy + s, cx + s, cy - s)
    elseif pos == "east" then -- circle
      g.setColor(0.94, 0.53, 0.50, 1)
      g.circle("line", cx, cy, s)
    elseif pos == "west" then -- square
      g.setColor(0.90, 0.65, 0.90, 1)
      g.rectangle("line", cx - s, cy - s, 2 * s, 2 * s)
    else -- triangle
      g.setColor(0.45, 0.85, 0.72, 1)
      g.polygon("line", cx, cy - s * 1.05, cx - s, cy + s * 0.8, cx + s, cy + s * 0.8)
    end
  else
    local set = (style == "nin") and NIN or XBOX
    local entry = set[pos]
    g.setColor(entry[2][1], entry[2][2], entry[2][3], 1)
    if fontObj then
      local prev = g.getFont()
      g.setFont(fontObj)
      local w = fontObj:getWidth(entry[1])
      local h = fontObj:getHeight()
      g.print(entry[1], cx - w / 2, cy - h / 2)
      if prev then g.setFont(prev) end
    end
  end
  g.setColor(1, 1, 1, 1)
end

return PadIcons
