-- Loads Vape with this fork's BlockWars module instead of the upstream one.
--
-- Upstream's NewMainScript pulls compiled per-game files from VapeCompiled,
-- which this fork cannot write to. But main.lua:94 reads
-- newvape/games/<PlaceId>.lua straight off disk when it exists and skips the
-- download, so dropping our bundle there shadows upstream's copy.
--
-- The bundle is refetched every run, so it always matches the repo. It also
-- survives vape updates: wipeFolder only deletes files whose first line is
-- upstream's cache watermark, and the bundle starts with a plain comment.

local BUNDLES = {
	[132768098780837] = 'https://raw.githubusercontent.com/fxr-lmao/fxr.exe/main/dist/132768098780837.lua'
}
local UPSTREAM = 'https://raw.githubusercontent.com/7GrandDadPGN/VapeV4ForRoblox/main/NewMainScript.lua'

local function fetch(url)
	local ok, res = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and res and #res > 0 and res ~= '404: Not Found' then
		return res
	end
	return nil
end

local bundle = BUNDLES[game.PlaceId]
if bundle then
	if not isfolder('newvape') then makefolder('newvape') end
	if not isfolder('newvape/games') then makefolder('newvape/games') end

	local source = fetch(bundle)
	if source then
		writefile('newvape/games/'..game.PlaceId..'.lua', source)
	else
		warn('[fxr] could not fetch the bundle, falling back to upstream for this game')
	end
end

local main = fetch(UPSTREAM)
if not main then
	error('[fxr] could not reach upstream NewMainScript')
end
loadstring(main)()
