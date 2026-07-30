local BedESP
local ShowOwn
local ShowBroken
local adornments = {}

local ENEMY = Color3.fromRGB(255, 65, 65)
local OWN = Color3.fromRGB(80, 200, 255)
local BROKEN = Color3.fromRGB(130, 130, 130)

local function isOwnBed(bed)
	return bed:GetAttribute('BedTeamId') == (lplr.Team and lplr.Team.Name or '')
end

local function adorn(bed)
	local highlight = Instance.new('Highlight')
	highlight.Adornee = bed
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.6
	highlight.Parent = vape.gui

	local billboard = Instance.new('BillboardGui')
	billboard.Adornee = bed
	billboard.Size = UDim2.fromOffset(200, 24)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = vape.gui

	local label = Instance.new('TextLabel')
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextStrokeTransparency = 0.4
	label.TextSize = 15
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	adornments[bed] = {Highlight = highlight, Billboard = billboard, Label = label}
	return adornments[bed]
end

local function refresh(bed)
	local entry = adornments[bed] or adorn(bed)
	local own = isOwnBed(bed)
	local hp = bed:GetAttribute('HP') or 10
	local broken = hp <= 0

	-- The whole point is not spending five minutes mining your own bed, so the
	-- label says whose it is rather than relying on colour alone.
	local visible = (not broken or ShowBroken.Enabled) and (not own or ShowOwn.Enabled)
	local color = broken and BROKEN or (own and OWN or ENEMY)

	entry.Highlight.Enabled = visible
	entry.Highlight.FillColor = color
	entry.Highlight.OutlineColor = color
	entry.Billboard.Enabled = visible
	entry.Label.TextColor3 = color
	entry.Label.Text = broken
		and ((own and 'YOUR BED' or 'ENEMY BED')..' (broken)')
		or ((own and 'YOUR BED' or 'ENEMY BED')..' - '..math.floor(hp))
end

BedESP = vape.Categories.Render:CreateModule({
	Name = 'BedESP',
	Function = function(callback)
		if callback then
			local beds = collection('BedWarsX_BedSpawn', BedESP)

			BedESP:Clean(runService.Heartbeat:Connect(function()
				local seen = {}
				for _, bed in beds do
					seen[bed] = true
					refresh(bed)
				end

				for bed, entry in adornments do
					if not seen[bed] then
						entry.Highlight:Destroy()
						entry.Billboard:Destroy()
						adornments[bed] = nil
					end
				end
			end))

			BedESP:Clean(function()
				for bed, entry in adornments do
					entry.Highlight:Destroy()
					entry.Billboard:Destroy()
					adornments[bed] = nil
				end
			end)
		end
	end,
	Tooltip = 'Highlights every bed and labels whose team it belongs to.'
})
ShowOwn = BedESP:CreateToggle({
	Name = 'Show own bed',
	Default = true,
	Tooltip = 'Also highlight your own bed, in a different colour'
})
ShowBroken = BedESP:CreateToggle({
	Name = 'Show broken beds',
	Tooltip = 'Keep showing beds that are already destroyed'
})
