-- simon.lua — Simon (memory game)
-- The device plays a growing sequence of beeps on three coloured
-- lanes. Repeat it back; survive as many rounds as you can.
--
--   UP   : red lane    (top)
--   OK   : blue lane   (middle)
--   DOWN : green lane  (bottom)
--   BACK : exit (also dismisses Game Over)
--
-- Each successful round adds one new step. Best round persists to
-- /unigeek/games/simon.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color( 10,  10,  30)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_HUD_LINE = lcd.color( 60,  60,  90)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_HI       = lcd.color(255, 200,  60)
local C_BAD      = lcd.color(255, 110, 110)

local SAVE_PATH = "/unigeek/games/simon.txt"

local LANES = {
  { label = "UP",   button = "up",   freq = 440,
    on  = lcd.color(255,  90,  90),
    off = lcd.color( 90,  30,  30) },
  { label = "OK",   button = "ok",   freq = 660,
    on  = lcd.color( 90, 150, 255),
    off = lcd.color( 30,  50,  90) },
  { label = "DOWN", button = "down", freq = 880,
    on  = lcd.color( 90, 220, 120),
    off = lcd.color( 30,  80,  40) },
}

-- ── Layout ────────────────────────────────────────────────
local HUD_H        = 12
local LANE_MARGIN  = math.max(8, math.floor(W * 0.08))
local LANE_GAP     = 4
local LANE_AREA_T  = HUD_H + 6
local LANE_AREA_B  = H - 14
local LANE_H       = math.floor((LANE_AREA_B - LANE_AREA_T - 2 * LANE_GAP) / 3)
local LANE_W       = W - 2 * LANE_MARGIN
local LANE_Y = {
  LANE_AREA_T,
  LANE_AREA_T + LANE_H + LANE_GAP,
  LANE_AREA_T + 2 * (LANE_H + LANE_GAP),
}
local HINT_Y       = H - 12

local PLAYBACK_LIT_MS  = 350
local PLAYBACK_GAP_MS  = 200
local INPUT_FB_MS      = 180
local NEXT_ROUND_MS    = 450
local FRAME_MS         = 33
local PLAYBACK_LIT_F   = math.ceil(PLAYBACK_LIT_MS / FRAME_MS)
local PLAYBACK_GAP_F   = math.ceil(PLAYBACK_GAP_MS / FRAME_MS)

-- ── State ─────────────────────────────────────────────────
local seq                  -- array of 1/2/3
local score                -- completed rounds (starts at 0)
local highScore
local game_state           -- "showing" | "input" | "over"
local playback_idx, playback_phase, playback_timer
local input_idx
local popup_drawn
local last_score_shown

math.randomseed(uni.millis())

-- ── Helpers ───────────────────────────────────────────────
local function loadHigh()
  if not sd.exists(SAVE_PATH) then return 0 end
  return tonumber(sd.read(SAVE_PATH) or "") or 0
end

local function saveHigh(n)
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(n))
end

local function drawLane(idx, lit)
  local L = LANES[idx]
  local y = LANE_Y[idx]
  local color = lit and L.on or L.off
  lcd.fillRoundRect(LANE_MARGIN, y, LANE_W, LANE_H, 4, color)
  lcd.textColor(C_TEXT, color)
  lcd.textSize(1)
  lcd.print(LANE_MARGIN + 6, y + math.floor(LANE_H / 2) - 4, L.label)
end

