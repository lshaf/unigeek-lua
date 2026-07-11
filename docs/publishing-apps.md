# Publishing apps

How a `.lua` script in this repo becomes an installable app — both **on the device**
(Download → Lua Scripts) and **on the website App Store**. If you just want to write a
good script, start with [CONTRIBUTING.md](../CONTRIBUTING.md) and
[lua-runner.md](lua-runner.md); this page is about **metadata and distribution**.

## How it all fits together

One file — the script's `.lua` — feeds two independent channels. Nothing here needs a
server or a database; both channels read plain files straight from this GitHub repo.

```
              your-app.lua  (+ optional your-app.md, images)
                     │
        add its path │ to map.txt
                     ▼
        ┌──────────── map.txt (flat list of every .lua path) ────────────┐
        │                                                                │
        ▼                                                                ▼
  FIRMWARE                                                          WEBSITE
  Download → Lua Scripts                                    tools/build-catalog.mjs
  reads map.txt, browses                                   reads map.txt + each .lua
  the tree, downloads the                                  header → generates apps.json
  .lua to the SD card                                                   │
                                                                        ▼
                                                          App Store page fetches
                                                          apps.json at runtime and
                                                          installs over USB/BLE
```

- **`map.txt`** is the single source of truth for *which apps exist*. Both the firmware
  and the catalog generator read it. If you add a script but forget `map.txt`, it shows
  up in neither place.
- **`apps.json`** is *generated* — never hand-edited. The metadata in it comes from a
  comment header at the top of each `.lua`.

---

## 1. Add a new app

