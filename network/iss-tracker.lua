--[[
@title ISS Tracker
@description Live International Space Station latitude/longitude, polled over WiFi every few seconds.
@category Network
@author lshaf
]]
-- iss-tracker.lua — Live ISS position
-- Polls wheretheiss.at every 5 s and shows the station's latitude /
-- longitude, altitude (km), velocity (km/h) and whether it's currently
-- in daylight or eclipse. A small bordered world-rectangle plots the
-- station's position as a moving dot so you can see it sweep around.
--
-- WiFi follows the same convention as crypto-price.lua: passwords are
-- read from /unigeek/wifi/passwords/<BSSID>_<SSID>.pass. If no stored
-- password is found, the script prompts on the first connect attempt.
--
--   OK   : refresh now / retry on error / start the WiFi prompt
--   BACK : exit (also dismisses any prompt)

local lcd   = require("uni.lcd")
local nav   = require("uni.nav")
local sd    = require("uni.sd")
local input = require("uni.input")
local wifi  = require("uni.wifi")
local http  = require("uni.http")
local json  = require("uni.json")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG      = lcd.color(  4,   8,  22)
local C_HUD_BG  = lcd.color( 22,  22,  38)
local C_TEXT    = lcd.color(220, 220, 240)
local C_DIM     = lcd.color(140, 150, 180)
local C_MAP_BG  = lcd.color( 10,  16,  44)
local C_MAP_LN  = lcd.color( 50,  60,  90)
local C_ISS     = lcd.color(255, 220,  80)
local C_DAY     = lcd.color(255, 200,  90)
local C_NIGHT   = lcd.color(120, 160, 255)
local C_GOOD    = lcd.color(120, 220, 130)
local C_BAD     = lcd.color(255, 110, 110)

-- ── Constants ─────────────────────────────────────────────
local URL          = "https://api.wheretheiss.at/v1/satellites/25544"
local REFRESH_MS   = 5 * 1000
local CONNECT_TMO  = 15000
local PASS_DIR     = "/unigeek/wifi/passwords"

-- ── Layout ────────────────────────────────────────────────
local HUD_H   = 12

local MAP_X   = 4
local MAP_Y   = HUD_H + 4
local MAP_W   = W - 2 * MAP_X
local MAP_H   = math.floor(H * 0.40)
local DOT_S   = 3                            -- ISS dot side length

local STATS_Y    = MAP_Y + MAP_H + 6
local LATLON_Y   = STATS_Y
local ALTVEL_Y   = STATS_Y + 14
local VIS_Y      = ALTVEL_Y + 12
local STATUS_Y   = H - 24
local HINT_Y     = H - 12

-- ── State ─────────────────────────────────────────────────
local iss_lat, iss_lon, iss_alt, iss_vel, iss_vis
local prev_dot_x, prev_dot_y         -- -1 when no dot drawn yet
local last_fetch_ms  = 0
local last_status    = "\0"
local last_remaining = -1
local error_active   = false
local last_ssid      = ""

prev_dot_x, prev_dot_y = -1, -1

-- ── Helpers (pre-allocated) ───────────────────────────────
local function trimWS(s) return string.match(s, "^%s*(.-)%s*$") end

local function findStoredPassword(ssid)
  if not sd.exists(PASS_DIR) then return nil end
  local entries = sd.list(PASS_DIR)
  if not entries then return nil end
  local suffix = "_" .. ssid .. ".pass"
  for _, e in ipairs(entries) do
    if (not e.isDir) and string.sub(e.name, -#suffix) == suffix then
      local raw = sd.read(PASS_DIR .. "/" .. e.name)
      if raw and raw ~= "" then
        local trimmed = trimWS(raw)
        if trimmed ~= "" then return trimmed end
      end
    end
  end
  return nil
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "ISS")

  local right, color
  if wifi.status() == "connected" then
    right = wifi.ip()
    if right == "" then right = "wifi up" end
    color = C_GOOD
  else
    right = "no wifi"
    color = C_BAD
  end
  lcd.textColor(color, C_HUD_BG)
  local rw = lcd.textWidth(right)
  lcd.print(W - rw - 2, 2, right)