local function drawAllLanesOff()
  for i = 1, 3 do drawLane(i, false) end
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LINE)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, string.format("ROUND %-3d", score + 1))
  local hi = string.format("BEST %-3d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hw = lcd.textWidth(hi)
  lcd.print(W - hw - 2, 2, hi)
end

local function drawHints(text)
  lcd.textSize(1)
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textColor(C_DIM, C_BG)
  if lcd.textWidth(text) > W then text = "BACK exit" end
  local w = lcd.textWidth(text)
  lcd.print(math.floor((W - w) / 2), HINT_Y, text)
end

local function drawPopup()
  local boxW = math.min(W - 16, 200)
  local boxH = 72
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.rect(bx, by, boxW, boxH, C_HUD_BG)
  lcd.rect(bx, by, boxW, 1, C_DIM)
  lcd.rect(bx, by + boxH - 1, boxW, 1, C_DIM)
  lcd.rect(bx, by, 1, boxH, C_DIM)
  lcd.rect(bx + boxW - 1, by, 1, boxH, C_DIM)
  lcd.textSize(2)
  lcd.textColor(C_BAD, C_HUD_BG)
  local title = "GAME OVER"
  local tw = lcd.textWidth(title)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 8, title)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local s = string.format("Rounds: %d", score)
  local sw = lcd.textWidth(s)
  lcd.print(bx + math.floor((boxW - sw) / 2), by + 32, s)
  local hi = string.format("Best: %d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hiw = lcd.textWidth(hi)
  lcd.print(bx + math.floor((boxW - hiw) / 2), by + 44, hi)
  lcd.textColor(C_DIM, C_HUD_BG)
  local hint = "OK: again   BACK: exit"
  local hw = lcd.textWidth(hint)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 14, hint)
end

local function buttonToLane(btn)
  if btn == "up"   then return 1 end
  if btn == "ok"   then return 2 end
  if btn == "down" then return 3 end
  return nil
end

local function resetGame()
  seq              = { math.random(1, 3) }
  score            = 0
  game_state       = "showing"
  playback_idx     = 1
  playback_phase   = "lit"
  playback_timer   = 0
  input_idx        = 1
  popup_drawn      = false
  last_score_shown = -1
end

local function clearScene()
  lcd.fillScreen(C_BG)
  drawHUD()
  drawAllLanesOff()
end

-- ── Init ──────────────────────────────────────────────────
highScore = loadHigh()
resetGame()
clearScene()
drawHints("watch carefully...")

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if score ~= last_score_shown then
    drawHUD()
    last_score_shown = score
  end

  if game_state == "showing" then
    if playback_phase == "lit" then
      if playback_timer == 0 then
        drawLane(seq[playback_idx], true)
        uni.beep(LANES[seq[playback_idx]].freq, PLAYBACK_LIT_MS)
      end
      playback_timer = playback_timer + 1
      if playback_timer >= PLAYBACK_LIT_F then
        drawLane(seq[playback_idx], false)
        playback_phase = "gap"
        playback_timer = 0
      end
    else
      playback_timer = playback_timer + 1
      if playback_timer >= PLAYBACK_GAP_F then
        playback_idx = playback_idx + 1
        if playback_idx > #seq then
          game_state     = "input"
          input_idx      = 1
          playback_idx   = 1
          playback_phase = "lit"
          playback_timer = 0
          drawHints("your turn")
        else
          playback_phase = "lit"
          playback_timer = 0
        end
      end
    end

  elseif game_state == "input" then
    local lane = buttonToLane(btn)
    if lane ~= nil then
      drawLane(lane, true)
      uni.beep(LANES[lane].freq, 100)
      uni.delay(INPUT_FB_MS)
      drawLane(lane, false)

      if lane == seq[input_idx] then
        input_idx = input_idx + 1
        if input_idx > #seq then
          score = score + 1
          seq[#seq + 1] = math.random(1, 3)
          game_state     = "showing"
          playback_idx   = 1
          playback_phase = "lit"
          playback_timer = 0
          drawHUD()
          last_score_shown = score
          drawHints("nice — next round")
          uni.delay(NEXT_ROUND_MS)
        end
      else
        game_state = "over"
        if score > highScore then
          highScore = score
          saveHigh(highScore)
        end
        uni.beep(150, 250)
        uni.delay(280)
        uni.beep(110, 250)
      end
    end

  else
    if not popup_drawn then
      drawHUD()
      last_score_shown = score
      drawPopup()
      popup_drawn = true
    end
    if btn == "ok" then
      resetGame()
      clearScene()
      drawHints("watch carefully...")
    end
  end

  uni.delay(FRAME_MS)
end
