# fxr.exe

A Roblox script for BlockWars, built on top of the CC0 Vape V4 runtime.

## Usage

Run this in your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fxr-lmao/fxr.exe/main/dist/loader.lua", true))()
```

Works on mobile executors too — nothing to install, the loader fetches
everything it needs each run.

## What is in here

| path | |
|---|---|
| `dist/loader.lua` | the loadstring above: installs the game module, applies fxr branding, then hands off to the runtime |
| `dist/132768098780837.lua` | the built BlockWars module |
| `dist/assets/` | branding assets, see below |
| `VapeV4ForRoblox/src/games/132768098780837 - blockwars/` | the BlockWars source |
| `VapeV4ForRoblox/tools/bundlegame.js` | builds a game folder into `dist/` |

Edit the source, not `dist/132768098780837.lua` — that file is rebuilt by
`.github/workflows/bundle.yml` whenever the game source changes.

## Logo

The header logo slot is 62x18 and the gui tints it to a flat colour, so it
suits a wordmark rather than artwork. With no logo file present the header
renders an `fxr` wordmark. Commit a png to `dist/assets/fxrlogo.png` and the
loader installs it and uses that instead.

## Credit

The underlying runtime is Vape V4 by [7GrandDad](https://github.com/7GrandDadPGN),
released under CC0. fxr is a fork of it.
