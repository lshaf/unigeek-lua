-- mastermind.lua — Mastermind (code-breaker)
-- The device picks a secret 4-digit code where each digit is 1..6.
-- Enter your guesses one digit at a time; after each full guess the
-- feedback pegs tell you how close you are:
--   ● filled red peg = right digit in the right position
--   ○ outlined peg   = right digit in the wrong position
-- 10 attempts to crack it. Best (lowest-attempt) win is saved.
--
--   UP   : cycle digit at cursor up   (1 -> 2 -> .. -> 6 -> 1)
--   DOWN : cycle digit at cursor down (1 -> 6 -> 5 -> .. -> 1)
--   OK   : confirm digit and advance (at position 4 = submit guess)
--   BACK : exit (also dismisses Game Over / You Win)

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG        = lcd.color( 10,  12,  28)
local C_HUD_BG    = lcd.color( 22,  22,  38)
local C_HUD_LINE  = lcd.color( 60,  60,  90)
local C_TEXT      = lcd.color(220, 220, 240)
local C_DIM       = lcd.color(140, 140, 180)
local C_HI        = lcd.color(255, 200,  60)
local C_GOOD      = lcd.color(120, 230, 130)
local C_BAD       = lcd.color(255, 110, 110)
local C_CURSOR    = lcd.color(255, 220,  60)
local C_PEG_EXACT = lcd.color(255,  80,  80)
local C_PEG_PART  = lcd.color(220, 220, 240)

local DIGIT_COLORS = {
  lcd.color(255, 110, 110),  -- 1 red
  lcd.color(255, 170,  60),  -- 2 orange
  lcd.color(255, 220,  80),  -- 3 yellow
  lcd.color(120, 220, 120),  -- 4 green
  lcd.color( 90, 150, 240),  -- 5 blue
  lcd.color(200, 120, 240),  -- 6 purple
}

-- ── Constants ─────────────────────────────────────────────
local CODE_LEN     = 4
local DIGITS       = 6
local MAX_ATTEMPTS = 10
local SAVE_PATH    = "/unigeek/games/mastermind.txt"

local BOX_W    = 12
local BOX_H    = 10
local BOX_GAP  = 1
local PEG_R    = 2
local PEG_GAP  = 1
local ROW_H    = 12

-- ── Layout ────────────────────────────────────────────────
local HUD_H        = 12
local ATTEMPTS_Y   = HUD_H + 4
local CURRENT_Y_GAP = 6
local HINT_Y       = H - 12
local CURRENT_AREA_H = BOX_H + 6
local MAX_VISIBLE_ROWS
do
  local available = HINT_Y - ATTEMPTS_Y - CURRENT_AREA_H - CURRENT_Y_GAP - 4
  MAX_VISIBLE_ROWS = math.max(3, math.min(MAX_ATTEMPTS, math.floor(available / ROW_H)))
end
local CURRENT_Y = ATTEMPTS_Y + MAX_VISIBLE_ROWS * ROW_H + CURRENT_Y_GAP

-- ── State (declared once) ─────────────────────────────────
local secret
local attempts
local current
local cursor_pos
local game_state         -- "playing" | "won" | "lost"
local best
local popup_drawn

math.randomseed(uni.millis())

-- ── Helpers ───────────────────────────────────────────────
local function loadBest()
  if not sd.exists(SAVE_PATH) then return nil end
  return tonumber(sd.read(SAVE_PATH) or "")
end

local function saveBest(n)
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(n))
end

local function generateSecret()
  secret = {}
  for i = 1, CODE_LEN do secret[i] = math.random(1, DIGITS) end
end

local function scoreGuess(guess)
  local black, white = 0, 0
  local used_s, used_g = { false, false, false, false }, { false, false, false, false }
  for i = 1, CODE_LEN do
    if guess[i] == secret[i] then
      black = black + 1
      used_s[i], used_g[i] = true, true
    end
  end
  for i = 1, CODE_LEN do
    if not used_g[i] then
      for j = 1, CODE_LEN do
        if (not used_s[j]) and guess[i] == secret[j] then
          white = white + 1
          used_s[j] = true
          break
        end
      end
    end
  end
  return black, white
end

