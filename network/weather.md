# Weather

Uses the open-meteo API (no key required). On first run the script prompts for a latitude and longitude and saves them to /unigeek/network/weather.txt; pressing DOWN at any time re-enters the location, OK forces a refresh.

WiFi follows the same convention as crypto-price.lua: passwords are looked up in /unigeek/wifi/passwords/<BSSID>_<SSID>.pass (the format the eapol bruteforce uses to save cracked passwords). If no stored password is found, the script prompts.

## Controls

| Button | Action |
|--------|--------|
| OK | refresh now / retry on error / start the WiFi prompt |
| DOWN | re-enter latitude / longitude |
| BACK | exit (also dismisses any prompt) |
