--[[
@title Weather
@description Current conditions plus today's high and low from the open-meteo API (no key needed).
@category Network
@author lshaf
]]
-- weather.lua — Current weather and today's high / low
-- Uses the open-meteo API (no key required). On first run the script
-- prompts for a latitude and longitude and saves them to
-- /unigeek/network/weather.txt; pressing DOWN at any time re-enters
-- the location, OK forces a refresh.
--
-- WiFi follows the same convention as crypto-price.lua: passwords are
-- looked up in /unigeek/wifi/passwords/<BSSID>_<SSID>.pass (the format
-- the eapol bruteforce uses to save cracked passwords). If no stored
-- password is found, the script prompts.
--
--   OK   : refresh now / retry on error / start the WiFi prompt
--   DOWN : re-enter latitude / longitude
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
local C_BG     = lcd.color(  8,  18,  30)
local C_HUD_BG = lcd.color( 22,  28,  44)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 150, 180)
local C_TEMP   = lcd.color(255, 200,  90)
local C_COLD   = lcd.color(140, 200, 255)
local C_HOT    = lcd.color(255, 130,  90)
local C_GOOD   = lcd.color(120, 220, 130)
local C_BAD    = lcd.color(255, 110, 110)

-- ── Constants ─────────────────────────────────────────────
local URL_FMT      = "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1"
local REFRESH_MS   = 10 * 60 * 1000    -- 10 minutes
local CONNECT_TMO  = 15000
local CONF_DIR     = "/unigeek/network"
local CONF_PATH    = CONF_DIR .. "/weather.txt"
local PASS_DIR     = "/unigeek/wifi/passwords"

-- ── Layout ────────────────────────────────────────────────
local HUD_H     = 12
local TEMP_SIZE = 3
local TEMP_H    = TEMP_SIZE * 8

local LOC_Y    = HUD_H + 6
local TEMP_Y   = LOC_Y + 12
local COND_Y   = TEMP_Y + TEMP_H + 4
local HILO_Y   = COND_Y + 12
local WIND_Y   = HILO_Y + 12
local STATUS_Y = H - 24
local HINT_Y   = H - 12

-- ── State ─────────────────────────────────────────────────
local lat, lon
local cur_temp, cur_code, cur_wind, cur_rh
local hi_temp, lo_temp
local last_fetch_ms  = 0
local last_status    = "\0"
local last_remaining = -1
local error_active   = false
local last_ssid      = ""

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

local function loadLocation()
  if not sd.exists(CONF_PATH) then return nil, nil end
  local raw = sd.read(CONF_PATH) or ""
  local la, lo = string.match(raw, "([%-%d%.]+)%s*,%s*([%-%d%.]+)")
  if (not la) or (not lo) then return nil, nil end
  return tonumber(la), tonumber(lo)
end

local function saveLocation(la, lo)
  if not sd.exists(CONF_DIR) then sd.mkdir(CONF_DIR) end
  sd.write(CONF_PATH, string.format("%s,%s", tostring(la), tostring(lo)))
end

local function codeToText(c)
  if c == nil then return "---" end
  if c == 0 then return "Clear" end
  if c == 1 then return "Mostly clear" end
  if c == 2 then return "Partly cloudy" end
  if c == 3 then return "Overcast" end
  if c == 45 or c == 48 then return "Fog" end
  if c >= 51 and c <= 57 then return "Drizzle" end
  if c >= 61 and c <= 67 then return "Rain" end
  if c >= 71 and c <= 77 then return "Snow" end
  if c >= 80 and c <= 82 then return "Showers" end
  if c == 85 or c == 86 then return "Snow showers" end
  if c >= 95 and c <= 99 then return "Thunderstorm" end
  return "Code " .. tostring(c)
end

local function tempColor(t)
  if t == nil then return C_DIM end
  if t >= 28 then return C_HOT end
  if t <= 5  then return C_COLD end
  return C_TEMP
end

local function fmtTempInt(t)
  if t == nil then return "--" end
  return string.format("%d", math.floor(t + 0.5))
end

local function fmtTempBig(t)
  if t == nil then return "--" end
  return string.format("%d C", math.floor(t + 0.5))
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Weather")

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

-- Centered-text overdraw helper. Erases a band of `size*8 + 2` pixels
-- so the previous render is gone before the new text lands.
local function drawCentered(y, text, size, color)
  local band = size * 8 + 2
  lcd.rect(0, y, W, band, C_BG)
  if text == nil or text == "" then return end
  lcd.textSize(size)
  lcd.textColor(color, C_BG)
  local tw = lcd.textWidth(text)
  lcd.print(math.floor((W - tw) / 2), y, text)
  lcd.textSize(1)
end

local function drawLocation()
  local s
  if lat and lon then
    s = string.format("%.3f, %.3f", lat, lon)
  else
    s = "no location set"
  end
  drawCentered(LOC_Y, s, 1, C_DIM)
end

local function drawTemp()
  drawCentered(TEMP_Y, fmtTempBig(cur_temp), TEMP_SIZE, tempColor(cur_temp))
end

local function drawCondition()
  drawCentered(COND_Y, codeToText(cur_code), 1, C_TEXT)
