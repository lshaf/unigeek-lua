#!/usr/bin/env node
// Generates apps.json from the .lua scripts listed in map.txt.
//
// Metadata for each app comes from a header comment at the top of its .lua,
// with graceful fallbacks so legacy scripts need no changes:
//
//   1. Structured tags anywhere in the first comment block:
//        --[[
//        @title Hacker News
//        @description Top stories from Hacker News
//        @category Web
//        @author lshaf
//        ]]
//      (line comments work too: `-- @title Hacker News`)
//   2. The legacy first line `-- <file> — <text>` supplies a description.
//   3. Title falls back to the prettified filename (hacker-news → Hacker News),
//      the same algorithm the firmware uses for its on-device list.
//   4. Category falls back to the top-level folder, Title-Cased.
//
// A sibling "<name>.md" (same folder, same basename) is recorded as `doc`.
//
// Usage:  node tools/build-catalog.mjs            # writes apps.json
//         node tools/build-catalog.mjs --check    # fails if apps.json is stale

import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'apps.json');

// hacker-news.lua -> "Hacker News". Keep in sync with the firmware's
// BrowseFileView::prettifyTitle so titles match on device and site.
function prettify(filename) {
  const base = filename.replace(/\.[^.]*$/, '');       // strip last extension
  return base
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

// Collect the leading comment block (a run of `--` lines and/or a --[[ ]] block)
// from the top of the file, as plain text lines with the comment markers stripped.
function headerLines(src) {
  const lines = src.split(/\r?\n/);
  const out = [];
  let inBlock = false;
  for (const raw of lines) {
    const line = raw.trim();
    if (inBlock) {
      if (line.includes(']]')) { out.push(line.replace(/\]\]/, '').trim()); break; }
      out.push(line);
      continue;
    }
    if (line.startsWith('--[[')) { inBlock = true; out.push(line.replace('--[[', '').trim()); continue; }
    if (line.startsWith('--')) { out.push(line.replace(/^--+/, '').trim()); continue; }
    if (line === '') { if (out.length) break; else continue; }
    break; // first non-comment, non-blank line ends the header
  }
  return out;
}

function parseTags(lines) {
  const tags = {};
  for (const line of lines) {
    const m = line.match(/^@(\w+)\s+(.+)$/);
    if (m) tags[m[1].toLowerCase()] = m[2].trim();
  }
  return tags;
}

// Legacy first line: "hacker-news.lua — Top 10 stories" -> "Top 10 stories".
function legacyDescription(lines) {
  const first = lines[0] || '';
  const m = first.split(/\s[—–-]\s/); // em/en dash or hyphen surrounded by spaces
  if (m.length >= 2) return m.slice(1).join(' - ').trim();
  return '';
}

const IMAGE_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp'];

// Cover image for an app: the first image referenced by its .md, else a sibling
// "<name>.<ext>" next to the .lua. Returns a repo-relative path (or absolute URL).
function firstMdImage(mdRel) {
  const abs = join(ROOT, mdRel);
  if (!existsSync(abs)) return null;
  const md = readFileSync(abs, 'utf8');
  const m = md.match(/!\[[^\]]*\]\(\s*([^)\s]+)/);
  if (!m) return null;
  let src = m[1];
  if (/^https?:\/\//i.test(src) || src.startsWith('data:')) return src;
  if (src.startsWith('/')) return src.slice(1);
  const dir = mdRel.includes('/') ? mdRel.slice(0, mdRel.lastIndexOf('/')) : '';
  return dir ? `${dir}/${src}` : src;
}

function siblingImage(relPath) {
  const baseNoExt = relPath.replace(/\.lua$/, '');
  for (const e of IMAGE_EXT) {
    if (existsSync(join(ROOT, `${baseNoExt}.${e}`))) return `${baseNoExt}.${e}`;
  }
  return null;
}

function listPaths() {
  const mapPath = join(ROOT, 'map.txt');
  if (existsSync(mapPath)) {
    return readFileSync(mapPath, 'utf8')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#') && l.endsWith('.lua'));
  }
  // Fallback: recursive glob for *.lua
  const acc = [];
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir)) {
      if (name.startsWith('.')) continue;
      const abs = join(dir, name);
      const r = rel ? `${rel}/${name}` : name;
      if (statSync(abs).isDirectory()) walk(abs, r);
      else if (name.endsWith('.lua')) acc.push(r);
    }
  };
  walk(ROOT, '');
  return acc.sort();
}

function buildApp(relPath) {
  const abs = join(ROOT, relPath);
  const src = readFileSync(abs, 'utf8');
  const lines = headerLines(src);
  const tags = parseTags(lines);

  const fileName = relPath.split('/').pop();
  const topFolder = relPath.includes('/') ? relPath.split('/')[0] : '';

  const app = {
    path: relPath,
    title: tags.title || prettify(fileName),
    description: tags.description || legacyDescription(lines) || '',
    category: tags.category || (topFolder ? prettify(topFolder) : 'Misc'),
  };
  if (tags.author) app.author = tags.author;

  const mdPath = relPath.replace(/\.lua$/, '.md');
  if (existsSync(join(ROOT, mdPath))) app.doc = mdPath;

  const image = (app.doc ? firstMdImage(app.doc) : null) || siblingImage(relPath);
  if (image) app.image = image;

  return app;
}

const apps = listPaths().map(buildApp);
const catalog = {
  version: 1,
  generatedAt: new Date().toISOString(),
  count: apps.length,
  apps,
};
const json = JSON.stringify(catalog, null, 2) + '\n';

if (process.argv.includes('--check')) {
  const current = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
  // Ignore generatedAt when comparing so a no-op run doesn't flag as stale.
  const strip = (s) => s.replace(/"generatedAt":\s*"[^"]*",?\n?/, '');
  if (strip(current) !== strip(json)) {
    console.error('apps.json is stale — run: node tools/build-catalog.mjs');
    process.exit(1);
  }
  console.log(`apps.json up to date (${apps.length} apps)`);
} else {
  writeFileSync(OUT, json);
  console.log(`Wrote ${OUT} (${apps.length} apps)`);
}
