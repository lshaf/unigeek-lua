--[[
@title Magic 8-Ball
@description Ask a question, shake the ball, and get a classic Magic 8-Ball answer.
@category Utility
@author lshaf
]]
-- magic-8ball.lua — Magic 8-Ball
-- Ask a question in your head, press OK to shake the ball, and one of
-- the 20 classic answers is revealed. Tinted green/yellow/red by tone.
--
--   OK   : shake / ask another
--   BACK : exit

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color(  8,  10,  30)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_BALL     = lcd.color( 18,  18,  28)
local C_HIGHL    = lcd.color( 80,  80, 110)
local C_WINDOW   = lcd.color(230, 230, 240)
local C_8        = lcd.color( 18,  18,  28)
local C_GOOD     = lcd.color(120, 230, 130)
local C_NEUT     = lcd.color(255, 200,  60)
local C_BAD      = lcd.color(255, 130, 130)

local ANSWERS = {
  -- Positive (10)
  { text = "It is certain",        kind = "good" },
  { text = "Without a doubt",      kind = "good" },
  { text = "Yes definitely",       kind = "good" },
  { text = "You may rely on it",   kind = "good" },
  { text = "As I see it, yes",     kind = "good" },
  { text = "Most likely",          kind = "good" },
  { text = "Outlook good",         kind = "good" },
  { text = "Yes",                  kind = "good" },
  { text = "Signs point to yes",   kind = "good" },
  { text = "It is decidedly so",   kind = "good" },
  -- Neutral (5)
  { text = "Reply hazy try again", kind = "neutral" },
  { text = "Ask again later",      kind = "neutral" },
  { text = "Better not say now",   kind = "neutral" },
  { text = "Cannot predict now",   kind = "neutral" },
  { text = "Concentrate and ask",  kind = "neutral" },
  -- Negative (5)
  { text = "Don't count on it",    kind = "bad" },
  { text = "My reply is no",       kind = "bad" },
  { text = "My sources say no",    kind = "bad" },
  { text = "Outlook not so good",  kind = "bad" },
  { text = "Very doubtful",        kind = "bad" },
}

-- ── Layout ────────────────────────────────────────────────
local HUD_H        = 12
local BALL_R       = math.min(34, math.max(20, math.floor(H * 0.22)))
local BALL_CX      = math.floor(W / 2)
local BALL_CY      = HUD_H + BALL_R + 6
local ANSWER_Y     = BALL_CY + BALL_R + 10
local ANSWER_H     = 30
local HINT_Y       = H - 12
local SHAKE_FRAMES = 18
local SHAKE_OFFSET = 4

-- ── State ─────────────────────────────────────────────────
local game_state    = "idle"   -- "idle" | "shaking" | "answered"
local shake_count   = 0
local last_offset   = 0
local current_ans   = nil
local count_total   = 0
local last_hint     = ""

math.randomseed(uni.millis())

-- ── Helpers ───────────────────────────────────────────────
local function kindColor(k)
  if k == "good"    then return C_GOOD end
  if k == "neutral" then return C_NEUT end
  return C_BAD
end

local function drawBall(offset)
  local cx = BALL_CX + offset
  local cy = BALL_CY
  lcd.fillCircle(cx, cy, BALL_R, C_BALL)
  lcd.fillCircle(cx - math.floor(BALL_R * 0.4),
                 cy - math.floor(BALL_R * 0.4),
                 math.max(2, math.floor(BALL_R * 0.18)), C_HIGHL)
  local win_r = math.max(8, math.floor(BALL_R * 0.45))
  lcd.fillCircle(cx, cy + math.floor(BALL_R * 0.05), win_r, C_WINDOW)
  lcd.textSize(2)
  lcd.textColor(C_8, C_WINDOW)
  local tw = lcd.textWidth("8")
  lcd.print(cx - math.floor(tw / 2), cy - 6, "8")
  lcd.textSize(1)
end

local function eraseBallSpan()
  local r = BALL_R + SHAKE_OFFSET + 3
  lcd.rect(BALL_CX - r, BALL_CY - BALL_R - 2, r * 2, (BALL_R + 2) * 2 + 4, C_BG)
end

local function drawAnswer(answer)
  lcd.rect(0, ANSWER_Y, W, ANSWER_H, C_BG)
  if answer == nil then return end
  lcd.textSize(1)
  lcd.textColor(kindColor(answer.kind), C_BG)
  local words = {}
  for w in string.gmatch(answer.text, "%S+") do words[#words + 1] = w end
  local lines = {""}
  for i = 1, #words do
    local trial = (lines[#lines] == "") and words[i] or (lines[#lines] .. " " .. words[i])
    if lcd.textWidth(trial) <= W - 8 then
      lines[#lines] = trial
    else
      lines[#lines + 1] = words[i]
    end
  end
  for i = 1, #lines do
    local lw = lcd.textWidth(lines[i])
    lcd.print(math.floor((W - lw) / 2), ANSWER_Y + (i - 1) * 10, lines[i])
  end
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Magic 8-Ball")
  if count_total > 0 then
    local s = string.format("asked %d", count_total)
    lcd.textColor(C_DIM, C_HUD_BG)
    local sw = lcd.textWidth(s)
    lcd.print(W - sw - 2, 2, s)
  end
end

local function drawHints()
  local s
  if game_state == "idle" then
    s = "ask, then OK   BACK to exit"
  elseif game_state == "answered" then
    s = "OK ask another   BACK exit"
  else
    s = "shaking..."
  end
  if s == last_hint then return end
  last_hint = s
  lcd.textSize(1)
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textColor(C_DIM, C_BG)
  if lcd.textWidth(s) > W then s = "OK ask   BACK exit" end
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), HINT_Y, s)
end

-- ── Init ──────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawHUD()
drawBall(0)
drawAnswer(nil)
drawHints()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if (game_state == "idle" or game_state == "answered") and btn == "ok" then
    game_state  = "shaking"
    shake_count = 0
    last_offset = 0
    drawAnswer(nil)
    drawHints()
  end

  if game_state == "shaking" then
    shake_count = shake_count + 1
    local offset = ((shake_count % 4) < 2) and SHAKE_OFFSET or -SHAKE_OFFSET
    if offset ~= last_offset then
      eraseBallSpan()
      drawBall(offset)
      last_offset = offset
      uni.beep(180 + shake_count * 12, 28)
    end
    if shake_count >= SHAKE_FRAMES then
      eraseBallSpan()
      drawBall(0)
      last_offset  = 0
      current_ans  = ANSWERS[math.random(1, #ANSWERS)]
      count_total  = count_total + 1
      game_state   = "answered"
      drawAnswer(current_ans)
      drawHUD()
      drawHints()
      uni.beep(900, 60)
      uni.delay(80)
      uni.beep(1300, 90)
    end
  end

  uni.delay(33)
end
