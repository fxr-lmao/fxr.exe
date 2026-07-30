-- Loads fxr: this fork's game modules plus fxr branding, on top of upstream's
-- runtime.
--
-- Upstream's NewMainScript pulls compiled files from VapeCompiled, which this
-- fork cannot write to. But main.lua:94 reads newvape/games/<PlaceId>.lua
-- straight off disk when it exists and skips the download, so dropping our
-- bundle there shadows upstream's copy.
--
-- The bundle is refetched every run, so it always matches the repo. It also
-- survives updates: wipeFolder only deletes files whose first line is
-- upstream's cache watermark, and the bundle starts with a plain comment.
--
-- Branding is applied to the live gui rather than to upstream's gui source.
-- That source is one 5000 line file needing its components injected at a
-- marker by a bundler we do not have, so rebuilding it to change a logo would
-- risk the whole menu. Everything below is additive and wrapped in pcall.

local BRAND = 'fxr'
local REPO = 'https://raw.githubusercontent.com/fxr-lmao/fxr.exe/main/dist/'
local UPSTREAM = 'https://raw.githubusercontent.com/7GrandDadPGN/VapeV4ForRoblox/main/NewMainScript.lua'

local BUNDLES = {
	[132768098780837] = REPO..'132768098780837.lua'
}

-- The mascot, shown on the gui button. Whatever png sits at this path in the
-- repo gets installed and used, so changing the logo is changing that file.
-- The window header is a separate slot and gets a wordmark instead, see below.
local LOGO_URL = REPO..'assets/fxrlogo.png'
local LOGO_FILE = 'newvape/assets/new/fxrlogo.png'

local function fetch(url)
	local ok, res = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and res and #res > 0 and res ~= '404: Not Found' then
		return res
	end
	return nil
end

local function folder(path)
	if not isfolder(path) then makefolder(path) end
end

local function installLogo()
	folder('newvape')
	folder('newvape/assets')
	folder('newvape/assets/new')

	local png = fetch(LOGO_URL)
	if not png then return false end
	writefile(LOGO_FILE, png)
	return true
end

local function brandLogo(logo)
	logo.Image = ''
	local label = logo:FindFirstChild('BrandText')
	if not label then
		label = Instance.new('TextLabel')
		label.Name = 'BrandText'
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = logo
	end
	label.Text = BRAND
	label.TextColor3 = logo.ImageColor3
end

-- Match on the asset each image is showing rather than on its name. The gui
-- button's ImageLabel is never named, so going by name missed it entirely and
-- left the vape pen sitting on screen.
local HEADER = 'newvape/assets/new/guivape.png'
local BADGE = 'newvape/assets/new/guiv4.png'
local ICON = 'newvape/assets/new/vape.png'

local function assetMap()
	local map = {}
	for _, path in {HEADER, BADGE, ICON} do
		local ok, asset = pcall(getcustomasset, path)
		if ok and asset then
			map[asset] = path
		end
	end
	return map
end

local function rebrand(vape, custom)
	if not vape or not vape.gui then return end
	local map = assetMap()

	for _, obj in vape.gui:GetDescendants() do
		if obj:IsA('ImageLabel') or obj:IsA('ImageButton') then
			local path = map[obj.Image]
			if path == BADGE then
				obj.Visible = false
			elseif path == HEADER then
				-- 62x18 and recoloured to a flat tint, so a wordmark, never art.
				brandLogo(obj)
			elseif path == ICON and custom then
				-- 26x26 and untouched by ImageColor3, so the mascot works here.
				obj.Image = getcustomasset(LOGO_FILE)
			end
		elseif obj:IsA('TextLabel') and obj.Text:sub(1, 5) == 'Vape ' then
			obj.Text = BRAND..obj.Text:sub(5)
		end
	end
end

local bundle = BUNDLES[game.PlaceId]
if bundle then
	folder('newvape')
	folder('newvape/games')

	local source = fetch(bundle)
	if source then
		writefile('newvape/games/'..game.PlaceId..'.lua', source)
	else
		warn('['..BRAND..'] could not fetch the bundle, falling back to upstream for this game')
	end
end

local custom = false
pcall(function()
	custom = installLogo()
end)

local main = fetch(UPSTREAM)
if not main then
	error('['..BRAND..'] could not reach upstream NewMainScript')
end
loadstring(main)()

local vape = shared.vape
if vape then
	-- Notifications name themselves, so catch the ones that say Vape.
	pcall(function()
		local old = vape.CreateNotification
		if old then
			vape.CreateNotification = function(self, title, ...)
				return old(self, title == 'Vape' and BRAND or title, ...)
			end
		end
	end)

	-- The window is built during load, but profiles and gui settings rebuild
	-- parts of it just after, so sweep a few times rather than racing it.
	task.spawn(function()
		for _ = 1, 10 do
			pcall(rebrand, vape, custom)
			task.wait(0.5)
		end
	end)
end