end

-- Map box: dark interior, faint border, and a faint equator + prime
-- meridian. Drawn once after a scene repaint; the dot is overdrawn on
-- top so we don't need to redraw the grid every refresh.
local function drawMap()
  lcd.rect(MAP_X, MAP_Y, MAP_W, MAP_H, C_MAP_BG)
  -- Border (1px ring)
  lcd.rect(MAP_X,             MAP_Y,             MAP_W, 1, C_MAP_LN)
  lcd.rect(MAP_X,             MAP_Y + MAP_H - 1, MAP_W, 1, C_MAP_LN)
  lcd.rect(MAP_X,             MAP_Y,             1,     MAP_H, C_MAP_LN)
  lcd.rect(MAP_X + MAP_W - 1, MAP_Y,             1,     MAP_H, C_MAP_LN)
  -- Equator + prime meridian
  local mid_y = MAP_Y + math.floor(MAP_H / 2)
  local mid_x = MAP_X + math.floor(MAP_W / 2)
  lcd.rect(MAP_X + 1, mid_y, MAP_W - 2, 1, C_MAP_LN)
  lcd.rect(mid_x, MAP_Y + 1, 1, MAP_H - 2, C_MAP_LN)
end

local function latlonToXY(la, lo)
  -- Clamp so the dot's 3x3 bounding box stays fully inside the map.
  local inner_w = MAP_W - 2 - DOT_S
  local inner_h = MAP_H - 2 - DOT_S
  local x = math.floor((lo + 180) / 360 * inner_w)
  local y = math.floor((90 - la) / 180 * inner_h)
  return MAP_X + 1 + x, MAP_Y + 1 + y
end

local function eraseDotAt(x, y)
  lcd.rect(x, y, DOT_S, DOT_S, C_MAP_BG)
  -- Redraw grid lines if the erased rect crossed them.
  local mid_y = MAP_Y + math.floor(MAP_H / 2)
  local mid_x = MAP_X + math.floor(MAP_W / 2)
  if mid_y >= y and mid_y < y + DOT_S then
    lcd.rect(x, mid_y, DOT_S, 1, C_MAP_LN)
  end
  if mid_x >= x and mid_x < x + DOT_S then
    lcd.rect(mid_x, y, 1, DOT_S, C_MAP_LN)
  end
end

local function drawDot()
  if iss_lat == nil or iss_lon == nil then return end
  local x, y = latlonToXY(iss_lat, iss_lon)
  if prev_dot_x >= 0 then
    eraseDotAt(prev_dot_x, prev_dot_y)
  end
  lcd.rect(x, y, DOT_S, DOT_S, C_ISS)
  prev_dot_x, prev_dot_y = x, y
end

local function drawCentered(y, text, size, color, band)
  band = band or (size * 8 + 2)
  lcd.rect(0, y, W, band, C_BG)
  if text == nil or text == "" then return end
  lcd.textSize(size)
  lcd.textColor(color, C_BG)
  local tw = lcd.textWidth(text)
  lcd.print(math.floor((W - tw) / 2), y, text)
  lcd.textSize(1)
end

local function fmtLatLon(la, lo)
  if la == nil or lo == nil then return "--, --" end
  local ns = (la >= 0) and "N" or "S"
  local ew = (lo >= 0) and "E" or "W"
  return string.format("%.2f %s   %.2f %s",
                       math.abs(la), ns, math.abs(lo), ew)
end

local function drawLatLon()
  drawCentered(LATLON_Y, fmtLatLon(iss_lat, iss_lon), 1, C_TEXT)
end

local function drawAltVel()
  local s
  if iss_alt == nil and iss_vel == nil then
    s = ""
  else
    local alt = (iss_alt ~= nil) and string.format("Alt %d km", math.floor(iss_alt + 0.5)) or ""
    local vel = (iss_vel ~= nil) and string.format("%d km/h", math.floor(iss_vel + 0.5))    or ""
    if alt ~= "" and vel ~= "" then
      s = alt .. "   " .. vel
    else
      s = alt .. vel
    end
  end
  drawCentered(ALTVEL_Y, s, 1, C_DIM)