local function drawDigitBox(x, y, digit, with_cursor)
  if digit == 0 then
    lcd.rect(x, y, BOX_W, BOX_H, C_BG)
    lcd.rect(x, y,          BOX_W, 1, C_DIM)
    lcd.rect(x, y + BOX_H - 1, BOX_W, 1, C_DIM)
    lcd.rect(x, y,          1, BOX_H, C_DIM)
    lcd.rect(x + BOX_W - 1, y, 1, BOX_H, C_DIM)
  else
    local fill = DIGIT_COLORS[digit]
    lcd.rect(x, y, BOX_W, BOX_H, fill)
    lcd.textSize(1)
    lcd.textColor(C_BG, fill)
    local s = tostring(digit)
    local sw = lcd.textWidth(s)
    lcd.print(x + math.floor((BOX_W - sw) / 2),
              y + math.floor((BOX_H - 8) / 2), s)
  end
  if with_cursor then
    lcd.rect(x - 1, y - 1,          BOX_W + 2, 1, C_CURSOR)
    lcd.rect(x - 1, y + BOX_H,      BOX_W + 2, 1, C_CURSOR)
    lcd.rect(x - 1, y - 1,          1, BOX_H + 2, C_CURSOR)
    lcd.rect(x + BOX_W, y - 1,      1, BOX_H + 2, C_CURSOR)
  end
end

local function drawPegs(x, y, black, white)
  local idx = 0
  for _ = 1, black do
    local cx = x + idx * (PEG_R * 2 + PEG_GAP) + PEG_R
    lcd.fillCircle(cx, y + PEG_R, PEG_R, C_PEG_EXACT)
    idx = idx + 1
  end
  for _ = 1, white do
    local cx = x + idx * (PEG_R * 2 + PEG_GAP) + PEG_R
    lcd.circle(cx, y + PEG_R, PEG_R, C_PEG_PART)
    idx = idx + 1
  end
end

-- Returns the X start where digit boxes begin (after "N:" label).
local function rowStartX()
  return 18
end

local function pegsX()
  return rowStartX() + CODE_LEN * (BOX_W + BOX_GAP) + 8
end

