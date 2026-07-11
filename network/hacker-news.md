# Hacker News

Read the front page of [Hacker News](https://news.ycombinator.com) straight from your
UniGeek. The app pulls the current top-stories list over WiFi and lets you scroll through
the ten highest-ranked items, showing score, comment count, and author for each.

## Controls

| Button | Action |
|--------|--------|
| UP / DOWN | Move the cursor through the list (wraps around) |
| OK | Refresh now / retry after an error / start the WiFi prompt |
| BACK | Exit (also dismisses any prompt) |

## WiFi

Credentials follow the standard convention: stored passwords live in
`/unigeek/wifi/passwords/<BSSID>_<SSID>.pass`. If none is found, the app prompts you on the
first connect attempt. The list auto-refreshes every 10 minutes.
