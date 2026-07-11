# ISS Tracker

Polls wheretheiss.at every 5 s and shows the station's latitude / longitude, altitude (km), velocity (km/h) and whether it's currently in daylight or eclipse. A small bordered world-rectangle plots the station's position as a moving dot so you can see it sweep around.

WiFi follows the same convention as crypto-price.lua: passwords are read from /unigeek/wifi/passwords/<BSSID>_<SSID>.pass. If no stored password is found, the script prompts on the first connect attempt.

## Controls

| Button | Action |
|--------|--------|
| OK | refresh now / retry on error / start the WiFi prompt |
| BACK | exit (also dismisses any prompt) |