end

local function drawVisibility()
  local s, c
  if iss_vis == nil then
    s, c = "", C_DIM
  elseif iss_vis == "daylight" then
    s, c = "in daylight", C_DAY
  elseif iss_vis == "eclipsed" then
    s, c = "in eclipse",  C_NIGHT
  else
    s, c = iss_vis,       C_DIM
  end
  drawCentered(VIS_Y, s, 1, c)
end

local function drawStatus(text, color)
  if text == last_status then return end
  lcd.rect(0, STATUS_Y, W, 10, C_BG)
  last_status = text
  if text == "" then return end
  lcd.textSize(1)
  lcd.textColor(color, C_BG)
  local sw = lcd.textWidth(text)
  lcd.print(math.floor((W - sw) / 2), STATUS_Y, text)
end

local function drawHint()
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local s = "OK refresh   BACK exit"
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, s)
end

local function drawValues()
  drawLatLon()
  drawAltVel()
  drawVisibility()
end

local function drawScene()
  lcd.fillScreen(C_BG)
  drawHUD()
  drawMap()
  prev_dot_x, prev_dot_y = -1, -1     -- map was just repainted; no stale dot
  drawDot()
  drawValues()
  last_status = "\0"
  drawHint()
end

local function ensureWifi()
  if wifi.status() == "connected" then return true end

  local ssid = input.text("WiFi SSID", last_ssid)
  if ssid == nil or ssid == "" then return false end
  last_ssid = ssid

  local pass = findStoredPassword(ssid)
  if not pass then
    pass = input.text("Password for " .. ssid, "")
    if pass == nil then return false end
  end

  drawScene()
  drawStatus(string.format("connecting to %s...", ssid), C_DIM)

  local ok = wifi.connect(ssid, pass, CONNECT_TMO)
  drawHUD()

  if not ok then
    drawStatus("connect failed", C_BAD)
    return false
  end

  drawStatus("connected", C_GOOD)
  return true
end

local function fetchISS()
  if wifi.status() ~= "connected" then return nil, "no wifi" end
  local body, code = http.get(URL)
  if code ~= 200 then return nil, string.format("HTTP %d", code) end
  local data = json.decode(body)
  if (not data) or (not data.latitude) or (not data.longitude) then
    return nil, "parse error"
  end
  return {
    lat = data.latitude,
    lon = data.longitude,
    alt = data.altitude,
    vel = data.velocity,
    vis = data.visibility,
  }, nil
end

local function refresh()
  drawStatus("fetching...", C_DIM)
  local d, err = fetchISS()
  drawHUD()
  if err then
    error_active = true
    drawStatus("error: " .. err, C_BAD)
    uni.beep(220, 120)
    return
  end
  iss_lat = d.lat
  iss_lon = d.lon
  iss_alt = d.alt
  iss_vel = d.vel
  iss_vis = d.vis
  last_fetch_ms  = uni.millis()
  error_active   = false
  last_remaining = -1
  drawDot()
  drawValues()
  drawStatus("", C_DIM)
end

-- ── Init ──────────────────────────────────────────────────
drawScene()

if ensureWifi() then
  refresh()
else
  error_active = true
  drawStatus("press OK to connect wifi", C_BAD)
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "ok" then
    if wifi.status() ~= "connected" then
      if ensureWifi() then refresh() end
    else
      refresh()
    end
  end

  if (not error_active) and iss_lat ~= nil then
    local elapsed = uni.millis() - last_fetch_ms
    if elapsed >= REFRESH_MS then
      refresh()
    else
      local remaining = math.floor((REFRESH_MS - elapsed) / 1000)
      if remaining ~= last_remaining then
        last_remaining = remaining
      end
    end
  end

  uni.delay(200)
end
