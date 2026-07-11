# Crypto Price Tracker

Fetches BTC/USD and ETH/USD from the CoinGecko public API every 60 s and displays them. If WiFi isn't already up, the script prompts for an SSID and password, then connects.

Password lookup follows the firmware's WifiUtility convention: passwords live in /unigeek/wifi/passwords/<BSSID>_<SSID>.pass (the format the eapol bruteforce uses to save cracked passwords). On lookup we scan that directory for any file ending in `_<SSID>.pass`, so cracked, firmware-saved, and manually-placed entries all work. We do NOT save passwords back from Lua — `uni.wifi` has no scan, so we can't fill in the BSSID half of the filename and would diverge from the firmware's format. Drop a file there yourself if you want auto-fill.

## Controls

| Button | Action |
|--------|--------|
| OK | refresh now / retry on error / start the connect prompt |

         when no wifi yet

## Controls

| Button | Action |
|--------|--------|
| BACK | exit (also dismisses any prompt) |