end

local function drawHiLo()
  local s
  if hi_temp == nil and lo_temp == nil then
    s = ""
  else
    s = string.format("H %s   L %s", fmtTempInt(hi_temp), fmtTempInt(lo_temp))
  end
  drawCentered(HILO_Y, s, 1, C_DIM)
end

local function drawWindRh()
  local s
  if cur_wind == nil and cur_rh == nil then
    s = ""
  else
    local wind_str = (cur_wind ~= nil) and string.format("Wind %d km/h", math.floor(cur_wind + 0.5)) or ""
    local rh_str   = (cur_rh   ~= nil) and string.format("RH %d%%",      math.floor(cur_rh + 0.5))   or ""
    if wind_str ~= "" and rh_str ~= "" then
      s = wind_str .. "   " .. rh_str
    else
      s = wind_str .. rh_str
    end
  end
  drawCentered(WIND_Y, s, 1, C_DIM)
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
  local s = "OK refresh  DOWN loc"
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, s)
end

local function drawValues()
  drawLocation()
  drawTemp()
  drawCondition()
  drawHiLo()
  drawWindRh()
end

local function drawScene()
  lcd.fillScreen(C_BG)
  drawHUD()
  drawValues()
  last_status = "\0"
  drawHint()
end

-- Returns true if WiFi is up after this call. Prompts when needed.
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

local function promptLocation()
  local la_str = input.text("Latitude  (-90 .. 90)",
                            lat and string.format("%.4f", lat) or "")
  if la_str == nil then return false end
  local la = tonumber(la_str)
  if (not la) or la < -90 or la > 90 then
    drawScene()
    drawStatus("invalid latitude", C_BAD)
    return false
  end

  local lo_str = input.text("Longitude (-180 .. 180)",
                            lon and string.format("%.4f", lon) or "")
  if lo_str == nil then return false end
  local lo = tonumber(lo_str)
  if (not lo) or lo < -180 or lo > 180 then
    drawScene()
    drawStatus("invalid longitude", C_BAD)
    return false
  end

  lat = la
  lon = lo
  saveLocation(lat, lon)
  drawScene()
  drawStatus("location saved", C_GOOD)
  return true
end

local function fetchWeather()
  if wifi.status() ~= "connected" then return nil, "no wifi" end
  if lat == nil or lon == nil then return nil, "no location" end
  local url = string.format(URL_FMT, tostring(lat), tostring(lon))
  local body, code = http.get(url)
  if code ~= 200 then return nil, string.format("HTTP %d", code) end
  local data = json.decode(body)
  if (not data) or (not data.current) or (not data.daily) then
    return nil, "parse error"
  end
  local hi, lo
  if type(data.daily.temperature_2m_max) == "table" then hi = data.daily.temperature_2m_max[1] end
  if type(data.daily.temperature_2m_min) == "table" then lo = data.daily.temperature_2m_min[1] end
  return {
    temp = data.current.temperature_2m,
    code = data.current.weather_code,
    wind = data.current.wind_speed_10m,
    rh   = data.current.relative_humidity_2m,
    hi   = hi,
    lo   = lo,
  }, nil
end

local function refresh()
  drawStatus("fetching...", C_DIM)
  local w, err = fetchWeather()
  drawHUD()
  if err then
    cur_temp, cur_code, cur_wind, cur_rh, hi_temp, lo_temp = nil, nil, nil, nil, nil, nil
    error_active = true
    drawValues()
    drawStatus("error: " .. err, C_BAD)
    uni.beep(220, 120)
    return
  end
  cur_temp = w.temp
  cur_code = w.code
  cur_wind = w.wind
  cur_rh   = w.rh
  hi_temp  = w.hi
  lo_temp  = w.lo
  last_fetch_ms  = uni.millis()
  error_active   = false
  last_remaining = -1
  drawValues()
  drawStatus("updated", C_GOOD)
  uni.beep(1300, 40)
end

-- ── Init ──────────────────────────────────────────────────
lat, lon = loadLocation()
drawScene()

if lat == nil then
  drawStatus("press DOWN to set location", C_DIM)
elseif ensureWifi() then
  refresh()
else
  error_active = true
  drawStatus("press OK to connect wifi", C_BAD)
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "down" then
    if promptLocation() then
      if ensureWifi() then refresh() end
    end
  elseif btn == "ok" then
    if lat == nil then
      if promptLocation() then
        if ensureWifi() then refresh() end
      end
    elseif wifi.status() ~= "connected" then
      if ensureWifi() then refresh() end
    else
      refresh()
    end
  end

  if (not error_active) and cur_temp ~= nil then
    local elapsed = uni.millis() - last_fetch_ms
    if elapsed >= REFRESH_MS then
      refresh()
    else
      local remaining = math.floor((REFRESH_MS - elapsed) / 1000)
      if remaining ~= last_remaining then
        if remaining >= 60 then
          drawStatus(string.format("refresh in %dm", math.floor(remaining / 60)), C_DIM)
        else
          drawStatus(string.format("refresh in %ds", remaining), C_DIM)
        end
        last_remaining = remaining
      end
    end
  end

  uni.delay(200)
end