1. **Drop the `.lua`** in the right category folder. The path here mirrors the SD-card
   path: `network/weather.lua` → `/unigeek/lua/network/weather.lua`. File names are
   lowercase, hyphen-separated (`base-converter.lua`). See
   [CONTRIBUTING.md](../CONTRIBUTING.md#folder-layout) for the category list.
2. **Add a metadata header** at the very top of the `.lua` (see §2).
3. *(Optional)* Add a **`.md` doc + images** next to it for a rich App Store page (§3).
4. **Register it in `map.txt`** — add the repo-relative path on its own line, keep the
   list sorted.
5. **Regenerate `apps.json`** — `node tools/build-catalog.mjs` (or let the worker do it on
   push, §4).
6. Update **[SCRIPTS.md](../SCRIPTS.md)** with a human-readable row (see CONTRIBUTING).

---

## 2. Metadata standard — the header block

Put a comment block at the **very top** of the `.lua` (it's the first thing the generator
reads, and Lua ignores it). Use the `--[[ … ]]` block form:

```lua
--[[
@title Weather
@description Current conditions plus today's high and low, over WiFi.
@category Network
@author lshaf
]]

-- weather.lua — the rest of your normal file comments can follow…
local lcd = require("uni.lcd")
```

| Tag | Required | What it does |
|-----|----------|--------------|
| `@title` | recommended | The display name in the list, on the card, and in the modal. |
| `@description` | recommended | One sentence shown on the card and at the top of the detail modal. Keep it to a single line. |
| `@category` | optional | Groups the app and drives the filter chips. |
| `@author` | optional | Shown as “by …” on the card and modal. |

### Fallbacks (why legacy scripts still look fine)

Every field degrades gracefully, so a script with **no header at all** still gets a decent
entry:

| Field | If the tag is missing… |
|-------|------------------------|
| title | Derived from the filename: `hacker-news.lua` → **Hacker News** (strip extension, `-`/`_` → spaces, Title Case). This is the *same* rule the firmware uses on-device. |
| description | The text after the first ` — ` / ` - ` on the first comment line. This is often truncated mid-sentence, so **prefer an explicit `@description`.** |
| category | The Title-Cased top folder: `network/…` → **Network**. |

> Titles and descriptions are plain text — **no emoji**. The App Store deliberately does
> not render icons.

---

## 3. Rich description + images (optional)

For screenshots and a longer write-up, add a **`.md` file with the same basename** next to
the `.lua`:

```
network/weather.lua
network/weather.md          ← rendered in the App Store detail modal
network/img/weather.png     ← referenced by the .md
```

- The `.md` is rendered as Markdown in the modal (headings, tables, code, images).
- **Images use relative paths** and are resolved against the `.md`'s folder. Keep assets
  in a sibling folder (e.g. `network/img/…`) and reference them relatively:
  `![Weather](img/weather.png)`. Absolute `https://` URLs are left as-is.

### Which image becomes the card cover?

The generator picks the cover in this order:

1. The **first image** referenced in the app's `.md` (`![...](...)`).
2. Otherwise, a sibling image file named after the script:
   `weather.png` / `.jpg` / `.jpeg` / `.gif` / `.webp` next to `weather.lua`.
3. Otherwise, no cover — the card shows a striped placeholder with the category label.

Recommended cover aspect is roughly **16:9** (cards render that way); the modal shows the
full image un-cropped.

---

## 4. Updating the website — the catalog worker

The website's App Store **does not read your `.lua` files directly** — it fetches a single
generated index, `apps.json`, from this repo at runtime. So "updating the site" means
"regenerating `apps.json`". There are two ways:

### Locally
```bash
node tools/build-catalog.mjs          # writes apps.json
node tools/build-catalog.mjs --check  # CI guard: fails if apps.json is stale
```
Commit the regenerated `apps.json` along with your app.

### Automatically — the worker (GitHub Action)
[`tools/catalog.workflow.yml`](../tools/catalog.workflow.yml) is a GitHub Actions workflow
that runs the generator on every push touching a `.lua`, `map.txt`, or the generator
itself, and commits the refreshed `apps.json` back. That's the "worker" that keeps the
catalog in sync with zero manual steps.

To enable it, move it into place:
```
tools/catalog.workflow.yml  →  .github/workflows/catalog.yml
```
> It ships parked under `tools/` because pushing a file into `.github/workflows/` requires
> a token with the **`workflow`** scope. Move it via the GitHub web UI, or push it with a
> PAT that has `workflow` enabled.

### How the change reaches users

Once `apps.json` is updated on `main`, the App Store page picks it up **on the next
load** — no site rebuild or deploy. The site reads
`https://raw.githubusercontent.com/<owner>/<repo>/main/apps.json` (configured by
`APPS_REPO` on the website). GitHub's raw CDN may cache for a minute or two, so allow a
short delay before a new app appears.

There is **no separate backend or proxy** for the App Store — the browser talks to GitHub
raw directly (which sends permissive CORS) and installs over USB/BLE straight to the SD.

---

## 5. `map.txt` and on-device Download

`map.txt` at the repo root is a flat, sorted list of every script path, one per line:

```
network/weather.lua
utility/base-converter.lua
utility/morse/generator.lua
```

The firmware's **Download → Lua Scripts** screen fetches this file once, presents the repo
as a browsable folder tree, and downloads the picked `.lua` straight to
`/unigeek/lua/<path>` on the SD card — no App Store, no computer needed. The catalog
generator reads the same `map.txt` to know which scripts to index.

Because both channels depend on it, **adding your path to `map.txt` is the one step you
cannot skip.**

---

## Checklist for a new app

- [ ] `.lua` in the correct category folder, lowercase-hyphen filename
- [ ] Header block with `@title` + `@description` (and `@category`, `@author` if useful)
- [ ] *(optional)* `.md` doc + images in a sibling folder, referenced relatively
- [ ] Path added to `map.txt` (sorted)
- [ ] `apps.json` regenerated (`node tools/build-catalog.mjs`) or left to the worker
- [ ] Row added to `SCRIPTS.md`
- [ ] Tested on-device per [CONTRIBUTING.md](../CONTRIBUTING.md)