local function drawAttemptRow(y, idx, attempt)
  lcd.rect(0, y, W, ROW_H, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(2, y + 2, string.format("%2d:", idx))
  local x = rowStartX()
  for i = 1, CODE_LEN do
    drawDigitBox(x, y + 1, attempt.digits[i], false)
    x = x + BOX_W + BOX_GAP
  end
  drawPegs(pegsX(), y + math.floor((ROW_H - PEG_R * 2) / 2), attempt.black, attempt.white)
end

local function drawAttempts()
  lcd.rect(0, ATTEMPTS_Y, W, MAX_VISIBLE_ROWS * ROW_H, C_BG)
  local start_i = math.max(1, #attempts - MAX_VISIBLE_ROWS + 1)
  local out_i = 0
  for i = start_i, #attempts do
    drawAttemptRow(ATTEMPTS_Y + out_i * ROW_H, i, attempts[i])
    out_i = out_i + 1
  end
end

local function drawCurrentRow()
  local y = CURRENT_Y
  lcd.rect(0, y - 1, W, CURRENT_AREA_H, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(2, y + 2, "NOW")
  local x = rowStartX()
  for i = 1, CODE_LEN do
    drawDigitBox(x, y + 1, current[i], i == cursor_pos)
    x = x + BOX_W + BOX_GAP
  end
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LINE)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Mastermind")
  local mid = string.format("ATT %d/%d", #attempts, MAX_ATTEMPTS)
  lcd.textColor(C_DIM, C_HUD_BG)
  local mw = lcd.textWidth(mid)
  lcd.print(math.floor((W - mw) / 2), 2, mid)
  if best then
    local hi = string.format("HI %d", best)
    lcd.textColor(C_HI, C_HUD_BG)
    local hw = lcd.textWidth(hi)
    lcd.print(W - hw - 2, 2, hi)
  end
end

local function drawHint()
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local s = "UP/DN digit   OK confirm   BACK exit"
  if lcd.textWidth(s) > W then s = "UP/DN OK BACK" end
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, s)
end

local function drawSceneBackground()
  lcd.fillScreen(C_BG)
end

local function drawPopup()
  local boxW = math.min(W - 12, 220)
  local boxH = 92
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.rect(bx, by, boxW, boxH, C_HUD_BG)
  lcd.rect(bx, by, boxW, 1, C_DIM)
  lcd.rect(bx, by + boxH - 1, boxW, 1, C_DIM)
  lcd.rect(bx, by, 1, boxH, C_DIM)
  lcd.rect(bx + boxW - 1, by, 1, boxH, C_DIM)

  lcd.textSize(2)
  local title, color
  if game_state == "won" then title, color = "CRACKED!",  C_GOOD
  else                        title, color = "GAME OVER", C_BAD end
  lcd.textColor(color, C_HUD_BG)
  local tw = lcd.textWidth(title)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 8, title)

  -- Reveal the secret
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local label = "SECRET:"
  local lw = lcd.textWidth(label)
  local boxes_w = CODE_LEN * (BOX_W + BOX_GAP) - BOX_GAP
  local total_w = lw + 8 + boxes_w
  local row_x = bx + math.floor((boxW - total_w) / 2)
  lcd.print(row_x, by + 36, label)
  local sx = row_x + lw + 8
  for i = 1, CODE_LEN do
    drawDigitBox(sx + (i - 1) * (BOX_W + BOX_GAP), by + 32, secret[i], false)
  end

  lcd.textColor(C_DIM, C_HUD_BG)
  local s = string.format("Attempts: %d", #attempts)
  local sw = lcd.textWidth(s)
  lcd.print(bx + math.floor((boxW - sw) / 2), by + 54, s)

  if best then
    lcd.textColor(C_HI, C_HUD_BG)
    local bs = string.format("Best: %d", best)
    local bsw = lcd.textWidth(bs)
    lcd.print(bx + math.floor((boxW - bsw) / 2), by + 66, bs)
  end

  lcd.textColor(C_DIM, C_HUD_BG)
  local hint = "OK: again   BACK: exit"
  local hw = lcd.textWidth(hint)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 14, hint)
end

local function resetGame()
  generateSecret()
  attempts    = {}
  current     = { 1, 0, 0, 0 }
  cursor_pos  = 1
  game_state  = "playing"
  popup_drawn = false
end

local function submitGuess()
  local b, w = scoreGuess(current)
  attempts[#attempts + 1] = {
    digits = { current[1], current[2], current[3], current[4] },
    black  = b,
    white  = w,
  }
  if b == CODE_LEN then
    game_state = "won"
    if best == nil or #attempts < best then
      best = #attempts
      saveBest(best)
    end
    uni.beep(1300, 60); uni.delay(80); uni.beep(1700, 80)
  elseif #attempts >= MAX_ATTEMPTS then
    game_state = "lost"
    uni.beep(150, 250); uni.delay(280); uni.beep(110, 200)
  else
    current    = { 1, 0, 0, 0 }
    cursor_pos = 1
    uni.beep(900, 30)
  end
end

-- ── Init ──────────────────────────────────────────────────
best = loadBest()
resetGame()
drawSceneBackground()
drawHUD()
drawAttempts()
drawCurrentRow()
drawHint()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if game_state == "playing" then
    if btn == "up" then
      current[cursor_pos] = current[cursor_pos] + 1
      if current[cursor_pos] > DIGITS then current[cursor_pos] = 1 end
      drawCurrentRow()
      uni.beep(700, 16)
    elseif btn == "down" then
      current[cursor_pos] = current[cursor_pos] - 1
      if current[cursor_pos] < 1 then current[cursor_pos] = DIGITS end
      drawCurrentRow()
      uni.beep(500, 16)
    elseif btn == "ok" then
      if cursor_pos < CODE_LEN then
        cursor_pos = cursor_pos + 1
        if current[cursor_pos] == 0 then current[cursor_pos] = 1 end
        drawCurrentRow()
        uni.beep(950, 20)
      else
        submitGuess()
        drawAttempts()
        drawCurrentRow()
        drawHUD()
      end
    end
  else
    if not popup_drawn then
      drawPopup()
      popup_drawn = true
    end
    if btn == "ok" then
      resetGame()
      drawSceneBackground()
      drawHUD()
      drawAttempts()
      drawCurrentRow()
      drawHint()
    end
  end

  uni.delay(33)
end
