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

-- Returns an asset string for the mascot, or nil when this executor cannot
-- make one. Mobile executors vary on whether getcustomasset exists at all,
-- which is presumably why the gui avoids it on touch in the first place.
local function installLogo()
	folder('newvape')
	folder('newvape/assets')
	folder('newvape/assets/new')

	local png = fetch(LOGO_URL)
	if not png then return nil end
	writefile(LOGO_FILE, png)

	if not getcustomasset then return nil end
	local ok, asset = pcall(getcustomasset, LOGO_FILE)
	if ok and type(asset) == 'string' and asset ~= '' then
		return asset
	end
	return nil
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

-- On touch devices the gui never resolves assets to local files. gui.lua:330
-- swaps its own getcustomasset for one returning these baked ids instead, so
-- an image's Image is this literal string and comparing against a local file
-- asset never matches -- which is why the button kept its vape pen on mobile.
local SLOTS = {
	['rbxassetid://14657521312'] = 'header',
	['rbxassetid://14368322199'] = 'badge',
	['rbxassetid://14373395239'] = 'icon'
}

-- 26x26 and never recoloured, so the mascot survives here. Falls back to text
-- if the executor cannot turn our png into an asset.
local function brandIcon(image, mascot)
	local label = image:FindFirstChild('BrandText')
	if mascot then
		image.Image = mascot
		if label then label:Destroy() end
		return
	end

	image.Image = ''
	if not label then
		label = Instance.new('TextLabel')
		label.Name = 'BrandText'
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = image
	end
	label.Text = BRAND
end

local function rebrand(vape, mascot)
	if not vape then return end

	-- The button's icon carries no name and, on mobile, no recognisable asset
	-- either, so reach it through the api rather than trying to spot it.
	if vape.VapeButton then
		for _, child in vape.VapeButton:GetChildren() do
			if child:IsA('ImageLabel') then
				brandIcon(child, mascot)
			end
		end
	end

	if not vape.gui then return end
	for _, obj in vape.gui:GetDescendants() do
		if obj:IsA('ImageLabel') or obj:IsA('ImageButton') then
			local slot = SLOTS[obj.Image]
			if slot == 'badge' or obj.Name == 'V4Logo' then
				obj.Visible = false
			elseif slot == 'header' or obj.Name == 'VapeLogo' then
				-- 62x18 and tinted flat, so a wordmark, never art.
				brandLogo(obj)
			elseif slot == 'icon' then
				brandIcon(obj, mascot)
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

local mascot
pcall(function()
	mascot = installLogo()
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
		for _ = 1, 20 do
			pcall(rebrand, vape, mascot)
			task.wait(0.5)
		end
	end)
end
