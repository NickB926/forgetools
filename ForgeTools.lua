--[[
	ForgeTools.lua — The Forge (Roblox) helper with an Ataraxia window.
	  • Auto mine   — tweens to rocks and mines them with the game's own swing.
	  • Auto sell   — tweens to Greedy Cey and sells your ores when the bag is getting full.
	  • Auto forge  — tweens to the forge, puts in your ores and plays every minigame perfectly.
	  • Auto mobs   — tweens to mobs (the Living folder) and fights them with your Weapon.
	Movement is always a tween (no long teleports — the game snaps those back).
	Needs workspace/PlayerTools/AtaraxiaLibrary.lua. Autoload: autoexec/03_forgetools.lua.
]]

local BUILD = 'forge-tools-v326'
local G = getgenv()
local compile = loadstring or load

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService')
local HttpService = game:GetService('HttpService')
local RS = game:GetService('ReplicatedStorage')
local PathfindingService = game:GetService('PathfindingService')
local LocalPlayer = Players.LocalPlayer

if type(G.SB2ForgeToolsUnload) == 'function' then
	pcall(G.SB2ForgeToolsUnload)
end
G.SB2ForgeToolsLoaded = true
G.FTTrips, G.FTTravel = {}, nil
G.SB2ForgeToolsBuild = BUILD

local alive = true
local conns = {}
local function track(c)
	conns[#conns + 1] = c
	return c
end

---------------------------------------------------------------------------
-- Game modules
---------------------------------------------------------------------------
local Knit = require(RS:WaitForChild('Shared'):WaitForChild('Packages'):WaitForChild('Knit'))
local function controller(name)
	local ok, c = pcall(Knit.GetController, name)
	return ok and c or nil
end
local function service(name)
	local ok, s = pcall(Knit.GetService, name)
	return ok and s or nil
end
local PlayerController
repeat
	PlayerController = controller('PlayerController')
	task.wait(0.5)
until PlayerController and PlayerController.Replica or not alive
local function data()
	return PlayerController and PlayerController.Replica and PlayerController.Replica.Data
end

local ORE_NAMES = {}
pcall(function()
	for _, v in pairs(require(RS.Shared.Data.Ore)) do
		if type(v) == 'table' and v.Name then
			ORE_NAMES[v.Name] = v.Rarity or 'Common'
		end
	end
end)

---------------------------------------------------------------------------
-- Settings (per account)
---------------------------------------------------------------------------
local ACCT = string.lower(tostring(LocalPlayer.Name)):gsub('[^%w_]', '')
local SETTINGS_PATH = 'PlayerTools/forgetools_' .. ACCT .. '.json'
local settings = {}
pcall(function()
	settings = HttpService:JSONDecode(readfile(SETTINGS_PATH))
end)
if type(settings) ~= 'table' then
	settings = {}
end
local defaults = {
	autoMine = false,
	mineZone = 'Any',
	skipLucky = false,
	autoSell = false,
	autoSellGear = false,
	autoRecycle = false,
	forgeWhenFull = false,
	forgeAlternate = false,
	autoEnhance = false,
	enhanceMinChance = 0,
	enhanceMaxLevel = 9,
	raceStop = 'Legendary',
	raceWant = {},
	raceMine = 'No change',
	raceFight = 'No change',
	raceKeepSpins = 0,
	sellAt = 90,
	autoForge = false,
	forgeType = 'Weapon',
	forgePiece = 'Any',
	forgeMold = 'None',
	fleeDeadly = true,
	forgeOres = 3,
	forgeMinOres = 3,
	forgeTraits = false,
	forgeTraitOres = {},
	forgeKeep = 0,
	switchMins = 3,
	autoAcceptQuests = false,
	autoCompleteQuests = false,
	questBuy = false,
	autoPickaxe = false,
	autoSellRunes = false,
	runeSellTier = 1,
	runeSellEpic = false,
	runeKeepTier = 3,
	runeKeep = { ['Drain Edge'] = true, ['Briar Notch'] = true, ['Miner Shard'] = true },
	autoLuckPotion = false,
	autoMinerPotion = false,
	tracers = false,
	mobTracers = false,
	huntSpecial = {},
	claimBoard = false,
	autoBlock = false,
	autoMail = false,
	autoOffer = false,
	autoCodes = false,
	autoDaily = false,
	parryLead = 20,
	parryShineLead = 0,
	forgeBest = false,
	questRange = 1000,
	noBlur = false,
	combatStyle = 'Hit & run',
	dodgeWhat = 'Only threats',
	autoAbyss = false,
	autoBoss = false,
	dodgeDist = 16,
	autoMobs = false,
	mobFilter = 'Any',
	retreatHp = 45,
	healTo = 60,
	kiteHp = 40,
	mineRocks = {},
	mineMutations = {},
	mineMeteors = false,
	maxMobHp = 80,
	autoEquip = false,
	tweenSpeed = 55,
	walkSpeed = 50,
	autoload = true,
	focusQuest = 'Auto',
	keepOres = {},
	keepTraitOres = false,
	raidTier = 1,
	raidRetries = 0,
	raidTicketMax = 5,
	raidFarming = false,
	raidSideMine = false,
	autoCards = false,
	cardFocus = 'Best overall',
	allowCursed = false,
}
for k, v in pairs(defaults) do
	if settings[k] == nil then
		settings[k] = v
	end
end
if settings.combatStyle == 'Float above' then
	settings.combatStyle = 'Hit & run' -- tested: mobs hit straight up, so floating doesn't protect you
end
-- (v238, asked for: "parry on asura, no parry on normal mobs") the island boss is always fought
-- with Block / parry when the style is Attack only; everything else uses the style as set.
-- (v296, asked for: fight modes for mining fights. Two new ones ride on the old ones:
-- 'Behind + dodge' is Hit & run that hops in behind the mob's back instead of on our side of it;
-- 'Face tank' is Attack only that walks straight up to the mob's face - no hopping round behind it,
-- no dodge, no block. Everything else in the code reads them as the style they are built on.)
local STYLE_BASE = { ['Behind + dodge'] = 'Hit & run', ['Face tank'] = 'Attack only' }
local function combatStyle()
	local cs = STYLE_BASE[settings.combatStyle] or settings.combatStyle
	if G.FTBossFight and cs == 'Attack only' then
		return 'Block / parry'
	end
	-- (v252, asked for: "crowd mode". Measured in the Abyss with 8-10 mobs around: 2.5 attack shines
	-- a second, 167 of 394 block presses refused, 61 hits in 75 s. A block cannot cover hits that
	-- close together, so with 5 or more mobs in reach a Block / parry fight is fought as Hit & run.)
	if G.FTCrowdMode and not G.FTBossFight and cs == 'Block / parry' then
		return 'Hit & run'
	end
	return cs
end
local function save()
	pcall(writefile, SETTINGS_PATH, HttpService:JSONEncode(settings))
end
save()

---------------------------------------------------------------------------
-- Character / movement
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Player tracers (loads Tracers.iy) + a PillDock floating pill to toggle them
---------------------------------------------------------------------------
local TRACERS_FILES = { 'Tracers.iy', 'PlayerTools/Tracers.iy', 'workspace/Tracers.iy' }
local PILLDOCK_FILES = { 'PillDock.lua', 'PlayerTools/PillDock.lua' }
local function runStandalone(paths)
	for _, p in ipairs(paths) do
		local okR, body = pcall(readfile, p)
		if okR and type(body) == 'string' and #body > 0 then
			local fn = compile(body, '@' .. p)
			if fn and pcall(fn) then
				return true
			end
		end
	end
	return false
end
local function setTracers(on)
	if on then
		runStandalone(TRACERS_FILES) -- (re)wires its own RenderStepped, keeps its state
		if G.SB2Tracers then
			G.SB2Tracers.enabled = true
		end
	elseif type(G.SB2TracersStop) == 'function' then
		pcall(G.SB2TracersStop)
	end
end
local function wireTracersPill()
	runStandalone(PILLDOCK_FILES)
	local reg = G.SB2RegisterPill
	if type(reg) ~= 'function' then
		return false
	end
	local btn
	local function paint()
		if not btn then
			return
		end
		local on = settings.tracers == true
		btn.Text = on and 'TR \226\151\143' or 'TR'
		btn.TextColor3 = on and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(220, 230, 245)
		local st = btn:FindFirstChildOfClass('UIStroke')
		if st then
			st.Color = on and Color3.fromRGB(80, 200, 110) or Color3.fromRGB(70, 90, 120)
		end
	end
	btn = reg({
		id = 'TR',
		text = settings.tracers and 'TR \226\151\143' or 'TR',
		onClick = function()
			settings.tracers = not settings.tracers
			save()
			setTracers(settings.tracers)
			paint()
		end,
	})
	paint()
	return true
end

-- (v220) ores still missing for a craft the user asked for: G.FTCraftNeed = { ore = count }.
-- While any is short, mining runs (as if Auto mine were ticked) and G.FTCraftRocks come first.
local function craftWant()
	local need = G.FTCraftNeed
	if type(need) ~= 'table' then
		return false
	end
	local d = data()
	local inv = d and d.Inventory or {}
	for ore, n in pairs(need) do
		if (tonumber(inv[ore]) or 0) < n then
			return true
		end
	end
	return false
end
-- (v230) drops still missing that the user asked for: G.FTDropNeed = { { ore = 'Yin', n = 5,
-- mob = 'Pale Oni' }, ... }. While one is short its mob is the fight target, ahead of quests.
-- (v245) is one of the rocks wanted for a craft (G.FTCraftRocks) standing in the world right now?
local function craftRockUp()
	local rocks = workspace:FindFirstChild('Rocks')
	if type(G.FTCraftRocks) ~= 'table' or not rocks then
		return false
	end
	for _, r in ipairs(rocks:GetDescendants()) do
		if r:IsA('Model') and G.FTCraftRocks[r.Name] then
			return true
		end
	end
	return false
end
local function dropTarget()
	local need = G.FTDropNeed
	if type(need) ~= 'table' then
		return nil
	end
	local d = data()
	local inv = d and d.Inventory or {}
	-- (v231: the first short one whose mob is alive right now - with no Spirit Golem up it fought
	-- any mob at all instead of moving on to the Pale Onis)
	local living = workspace:FindFirstChild('Living')
	local first
	-- (v272, asked for: farm Weapon Molds for the Moon Crescent Spear. A mold is not an ore: it is
	-- an entry { Name, Quantity } in Inventory.Misc, so it was always counted as 0 held.)
	local function held(name)
		local nOre = tonumber(inv[name])
		if nOre then
			return nOre
		end
		for _, it in pairs(type(inv.Misc) == 'table' and inv.Misc or {}) do
			if type(it) == 'table' and it.Name == name then
				return tonumber(it.Quantity) or 0
			end
		end
		return 0
	end
	for _, e in ipairs(need) do
		if type(e) == 'table' and held(e.ore) < (tonumber(e.n) or 0) then
			first = first or e.mob
			for _, m in ipairs(living and living:GetChildren() or {}) do
				if string.sub(m.Name, 1, #e.mob) == e.mob and m:GetAttribute('IsNpc') then
					local h = m:FindFirstChildOfClass('Humanoid')
					if h and h.Health > 0 then
						return e.mob
					end
				end
			end
		end
	end
	if not first then
		G.FTDropNeed = nil
	end
	return first
end

local function char()
	local c = LocalPlayer.Character
	local hrp = c and c:FindFirstChild('HumanoidRootPart')
	local hum = c and c:FindFirstChildOfClass('Humanoid')
	return c, hrp, hum
end

local noclip = false
track(RunService.Stepped:Connect(function()
	if not noclip then
		return
	end
	local c = LocalPlayer.Character
	if not c then
		return
	end
	for _, p in ipairs(c:GetDescendants()) do
		if p:IsA('BasePart') and p.CanCollide then
			p.CanCollide = false
		end
	end
end))

local currentTween
-- (v223) Island 3's locked Red Cave door ("Heart Door", an invisible barrier 29 x 47 x 54 at
-- 375,31,83, about 330 studs from the spawn). Measured: every trip that cut through it with
-- collisions off was sent back to the spawn a second later - 51 times in a row on the way to
-- Morveth. Its prompt is disabled on this account, so the door is simply not ours to pass.
-- So: glides go round it, and anything else that drifts into it is put back where it came from.
local Door = { on = game.PlaceId == 131884594917121 }
-- (v227) Not just the door: the whole Red Cave behind it is off limits until the door is unlocked
-- (Raven 2's key). Measured: glides that clipped through the cave at (631,17,-60), (526,50,-41),
-- (474,59,-35), (628,68,-65) were all sent back to the spawn. The game marks its zones with flat
-- plates in workspace.Debris.Regions; everything UNDER an "Island3RedCave..." plate is the cave
-- (the peak caves lie above those plates and are fine). Morveth, Raven 3, Auron and Mjelatkhan
-- stand inside it.
function Door.boxes()
	if not Door.on then
		return nil
	end
	if Door.list and os.clock() - Door.at < 20 then
		return Door.list
	end
	Door.at = os.clock()
	local d = data()
	if d and type(d.MiscDialogues) == 'table' and d.MiscDialogues.UnlockedRedCaveDoor then
		Door.list = {} -- (unlocked: nothing to keep out of)
		return Door.list
	end
	local list = {}
	local function add(part, top)
		local p, sz = part.Position, part.Size
		list[#list + 1] = { p.X - sz.X / 2, p.X + sz.X / 2, p.Z - sz.Z / 2, p.Z + sz.Z / 2, top }
	end
	local deb = workspace:FindFirstChild('Debris')
	local regs = deb and deb:FindFirstChild('Regions')
	for _, r in ipairs(regs and regs:GetChildren() or {}) do
		if r:IsA('BasePart') and string.sub(r.Name, 1, 14) == 'Island3RedCave' then
			add(r, r.Position.Y + 3)
		end
	end
	local a = workspace:FindFirstChild('Assets')
	local hd = a and a:FindFirstChild('Heart Door')
	local b = hd and hd:FindFirstChild('Barrier')
	if b then
		add(b, b.Position.Y + b.Size.Y / 2 + 5)
	end
	Door.list = list
	return list
end
-- is this spot inside the locked cave (grown by m studs sideways)?
function Door.inPoint(p, m)
	for _, b in ipairs(Door.boxes() or {}) do
		if p.X > b[1] - m and p.X < b[2] + m and p.Z > b[3] - m and p.Z < b[4] + m and p.Y < b[5] then
			return true
		end
	end
	return false
end
-- does the straight move a -> b pass through the locked cave? Returns the highest plate crossed.
function Door.hits(a, b, m)
	local low = math.min(a.Y, b.Y)
	local top
	for _, bx in ipairs(Door.boxes() or {}) do
		if low < bx[5] then
			local t0, t1, hit = 0, 1, true
			for _, v in ipairs({ { b.X - a.X, a.X, bx[1] - m, bx[2] + m }, { b.Z - a.Z, a.Z, bx[3] - m, bx[4] + m } }) do
				local dd, o, lo, hi = v[1], v[2], v[3], v[4]
				if math.abs(dd) < 1e-6 then
					if o <= lo or o >= hi then
						hit = false
						break
					end
				else
					local ta, tb = (lo - o) / dd, (hi - o) / dd
					if ta > tb then
						ta, tb = tb, ta
					end
					t0, t1 = math.max(t0, ta), math.min(t1, tb)
					if t0 >= t1 then
						hit = false
						break
					end
				end
			end
			if hit then
				top = math.max(top or -math.huge, bx[5])
			end
		end
	end
	return top ~= nil, top
end
-- (v226: the v223 guard that put the character back at the door is gone - it fired 7,696 times
-- and pinned the character there. Routes are refused before they start instead.)

local function stopTween()
	if currentTween then
		pcall(function()
			currentTween:Cancel()
		end)
		currentTween = nil
	end
	noclip = false
end

-- Tween the character to a CFrame. Returns true when it got there.
-- Walk to a target around walls (collisions ON, no noclip) so the game's anti-noclip
-- can't bounce us to spawn. Returns true if we reached it (or opts.abort fired).
local function groundAt(pos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { LocalPlayer.Character }
	rp.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), rp)
	return hit and (hit.Position + Vector3.new(0, 3, 0)) or pos
end

-- Lava. The game hurts you through invisible flat sheets (workspace.Debris.LavaDamageZone) lying
-- at the lava's surface: you burn wherever the ground is at or below a sheet, inside its outline.
-- Lava.at(pos) takes a standing position (ground + 3) and returns the sheet's height, or nil.
local Lava = { zones = {}, at0 = -1e9 }
function Lava.at(pos)
	if os.clock() - Lava.at0 > 5 then
		Lava.at0 = os.clock()
		local zones = {}
		local deb = workspace:FindFirstChild('Debris')
		for _, x in ipairs(deb and deb:GetChildren() or {}) do
			if x:IsA('BasePart') and string.find(x.Name, 'LavaDamage', 1, true) then
				zones[#zones + 1] = x
			end
		end
		Lava.zones = zones
	end
	for _, z in ipairs(Lava.zones) do
		if z.Parent then
			local l = z.CFrame:PointToObjectSpace(pos)
			if math.abs(l.X) <= z.Size.X / 2 + 1 and math.abs(l.Z) <= z.Size.Z / 2 + 1 and l.Y - 3 <= z.Size.Y / 2 + 1.5 and l.Y > -40 then
				return z.Position.Y + z.Size.Y / 2
			end
		end
	end
	return nil
end

local function computePath(from, goals)
	for _, radius in ipairs({ 2, 1 }) do
		for _, goal in ipairs(goals) do
			local p = PathfindingService:CreatePath({ AgentRadius = radius, AgentHeight = 5, AgentCanJump = true })
			local okc = pcall(function()
				p:ComputeAsync(from, goal)
			end)
			if okc and p.Status == Enum.PathStatus.Success then
				local wps = p:GetWaypoints()
				-- The pathfinder snaps the goal to the nearest walkable spot, which can be a
				-- different floor right above / below it: only accept paths that really end there.
				local endGap = #wps >= 2 and (wps[#wps].Position - goal) or nil
				local okEnd = endGap and math.abs(endGap.Y) <= 7 and Vector3.new(endGap.X, 0, endGap.Z).Magnitude <= 7
				-- It also happily plans "jumps" up 6-9 stud boulders (straight up a mountainside to a
				-- rock inside the cave below). We can't make those: such a path is no path.
				if okEnd then
					for i = 2, #wps do
						local step = wps[i].Position - wps[i - 1].Position
						if step.Y > 5 and Vector3.new(step.X, 0, step.Z).Magnitude < step.Y * 0.8 then
							okEnd = false
							break
						end
					end
				end
				if okEnd then
					return wps
				end
			end
		end
	end
	return nil
end

-- Is the spot we're standing on part of the walkable map at all? (Wedged in a nook between
-- walls the pathfinder says "no path" to everything, which says nothing about the target.)
local function startOnMesh(from)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local probe = groundAt(from + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14))
		if math.abs(probe.Y - from.Y) < 8 and computePath(from, { probe }) then
			return true
		end
	end
	return false
end

-- Wedged against walls: walk toward the most open side for a moment so paths work again.
local function unwedge()
	local _, hrp, hum = char()
	if not hrp or not hum then
		return
	end
	-- Standing somewhere the pathfinder has no map for (a ledge lip, a platform edge): walk a
	-- few studs to open ground that IS on the map, trying a different direction each time.
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living') }
	local cands = {}
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local hit = workspace:Raycast(hrp.Position, dir * 24, rp)
		local open = hit and (hit.Position - hrp.Position).Magnitude or 24
		if open > 7 then
			local step = math.min(open - 2, 14)
			local g = workspace:Raycast(hrp.Position + dir * step + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), rp)
			if g then
				cands[#cands + 1] = { pos = g.Position + Vector3.new(0, 3, 0), score = open + math.random() * 12 }
			end
		end
	end
	table.sort(cands, function(x, y)
		return x.score > y.score
	end)
	local goal
	for i = 1, math.min(4, #cands) do
		-- a spot from which the map works again
		local c = cands[i].pos
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2
			local probe = groundAt(c + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14))
			if math.abs(probe.Y - c.Y) < 8 and computePath(c, { probe }) then
				goal = c
				break
			end
		end
		if goal then
			break
		end
	end
	goal = goal or (cands[1] and cands[1].pos)
	if not goal then
		return
	end
	local t0 = os.clock()
	hum:MoveTo(goal)
	while alive and os.clock() - t0 < 2.5 do
		local d = goal - hrp.Position
		if Vector3.new(d.X, 0, d.Z).Magnitude < 2 then
			break
		end
		task.wait(0.1)
	end
end

-- Long-range routing. The game's pathfinder gives up on long routes (from spawn it says
-- "no path" to every cave), so we keep a few known-good spots ("nodes") and chain short
-- paths between them. Nodes are remembered per place and grow as the character walks around.
local Nav = { nodes = {}, edges = {} }
do
	local navFile = 'PlayerTools/forgetools_nav_' .. tostring(game.PlaceId) .. '.json'
	local SEEDS = {
		[129009554587176] = { -- island 2: town -> cave entrance -> up the ramp -> first cave
			{ 35, 21, -166 }, { 21, 34, -210 }, { 66, 54, -246 }, { 133, 69, -246 },
			{ 179, 75, -202 }, { 175, 74, -134 }, { 187, 77, -98 },
			-- lower cave -> Volcanic Depths: open floor, but the pathfinder has a seam between them
			{ 322, 57, -70 }, { 350, 57, -70 }, { 317.6, 57.9, 2.3 },
			{ 407.5, 53.7, 193.4 }, { 489.8, 53.9, 286 }, { 558.4, 54.8, 159.7 },
			-- top and landing of the ledge between the upper cave level and Volcanic Depths
			{ 366, 86, 79 }, { 372, 72, 80 },
		},
	}
	local function add(v, minGap)
		for _, n in ipairs(Nav.nodes) do
			if (n - v).Magnitude < (minGap or 40) then
				return false
			end
		end
		Nav.nodes[#Nav.nodes + 1] = v
		return true
	end
	local function saveNodes()
		local t = {}
		for i, n in ipairs(Nav.nodes) do
			t[i] = { math.floor(n.X * 10) / 10, math.floor(n.Y * 10) / 10, math.floor(n.Z * 10) / 10 }
		end
		pcall(writefile, navFile, HttpService:JSONEncode(t))
	end
	pcall(function()
		for _, t in ipairs(HttpService:JSONDecode(readfile(navFile))) do
			add(Vector3.new(t[1], t[2], t[3]))
		end
	end)
	for _, t in ipairs(SEEDS[game.PlaceId] or {}) do
		add(groundAt(Vector3.new(t[1], t[2], t[3])), 8)
	end
	-- Remember where we are standing as a node (only while walking on solid ground).
	-- Only remember open ground: a spot squeezed between rocks (or inside one, after a bad hop)
	-- becomes a trap that every later route gets sent through.
	local function openGround(pos)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living') }
		local clear = 0
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			if not workspace:Raycast(pos, Vector3.new(math.cos(a), 0, math.sin(a)) * 4, rp) then
				clear += 1
			end
		end
		return clear >= 6 and not workspace:Raycast(pos, Vector3.new(0, 5, 0), rp)
	end
	function Nav.crumb(pos, hum)
		if hum and hum.FloorMaterial ~= Enum.Material.Air and hum:GetState() == Enum.HumanoidStateType.Running
			and openGround(pos) and add(pos) then
			saveNodes()
		end
	end
	local function pathLen(w)
		local len = 0
		for i = 2, #w do
			len += (w[i].Position - w[i - 1].Position).Magnitude
		end
		return len
	end
	-- Two nearby spots on open, level floor with nothing between them: walk straight across.
	-- (The pathfinder's map has seams where two areas meet, e.g. cave -> Volcanic Depths.)
	local function straightLink(a, b)
		local d = b - a
		if d.Magnitude > 32 or d.Magnitude < 1 or math.abs(d.Y) > 5 then
			return nil
		end
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living') }
		if workspace:Raycast(a, d, rp) or workspace:Raycast(a - Vector3.new(0, 1.8, 0), d, rp) then
			return nil
		end
		local lastY = a.Y - 3
		for t = 3, d.Magnitude, 3 do
			local g = workspace:Raycast(a + d.Unit * t + Vector3.new(0, 1, 0), Vector3.new(0, -9, 0), rp)
			if not g or math.abs(g.Position.Y - lastY) > 3 then
				return nil
			end
			lastY = g.Position.Y
		end
		return { { Position = a }, { Position = b } }
	end
	-- Ledges the pathfinder only knows some of the time (a rock spawning on the lip removes the
	-- drop from its map, and it never knows the way back up): a short hop, both directions.
	local HOPS = {
		{ Vector3.new(366, 88, 79), Vector3.new(372, 74, 80) }, -- upper cave level <-> Volcanic Depths
	}
	local function hopLink(a, b)
		if game.PlaceId ~= 129009554587176 then
			return nil
		end
		for _, hp in ipairs(HOPS) do
			if ((a - hp[1]).Magnitude < 7 and (b - hp[2]).Magnitude < 7) or ((a - hp[2]).Magnitude < 7 and (b - hp[1]).Magnitude < 7) then
				return { { Position = a }, { Position = b, Hop = true } }
			end
		end
		return nil
	end
	-- The map: nodes (spots) + edges (walkable paths between two spots, with their waypoints).
	-- Edges are SAVED, so a route that was worked out once is never computed again: planning is
	-- then a plain shortest-path search over the saved map plus one path call for the last leg.
	local EDGE_R = 130
	local edgeFile = 'PlayerTools/forgetools_navedges_' .. tostring(game.PlaceId) .. '.json'
	local dirty, lastSave = false, 0
	local function nk(v)
		return ('%d,%d,%d'):format(math.floor(v.X + 0.5), math.floor(v.Y + 0.5), math.floor(v.Z + 0.5))
	end
	local keyCache = {}
	local function ek(u, v)
		local id = u * 4096 + v
		local k = keyCache[id]
		if not k then
			k = nk(Nav.nodes[u]) .. '>' .. nk(Nav.nodes[v])
			keyCache[id] = k
		end
		return k
	end
	local function plain(w)
		local out = {}
		for i, wp in ipairs(w) do
			out[i] = type(wp) == 'table' and wp or { Position = wp.Position, Action = wp.Action }
		end
		return out
	end
	pcall(function()
		if isfile(edgeFile) then
			local now = os.time()
			for k, e in pairs(HttpService:JSONDecode(readfile(edgeFile))) do
				if type(e) == 'table' and type(e.p) == 'table' then
					local w = {}
					for i = 1, #e.p, 3 do
						local c = string.sub(e.a or '', (i + 2) / 3, (i + 2) / 3)
						w[#w + 1] = {
							Position = Vector3.new(e.p[i], e.p[i + 1], e.p[i + 2]),
							Action = (c == 'J' and Enum.PathWaypointAction.Jump) or (c == 'W' and Enum.PathWaypointAction.Walk) or nil,
						}
					end
					if #w >= 2 then
						Nav.edges[k] = { w = w, len = tonumber(e.l) or pathLen(w) }
					end
				elseif type(e) == 'table' and e.t and now - e.t < 1800 then
					Nav.edges[k] = { bad = e.t }
				end
			end
		end
	end)
	function Nav.saveEdges(force)
		if not dirty or (not force and os.clock() - lastSave < 20) then
			return
		end
		dirty, lastSave = false, os.clock()
		local out = {}
		for k, e in pairs(Nav.edges) do
			if e.w then
				if not (e.w[2] and e.w[2].Hop) then
					local pts, acts = {}, {}
					for _, wp in ipairs(e.w) do
						local v = wp.Position
						pts[#pts + 1] = math.floor(v.X * 10 + 0.5) / 10
						pts[#pts + 1] = math.floor(v.Y * 10 + 0.5) / 10
						pts[#pts + 1] = math.floor(v.Z * 10 + 0.5) / 10
						acts[#acts + 1] = (wp.Action == Enum.PathWaypointAction.Jump and 'J') or (wp.Action ~= nil and 'W') or 'N'
					end
					out[k] = { p = pts, a = table.concat(acts), l = math.floor(e.len) }
				end
			elseif e.bad then
				out[k] = { t = e.bad }
			end
		end
		pcall(writefile, edgeFile, HttpService:JSONEncode(out))
	end
	-- known hops are part of the map from the start
	for u = 1, #Nav.nodes do
		for v = 1, #Nav.nodes do
			if u ~= v then
				local w = hopLink(Nav.nodes[u], Nav.nodes[v])
				if w then
					Nav.edges[ek(u, v)] = { w = w, len = 20 }
				end
			end
		end
	end
	-- cached edge (or nil); second result: true when nothing is known about this pair yet
	local function known(u, v)
		local k = ek(u, v)
		local e = Nav.edges[k]
		if e and e.w then
			return e, false
		end
		if e and e.bad and os.time() - e.bad > 1800 then
			Nav.edges[k] = nil
			return nil, true
		end
		return nil, e == nil
	end
	local function compute(u, v)
		local a, b = Nav.nodes[u], Nav.nodes[v]
		local w = hopLink(a, b) or computePath(a, { b }) or straightLink(a, b)
		local e = w and { w = plain(w), len = pathLen(w) } or { bad = os.time() }
		Nav.edges[ek(u, v)] = e
		dirty = true
		return e.w and e or nil
	end
	local goalTried = {}
	local attachCache
	-- No saved spots lead anywhere useful (a new island, or a corner the map does not cover yet):
	-- path to a point part of the way toward the target, a little left / right if need be.
	local relayTried = {}
	local function relay(from, target)
		local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
		if flat.Magnitude < 45 then
			return nil
		end
		local key = nk(from * 0.125) .. '|' .. nk(target * 0.125)
		if relayTried[key] and os.clock() - relayTried[key] < 120 then
			return nil
		end
		local tEnd = os.clock() + 3
		for _, step in ipairs({ 150, 90, 50 }) do
			if step < flat.Magnitude then
				for _, ang in ipairs({ 0, 30, -30 }) do
					if os.clock() > tEnd then
						break
					end
					local a = math.rad(ang)
					local u = flat.Unit
					local dir = Vector3.new(u.X * math.cos(a) - u.Z * math.sin(a), 0, u.X * math.sin(a) + u.Z * math.cos(a))
					local t = step / flat.Magnitude
					for _, y in ipairs({ from.Y, from.Y + (target.Y - from.Y) * t }) do
						local probe = from + dir * step
						local g = groundAt(Vector3.new(probe.X, y, probe.Z))
						local w = computePath(from, { g })
						if w then
							return plain(w)
						end
					end
				end
			end
		end
		relayTried[key] = os.clock()
		return nil
	end
	-- Returns waypoints, partial. partial = true when it only gets us closer (to the reachable
	-- node nearest the target); the caller walks it and then plans again from there.
	-- Never thinks for more than ~3 seconds per call.
	function Nav.route(from, goals, target)
		local N = Nav.nodes
		if #N == 0 then
			local w = relay(from, target)
			return w, w ~= nil
		end
		local tEnd = os.clock() + 3
		-- 1. which nodes can we walk to from here? (remembered for a moment: bursts repeat this)
		local startW
		local fk = nk(from * 0.25)
		if attachCache and attachCache.k == fk and os.clock() - attachCache.at < 20 and #N == attachCache.n then
			startW = attachCache.w
		else
			startW = {}
			local order = {}
			for i = 1, #N do
				order[i] = i
			end
			table.sort(order, function(x, y)
				return (N[x] - from).Magnitude < (N[y] - from).Magnitude
			end)
			local got = 0
			for n, i in ipairs(order) do
				local d = (N[i] - from).Magnitude
				if d > 350 or n > 8 or got >= 2 then
					break
				end
				if d < 6 then
					startW[i] = { { Position = from }, { Position = N[i] } }
					got += 1
				else
					local w = computePath(from, { N[i] })
					if w then
						startW[i] = plain(w)
						got += 1
					end
				end
			end
			attachCache = { k = fk, at = os.clock(), n = #N, w = startW }
		end
		if next(startW) == nil then
			local w = relay(from, target)
			return w, w ~= nil
		end
		-- 2. shortest paths over what the map already knows (no path calls at all)
		local function solve()
			local dist, prev, done = {}, {}, {}
			for i, w in pairs(startW) do
				dist[i], prev[i] = pathLen(w), 0
			end
			while true do
				local u, du
				for i, d in pairs(dist) do
					if not done[i] and (not du or d < du) then
						u, du = i, d
					end
				end
				if not u then
					break
				end
				done[u] = true
				for v = 1, #N do
					if not done[v] and (N[v] - N[u]).Magnitude <= EDGE_R then
						local e = known(u, v)
						if e and du + e.len < (dist[v] or math.huge) then
							dist[v], prev[v] = du + e.len, u
						end
					end
				end
			end
			return dist, prev
		end
		local function assemble(prev, u, last)
			local chain = {}
			while u and u ~= 0 do
				local pu = prev[u]
				table.insert(chain, 1, pu == 0 and startW[u] or Nav.edges[ek(pu, u)].w)
				u = pu
			end
			if last then
				chain[#chain + 1] = last
			end
			local out = {}
			for _, w in ipairs(chain) do
				for _, wp in ipairs(w) do
					out[#out + 1] = wp
				end
			end
			return out
		end
		local goalPair = { goals[1], goals[2] }
		local tk = nk(target * 0.25)
		while alive do
			local dist, prev = solve()
			-- 3. last leg: from the reachable nodes that look best for this target
			local cands = {}
			for i, d in pairs(dist) do
				local sl = (N[i] - target).Magnitude
				if sl <= 250 then
					cands[#cands + 1] = { i = i, f = d + sl * 1.3 }
				end
			end
			table.sort(cands, function(x, y)
				return x.f < y.f
			end)
			local tries = 0
			for _, c in ipairs(cands) do
				if tries >= 3 or os.clock() > tEnd then
					break
				end
				local gk = nk(N[c.i]) .. '|' .. tk
				local at = goalTried[gk]
				if not at or os.clock() - at > 120 then
					tries += 1
					local w = computePath(N[c.i], goalPair)
					if w then
						Nav.saveEdges()
						return assemble(prev, c.i, plain(w)), false
					end
					goalTried[gk] = os.clock()
				end
			end
			if os.clock() > tEnd then
				break
			end
			-- 4. not there yet: learn a few more edges, the most promising first, and look again
			local todo = {}
			for u, du in pairs(dist) do
				for v = 1, #N do
					if v ~= u then
						local gap = (N[v] - N[u]).Magnitude
						if gap <= EDGE_R then
							local e, unknown = known(u, v)
							if not e and unknown then
								todo[#todo + 1] = { u = u, v = v, f = du + gap + (N[v] - target).Magnitude }
							end
						end
					end
				end
			end
			if #todo == 0 then
				break
			end
			table.sort(todo, function(x, y)
				return x.f < y.f
			end)
			local n = 0
			for _, t in ipairs(todo) do
				if n >= 8 or os.clock() > tEnd then
					break
				end
				compute(t.u, t.v)
				n += 1
			end
		end
		Nav.saveEdges()
		local dist, prev = solve()
		local best, bestS = nil, (target - from).Magnitude - 25
		for i in pairs(dist) do
			local sl = (N[i] - target).Magnitude
			if sl < bestS then
				best, bestS = i, sl
			end
		end
		if best then
			return assemble(prev, best, nil), true
		end
		local w = relay(from, target)
		return w, w ~= nil
	end
end

-- Returns ok, reason. reason: 'nopath' (no walkable route exists from a good start),
-- 'wedged' (we were stuck in a nook; nudged out, try again), 'stuck' (route exists, got blocked).
-- On-foot speed. The game recomputes Humanoid.WalkSpeed every frame, but it honours a number in
-- the character's "EmoteWalkSpeed" attribute (stuns / roots still win). Only set while WE walk.
local function walkBoost(on)
	local c = LocalPlayer.Character
	if not c then
		return
	end
	local v = tonumber(settings.walkSpeed) or 0
	pcall(function()
		c:SetAttribute('EmoteWalkSpeed', (on and v > 0) and v or nil)
	end)
	-- Roblox makes a Humanoid "climb" stacked rubble / thin parts like a ladder, and while climbing
	-- a walk order only moves it up and down: it hangs there forever. No climbing while WE walk.
	pcall(function()
		local hum = c:FindFirstChildOfClass('Humanoid')
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, not on)
			if on and hum:GetState() == Enum.HumanoidStateType.Climbing then
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end
	end)
end

local function walkPathRaw(cf, opts)
	opts = opts or {}
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then
		return false, 'stuck'
	end
	local target = cf.Position
	local goals = { groundAt(target), target }
	for _, alt in ipairs(opts.alt or {}) do
		goals[#goals + 1] = groundAt(alt)
	end
	local function near()
		local d = target - hrp.Position
		if d.Magnitude <= 4 then
			return true
		end
		for _, g in ipairs(goals) do
			local dg = g - hrp.Position
			if Vector3.new(dg.X, 0, dg.Z).Magnitude <= 3 and math.abs(dg.Y) <= 6 then
				return true
			end
		end
		return false
	end
	local replans, partials = 0, 0
	while alive do
		local wps = computePath(hrp.Position, goals)
		local partial = false
		if not wps then
			-- (a spot close by with no direct route - a boulder up on a ledge: measured, 13 seconds
			-- went on the fallbacks below before giving up. The caller glides over instead.)
			if replans == 0 and partials == 0 and (target - hrp.Position).Magnitude < 150 then
				G.FTNavDbg = ('no direct path to a spot %.0f studs away'):format((target - hrp.Position).Magnitude)
				return false, 'nopath'
			end
			if replans == 0 and partials == 0 and not startOnMesh(hrp.Position) then
				unwedge()
				return false, 'wedged'
			end
			if partials < 5 then
				if opts.onRelay then
					pcall(opts.onRelay)
				end
				-- Planning is done in short bursts (finished pieces are remembered), so we can
				-- still react to a mob between them instead of standing there for 15s.
				for _ = 1, 3 do
					wps, partial = Nav.route(hrp.Position, goals, target)
					if wps or not alive or (opts.abort and opts.abort()) then
						break
					end
				end
				if not wps and opts.abort and opts.abort() then
					return true
				end
			end
			if not wps or #wps < 2 then
				G.FTNavDbg = ('no path from (%.0f,%.0f,%.0f) to (%.0f,%.0f,%.0f) replans=%d'):format(hrp.Position.X, hrp.Position.Y, hrp.Position.Z,
					target.X, target.Y, target.Z, replans)
				return false, replans > 0 and 'stuck' or 'nopath'
			end
			if partial then
				partials += 1
			end
		end
		local blocked = false
		local legStart = hrp.Position
		for i = 2, #wps do
			if not alive then
				return false, 'stuck'
			end
			if opts.abort and opts.abort() then
				return true
			end
			local wpt = wps[i]
			if type(wpt) == 'table' and wpt.Hop then
				-- a known ledge: hop it (only from right at its other end)
				if (hrp.Position - wps[i - 1].Position).Magnitude < 10 then
					hrp.CFrame = CFrame.new(wpt.Position)
					hrp.AssemblyLinearVelocity = Vector3.zero
					task.wait(0.3)
				else
					G.FTNavDbg = 'not at the ledge for the hop'
					blocked = true
					break
				end
				continue
			end
			if settings.glidePaths ~= false and (tonumber(settings.tweenSpeed) or 0) > (tonumber(settings.walkSpeed) or 0) then
				-- Glide along the route at tween speed instead of walking it at walk speed (3x faster).
				-- The route itself is walkable ground, so nothing gets clipped; ledges, rubble and
				-- jumps stop mattering.
				local goal = wpt.Position + Vector3.new(0, 3, 0)
				local lavaY = Lava.at(goal)
				if lavaY then
					goal = Vector3.new(goal.X, lavaY + 6, goal.Z) -- lava under this stretch: pass above it
				end
				local speed = math.max(10, tonumber(settings.tweenSpeed) or 55)
				if Door.hits(hrp.Position, goal, 6) then
					G.FTNavDbg = 'this route goes through the locked Red Cave door - not taken'
					return false, 'nopath'
				end
				noclip = true
				-- (v226: this loop used to run on after Unload - it never looked at `alive` - and a
				-- stretch it could never finish kept dragging the character about. Now it stops with
				-- the script, and gives a stretch up after 4 s without getting closer.)
				local bestD, bestAt = math.huge, os.clock()
				while true do
					local dt = task.wait()
					local _, h, hm = char()
					if not alive or not h or not hm or hm.Health <= 0 then
						noclip = false
						return false, 'stuck'
					end
					do
						local dNow = (goal - h.Position).Magnitude
						if dNow < bestD - 2 then
							bestD, bestAt = dNow, os.clock()
						elseif os.clock() - bestAt > 4 then
							noclip = false
							G.FTNavDbg = 'glide along the route made no headway for 4 s'
							return false, 'stuck'
						end
					end
					hrp, hum = h, hm
					if (opts.abort and opts.abort()) or near() then
						noclip = false
						hrp.AssemblyLinearVelocity = Vector3.zero
						return true
					end
					local to = goal - hrp.Position
					local step = speed * math.min(dt, 0.1)
					local pos = to.Magnitude <= step and goal or (hrp.Position + to.Unit * step)
					local flat = Vector3.new(to.X, 0, to.Z)
					hrp.CFrame = flat.Magnitude > 0.2 and CFrame.lookAt(pos, pos + flat) or (hrp.CFrame - hrp.CFrame.Position + pos)
					hrp.AssemblyLinearVelocity = Vector3.zero
					if pos == goal then
						break
					end
				end
				noclip = false
				Nav.crumb(hrp.Position, hum)
				continue
			end
			-- Ledge drops / climbs: a waypoint right below (or above) us is NOT reached until we are
			-- on its level. Walk them slowly (at boosted speed we'd fly far past the landing) and
			-- keep heading the same way until we've actually dropped.
			local prevPos = wps[i - 1].Position
			local rise = wpt.Position.Y - prevPos.Y
			local vertical = rise < -3.5 and wpt.Action ~= nil and wps[i - 1].Action ~= nil
			local heading = Vector3.new(wpt.Position.X - prevPos.X, 0, wpt.Position.Z - prevPos.Z)
			if heading.Magnitude < 0.5 and wps[i + 1] then
				heading = Vector3.new(wps[i + 1].Position.X - wpt.Position.X, 0, wps[i + 1].Position.Z - wpt.Position.Z)
			end
			heading = heading.Magnitude > 0.1 and heading.Unit or Vector3.zero
			local fast = tonumber(settings.walkSpeed) or 0
			if vertical and fast > 18 then
				pcall(function()
					LocalPlayer.Character:SetAttribute('EmoteWalkSpeed', 18)
				end)
			end
			local reachR = vertical and 2.5 or math.max(3.5, fast * 0.08)
			if wpt.Action == Enum.PathWaypointAction.Jump and not vertical then
				hum.Jump = true -- (no jump needed to step off a ledge)
			end
			hum:MoveTo(wpt.Position)
			local t0, last, lastAt, jumped = os.clock(), hrp.Position, os.clock(), false
			while true do
				task.wait() -- every frame: at boosted speed 0.1s is several studs
				local _, h, hm = char()
				if not alive or not h or not hm or hm.Health <= 0 then
					return false, 'stuck'
				end
				hrp, hum = h, hm
				if opts.abort and opts.abort() then
					return true
				end
				if near() then
					return true
				end
				local flat = Vector3.new(wpt.Position.X - hrp.Position.X, 0, wpt.Position.Z - hrp.Position.Z)
				local feetGap = (hrp.Position.Y - 3) - wpt.Position.Y
				if vertical then
					if feetGap <= 4 and flat.Magnitude < 8 then
						break -- landed on the waypoint's level (or fell past it: carry on from here)
					end
					if flat.Magnitude < reachR and feetGap > 4 then
						hum:MoveTo(hrp.Position + heading * 5 - Vector3.new(0, 3, 0)) -- still on the ledge: keep going over the edge
					end
				elseif flat.Magnitude < reachR then
					break
				end
				local now = os.clock()
				if (hrp.Position - last).Magnitude > 1 then
					last, lastAt, jumped = hrp.Position, now, false
				elseif now - lastAt > 0.8 and not jumped then
					jumped = true
					hum.Jump = true -- small ledge / rubble: hop it
					hum:MoveTo(wpt.Position)
				elseif now - lastAt > 2 then
					blocked = true
				elseif now - t0 > 8 then
					blocked = true
				end
				if blocked then
					G.FTNavDbg = ('blocked at (%.0f,%.0f,%.0f) heading for (%.0f,%.0f,%.0f)%s'):format(hrp.Position.X, hrp.Position.Y, hrp.Position.Z,
						wpt.Position.X, wpt.Position.Y, wpt.Position.Z, vertical and ' [ledge]' or '')
					break
				end
			end
			if vertical then
				walkBoost(true)
			end
			if blocked then
				break
			end
			Nav.crumb(hrp.Position, hum)
		end
		if not blocked then
			if near() or (target - hrp.Position).Magnitude <= 8 then
				return true
			end
			if not partial then
				G.FTNavDbg = ('path ended %.1f from the target (at %.0f,%.0f,%.0f, target %.0f,%.0f,%.0f, ground goal y=%.0f)'):format(
					(target - hrp.Position).Magnitude, hrp.Position.X, hrp.Position.Y, hrp.Position.Z, target.X, target.Y, target.Z, goals[1].Y)
				return false, 'stuck'
			end
			-- walked the relay leg: plan again from here
		else
			replans += 1
			if replans > 4 then
				return false, 'stuck'
			end
			if (hrp.Position - legStart).Magnitude < 4 then
				-- Didn't get anywhere at all: the body is clipped into a rock lip / mesh edge (hops
				-- and tweens can leave it there). Pop out onto the path a few studs ahead.
				for j = 2, #wps do
					local wp = wps[j].Position
					local gap = (wp - hrp.Position).Magnitude
					if gap >= 5 or j == #wps then
						if gap <= 30 then
							local spot = wps[j].Action ~= nil and (wp + Vector3.new(0, 3.5, 0)) or (wp + Vector3.new(0, 0.5, 0))
							hrp.CFrame = CFrame.new(spot)
							hrp.AssemblyLinearVelocity = Vector3.zero
							G.FTNavDbg = ('was clipped into the map at (%.0f,%.0f,%.0f) — popped out'):format(legStart.X, legStart.Y, legStart.Z)
							task.wait(0.3)
						end
						break
					end
				end
			end
		end
	end
	return false, 'stuck'
end

local function walkPath(cf, opts)
	walkBoost(true)
	local ok, a, b = pcall(walkPathRaw, cf, opts)
	noclip = false
	walkBoost(false)
	if not ok then
		warn('[ForgeTools] walkPath: ' .. tostring(a))
		G.FTNavDbg = 'walk error: ' .. tostring(a)
		return false, 'stuck'
	end
	return a, b
end

-- Steer to a target on foot (collisions ON), like a player walking. Reaches cave ore the
-- pathfinder can't map, without ever clipping a wall (so no spawn reset). Stops if stuck.
local function walkDirect(cf, opts)
	opts = opts or {}
	walkBoost(true)
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	local target = cf.Position
	local bind = 'FTWalkDirect'
	pcall(function() RunService:UnbindFromRenderStep(bind) end)
	RunService:BindToRenderStep(bind, 2000, function()
		local _, h = char()
		if not h then return end
		local flat = Vector3.new(target.X - h.Position.X, 0, target.Z - h.Position.Z)
		if flat.Magnitude > 2 then
			LocalPlayer:Move(flat.Unit, false)
		end
	end)
	local t0, last, lastAt, reached = os.clock(), hrp.Position, os.clock(), false
	while os.clock() - t0 < 30 do
		task.wait(0.1)
		local _, h = char()
		if not h or not alive then
			break
		end
		hrp = h
		if opts.abort and opts.abort() then
			reached = true
			break
		end
		if (target - hrp.Position).Magnitude <= 10 then
			reached = true
			break
		end
		local now = os.clock()
		if (hrp.Position - last).Magnitude > 1.5 then
			last, lastAt = hrp.Position, now
		elseif now - lastAt > 2.5 then
			break -- stuck against a wall; give up rather than clip through it
		end
	end
	pcall(function() RunService:UnbindFromRenderStep(bind) end)
	pcall(function() LocalPlayer:Move(Vector3.zero, false) end)
	walkBoost(false)
	return reached
end

local function tweenToRaw(cf, opts)
	opts = opts or {}
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	if typeof(cf) == 'Vector3' then
		cf = CFrame.new(cf)
	end
	local dist = (cf.Position - hrp.Position).Magnitude
	if dist < 1.5 then
		hrp.CFrame = cf
		return true
	end
	do
		local origin = hrp.Position
		local to = cf.Position - origin
		if to.Magnitude > 6 then
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { LocalPlayer.Character }
			local hit = workspace:Raycast(origin, to, rp)
			if hit and (hit.Position - origin).Magnitude < to.Magnitude - 4 then
				-- wall in the way: walk around it (pathfind) or steer in on foot (caves); never clip
				local okw, why = walkPath(cf, opts)
				if okw then
					return true
				end
				-- Straight-line steering only helps for short hops the pathfinder can't map;
				-- over distance it just grinds into the wall and wedges us in a corner.
				if why == 'nopath' and to.Magnitude <= 40 and math.abs(to.Y) <= 10 and walkDirect(cf, opts) then
					return true
				end
				return false, why
			end
		end
	end
	if Door.hits(hrp.Position, cf.Position, 6) then
		G.FTNavDbg = 'straight move would cross the locked Red Cave door - not taken'
		return false, 'nopath'
	end
	stopTween()
	noclip = true
	local speed = math.max(10, tonumber(settings.tweenSpeed) or 55)
	local tw = TweenService:Create(hrp, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), { CFrame = cf })
	currentTween = tw
	local hold = RunService.Heartbeat:Connect(function()
		if hrp.Parent then
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end)
	tw:Play()
	local done = false
	local c2 = tw.Completed:Connect(function()
		done = true
	end)
	local deadline = os.clock() + dist / speed + 3
	local calledOff = false
	while not done and alive and os.clock() < deadline do
		if opts.abort and opts.abort() then
			calledOff = true
			break
		end
		task.wait()
	end
	c2:Disconnect()
	hold:Disconnect()
	if not done then
		pcall(function()
			tw:Cancel()
		end)
	end
	currentTween = nil
	noclip = false
	if calledOff then
		return true -- (same as the walking route: the caller asked us to stop)
	end
	if not done then
		G.FTNavDbg = ('straight move cut off %.1f from the target'):format((cf.Position - hrp.Position).Magnitude)
	end
	return done
end

-- While we are on our way somewhere, G.FTTravel is where to. Dodges read it: a step away from a mob
-- that is ahead of us used to throw us 16-30 studs back down the route, again and again.
local setStatus -- (defined further down; Nav.fly, Nav.cross and Nav.escape report through it)
-- No route on foot: glide. Up 40 studs above the higher of the two ends, across, and down onto the
-- spot, with collisions off (ledges, ladders, cave roofs and pockets like island 4's Spirit Cave
-- stop mattering). Given up if a fifth of our health goes on the way. The user's call: "dont bother
-- with ladders just make it glide up".
function Nav.fly(dest, opts, first)
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	local from = hrp.Position
	local alt = math.max(from.Y, dest.Y) + 40
	if Door.inPoint(dest, 0) then
		G.FTNavDbg = 'that spot is inside the locked Red Cave - not going'
		return false
	end
	do
		-- (island 3: a glide whose line passes over the locked Red Cave goes above its plates)
		local lowA, lowB = Vector3.new(from.X, -1e4, from.Z), Vector3.new(dest.X, -1e4, dest.Z)
		local crosses, top = Door.hits(lowA, lowB, 10)
		if crosses and alt < top + 15 then
			alt = top + 15
		end
	end
	local legs = { Vector3.new(from.X, alt, from.Z), Vector3.new(dest.X, alt, dest.Z), dest }
	local hp0 = hum.Health
	local speed = math.clamp(tonumber(settings.tweenSpeed) or 55, 30, 70)
	-- (v188, the user's call after a measured test: 1,000 studs at 300 studs/s held, 600 held once,
	-- 1,000 studs/s got the account kicked. So 300, and only for the really long trips - the many
	-- 300-500 stud moves inside one area stay at the old speed, in case it is the number of fast
	-- trips that the game counts.)
	if (dest - from).Magnitude > 500 then
		speed = math.clamp(tonumber(settings.glideSpeed) or 90, speed, 120) -- (v189: 300 got the account kicked on its first real trip; 90 is the user's one careful step up from 66)
	end
	G.FTFlySpeed = speed
	if setStatus then
		setStatus(((first and 'long trip' or 'no route on foot') .. ' — gliding over (%.0f studs)'):format((dest - from).Magnitude))
	end
	stopTween()
	noclip = true
	local calledOff = false
	local okRun, done = pcall(function()
		for _, goal in ipairs(legs) do
			-- (v225: a leg that gets no closer for 4 s is given up. Measured on island 3: something
			-- kept moving us off the end point next to an orc and this loop ran for 8 minutes.)
			local bestD, bestAt = math.huge, os.clock()
			while true do
				local dt = task.wait()
				local _, h, hm = char()
				if not alive or not h or not hm or hm.Health <= 0 or hm.Health < hp0 * 0.8 then
					return false
				end
				do
					local dNow = (goal - h.Position).Magnitude
					if dNow < bestD - 2 then
						bestD, bestAt = dNow, os.clock()
					elseif os.clock() - bestAt > 4 then
						G.FTFlyStall = (G.FTFlyStall or 0) + 1
						return false
					end
				end
				if opts and opts.abort and opts.abort() then
					-- called off in the air: set down on the ground below, not dropped from 40 studs up
					local rp = RaycastParams.new()
					rp.FilterType = Enum.RaycastFilterType.Exclude
					rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living') }
					local hit = workspace:Raycast(h.Position, Vector3.new(0, -400, 0), rp)
					if hit then
						h.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3.5, 0))
					end
					h.AssemblyLinearVelocity = Vector3.zero
					calledOff = true
					return true
				end
				local to = goal - h.Position
				local step = speed * math.min(dt, 0.1)
				if to.Magnitude <= step then
					h.CFrame = CFrame.new(goal)
					h.AssemblyLinearVelocity = Vector3.zero
					break
				end
				h.CFrame = CFrame.new(h.Position + to.Unit * step)
				h.AssemblyLinearVelocity = Vector3.zero
			end
		end
		return true
	end)
	noclip = false
	local _, h2 = char()
	if h2 then
		h2.AssemblyLinearVelocity = Vector3.zero
	end
	G.FTFlyDbg = ('%s fly ended: %s %s (legs %d)'):format(os.date('%H:%M:%S'), tostring(okRun), tostring(done), #legs)
	return okRun and done == true, calledOff
end

-- The game's own fast travel (v182). Measured: WaypointService:RequestTeleport(name) is free for an
-- unlocked waypoint, but answers false unless you stand at a waypoint stone (the game's menu shuts
-- 20 studs from one). So a long trip becomes: glide to the nearest unlocked stone, teleport to the
-- stone nearest the destination, glide the rest - when that is well under the direct distance.
function Nav.waypoints()
	local wf = workspace:FindFirstChild('Waypoints')
	local okd, d = pcall(data)
	local un = okd and type(d) == 'table' and d.WaypointsUnlocked or nil
	local out = {}
	for _, w in ipairs(wf and wf:GetChildren() or {}) do
		local open = w.Name == 'Town Hall' or w.Name == 'Village'
		for _, t in pairs(type(un) == 'table' and un or {}) do
			if type(t) == 'table' and t[w.Name] then
				open = true
			end
		end
		local okp, pos = pcall(function()
			return w:IsA('BasePart') and w.Position or w:GetPivot().Position
		end)
		if okp then
			out[#out + 1] = { name = w.Name, pos = pos, model = w, open = open }
		end
	end
	return out
end
-- (measured: the server only answers a waypoint call after the stone's own prompt was triggered)
function Nav.touchStone(w)
	pcall(function()
		local pr = w.model:FindFirstChildWhichIsA('ProximityPrompt', true)
		if pr and fireproximityprompt then
			fireproximityprompt(pr)
		end
	end)
	task.wait(0.6)
end
function Nav.closeStoneMenu()
	pcall(function()
		controller('UIController'):Close(true)
	end)
end
-- Locked stones are bought from wherever we are (v184). Measured: WaypointService:RequestUnlock
-- ('Raids') from 1,382 studs away answered true, the stone was unlocked and 15,000 gold was taken -
-- the same as unlocking from the game's map. One-time gold price from the game's own table.
function Nav.unlockNear()
	if os.clock() - (Nav.unlockAt or -1e9) < 30 then
		return
	end
	Nav.unlockAt = os.clock()
	local okd, d = pcall(data)
	if not okd or type(d) ~= 'table' then
		return
	end
	if Nav.wpPrices == nil then
		Nav.wpPrices = false
		pcall(function()
			Nav.wpPrices = require(RS.Shared.Data.Waypoints).Prices
		end)
	end
	Nav.unlockBad = Nav.unlockBad or {}
	for _, w in ipairs(Nav.waypoints()) do
		local price = type(Nav.wpPrices) == 'table' and tonumber(Nav.wpPrices[w.name]) or nil
		if not w.open and price and (tonumber(d.Gold) or 0) >= price and os.clock() > (Nav.unlockBad[w.name] or 0) then
			Nav.unlockBad[w.name] = os.clock() + 600
			local okU, a = pcall(function()
				return service('WaypointService'):RequestUnlock(w.name):await()
			end)
			G.FTUnlockLast = ('%s %s for %d gold: ok=%s %s'):format(os.date('%H:%M:%S'), w.name, price, tostring(okU), tostring(a))
			if setStatus then
				setStatus(('fast travel: unlocked the %s waypoint (%d gold)'):format(w.name, price))
			end
			task.wait(0.5)
		end
	end
end
local tweenToFwd
function Nav.hop(dest, opts)
	local _, hrp = char()
	if not hrp or os.clock() < (Nav.hopBad or 0) then
		return false
	end
	local direct = (dest - hrp.Position).Magnitude
	if direct < 350 then
		return false
	end
	local near, nearD, far, farD
	for _, w in ipairs(Nav.waypoints()) do
		local d1, d2 = (w.pos - hrp.Position).Magnitude, (w.pos - dest).Magnitude
		if w.open and (not nearD or d1 < nearD) then
			near, nearD = w, d1
		end
		if w.open and (not farD or d2 < farD) then
			far, farD = w, d2
		end
	end
	if not near or near == far or nearD + farD > direct * 0.6 then
		return false
	end
	if setStatus then
		setStatus(('fast travel: to the %s waypoint (%.0f studs), then %s'):format(near.name, nearD, far.name))
	end
	if nearD > 10 then
		local okT = tweenToFwd(CFrame.new(near.pos + Vector3.new(0, 3, 5)), { abort = opts and opts.abort, noHop = true })
		if not okT then
			Nav.hopBad = os.clock() + 120
			return false
		end
	end
	local okC, a, b
	local tries = 0
	for i = 1, 3 do
		tries = i
		Nav.touchStone(near)
		okC, a, b = pcall(function()
			return service('WaypointService'):RequestTeleport(far.name):await()
		end)
		if not (okC and a == true and b == false) or not alive then
			break
		end
		task.wait(0.8)
	end
	Nav.closeStoneMenu()
	G.FTHopLast = ('%s %s -> %s: ok=%s %s %s (try %d)'):format(os.date('%H:%M:%S'), near.name, far.name, tostring(okC), tostring(a), tostring(b), tries)
	if okC and a == true and b == false then
		Nav.hopBad = os.clock() + 300 -- (refused three times: no point waiting 8 s for an arrival)
		return false
	end
	local t0 = os.clock()
	while alive and os.clock() - t0 < 8 do
		local _, h = char()
		if h and (h.Position - far.pos).Magnitude < 60 then
			task.wait(0.4) -- (the arrival effect; v324: was 1 s)
			G.FTHops = (G.FTHops or 0) + 1
			return true
		end
		task.wait(0.2)
	end
	Nav.hopBad = os.clock() + 300 -- (refused: plain travel for the next 5 minutes)
	return false
end

local function tweenTo(cf, opts)
	local trip = { dest = typeof(cf) == 'CFrame' and cf.Position or cf }
	if workspace:GetAttribute('AbyssRun') == true and not G.FTAbyssBack then
		-- (v251, seen live: in an Abyss run it set off on a 6,732 stud glide out over the void, 6,000
		-- studs past its floor. A floor is a few hundred studs across; the game moves us between
		-- floors itself. No trip longer than that is ever right in there.)
		local _, hA = char()
		if hA and (trip.dest - hA.Position).Magnitude > 800 then
			G.FTNavDbg = ('abyss: refused a %.0f stud trip'):format((trip.dest - hA.Position).Magnitude)
			G.FTAbyssRefused = (G.FTAbyssRefused or 0) + 1
			task.wait(0.3)
			return false
		end
	end
	if Door.inPoint(trip.dest, 0) then
		G.FTNavDbg = 'that spot is inside the locked Red Cave - not going'
		G.FTDoorRefused = (G.FTDoorRefused or 0) + 1
		return false
	end
	if not (opts and opts.noHop) then
		pcall(Nav.unlockNear, opts)
		-- (v187: waypoint hops are off unless settings.useWaypoints is set by hand. The user wants a
		-- straight trip; the long glide below does 1,000 studs in about 16 s; and measured: a stone
		-- refuses a teleport asked for in the first seconds after arriving at it.)
		if settings.useWaypoints == true then
			local okH, hopped = pcall(Nav.hop, trip.dest, opts)
			trip.hopped = okH and hopped == true
		end
	end
	G.FTTrips = G.FTTrips or {}
	table.insert(G.FTTrips, trip)
	G.FTTravel = trip.dest
	-- A long trip is glided over in one go (v187). Measured on the way from town to the Oni cave,
	-- 935 studs: the walk planner went by known spots to (473,81,38), found no path on from there,
	-- and only then glided - 54 s in all, 12-18 of them standing still. The glide alone, at the
	-- same speed, is about 16 s.
	local ok, a, b
	do
		local _, hf0 = char()
		-- (v221, the user on island 3: "going through too many walls seems to backtrack you back to the
		-- spawn ... just walk through the areas like you did before". Measured there: 340 studs glided,
		-- 330 snapped back, over and over for 4 minutes. So no first-choice glide on island 3.)
		-- (v324, the user: "when using waypoint warp after its teleported, theres a delay before it paths to
		-- the next location". Measured: Holy Tree stone -> Spirit Cave, 260 studs across and 160 down - the
		-- walk planner found no direct path, then planned "via known spots" in bursts: 36 s from the warp to
		-- the rock. Right after a warp, anything over 100 studs is glided in one go.)
		local farAfterHop = trip.hopped and hf0 and (trip.dest - hf0.Position).Magnitude > 100
		if hf0 and (farAfterHop or (trip.dest - hf0.Position).Magnitude > 300 or Door.hits(hf0.Position, trip.dest, 8)) and not (opts and opts.noFly) then
			Nav.flyAt = os.clock()
			local okF, res, off = pcall(Nav.fly, trip.dest, opts, true)
			G.FTFlyLast = ('%s first-choice glide: %s %s'):format(os.date('%H:%M:%S'), tostring(okF), tostring(res))
			if okF and res then
				ok, a, b = true, true, nil
			end
		end
	end
	if ok == nil then
		ok, a, b = pcall(tweenToRaw, cf, opts)
	end
	if ok and a == false and alive and not (opts and opts.abort and opts.abort()) then
		local _, hf = char()
		if hf and (trip.dest - hf.Position).Magnitude > 25 and os.clock() - (Nav.flyAt or -1e9) > 3 then
			Nav.flyAt = os.clock()
			local okF, res = pcall(Nav.fly, trip.dest)
			if okF and res then
				a, b = true, nil
			end
		end
	end
	local at = table.find(G.FTTrips, trip)
	if at then
		table.remove(G.FTTrips, at)
	end
	-- (back to the trip this one was a leg of, if any; never to one that has already ended)
	G.FTTravel = G.FTTrips[1] and G.FTTrips[1].dest or nil
	if not ok then
		error(a, 0)
	end
	return a, b
end
tweenToFwd = tweenTo

-- (v316, the user in the Abyss: "gotta be careful of these go below the ramp". Measured: a Chuthlu
-- 8 studs below us under a plank ramp, 4 studs across; the spot on our side was inside the ramp, the
-- game pushed us up onto it and every swing hit the planks - its health did not move in 11 s. A spot
-- now needs a clear line to the mob and a floor under it at the mob's height; if ours has neither,
-- the nearest of 8 spots around the mob that does is used.)
local standRp = RaycastParams.new()
standRp.FilterType = Enum.RaycastFilterType.Exclude
standRp.RespectCanCollide = true
local function standClear(p, pos)
	standRp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
	if workspace:Raycast(p, pos - p, standRp) then
		return false -- (a wall / ramp between the mob and the spot)
	end
	local fl = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -9, 0), standRp)
	return fl ~= nil
end
local function standNear(part, gap)
	local _, hrp = char()
	local p = part.Position
	local dir = hrp and ((hrp.Position - p) * Vector3.new(1, 0, 1)) or Vector3.new(1, 0, 0)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
	local r = math.max(part.Size.X, part.Size.Z) / 2 + (gap or 2)
	local pos = p + dir * r
	local okC, clear = pcall(standClear, p, pos)
	if okC and not clear then
		local best, bd
		local base = math.atan2(dir.Z, dir.X)
		for i = 1, 7 do
			local a = base + (math.ceil(i / 2) * (i % 2 == 0 and -1 or 1)) * math.pi / 4
			local c = p + Vector3.new(math.cos(a), 0, math.sin(a)) * r
			local okS, cl = pcall(standClear, p, c)
			if okS and cl then
				local d = hrp and (c - hrp.Position).Magnitude or 0
				if not bd or d < bd then
					best, bd = c, d
				end
			end
		end
		if best then
			pos = best
			G.FTStandMoved = (G.FTStandMoved or 0) + 1
		end
	end
	return CFrame.lookAt(pos, Vector3.new(p.X, pos.Y, p.Z))
end

-- The long way round. Some areas are pockets: island 4's Spirit Cave only connects to the rest of
-- the island through the water around it, a 2,200 stud route that the normal planner (which checks
-- every step and works in short hops between known spots) never comes up with. The game's own
-- pathfinder does find it in one go. Measured by hand: gliding that route at 60 studs/s with
-- collisions off took 30 seconds and cost no health; with collisions ON the glide jammed against
-- the cave mouth. So: one whole-route plan to a spot next to the rock, glided with collisions off,
-- given up if a fifth of our health goes on the way. Only used for a rock 300+ studs away that
-- the normal planner has just failed on.
function Nav.cross(hb, label)
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 or not hb or not hb.Parent then
		return false
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Rocks') }
	rp.RespectCanCollide = true
	local wps
	local half = math.max(hb.Size.X, hb.Size.Z) / 2 + 4
	for a = 0, 270, 90 do
		local p = hb.Position + Vector3.new(math.cos(math.rad(a)), 0, math.sin(math.rad(a))) * half
		local r = workspace:Raycast(p + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), rp)
		if r then
			local goal = r.Position + Vector3.new(0, 3, 0)
			local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
			local okc = pcall(function()
				path:ComputeAsync(hrp.Position, goal)
			end)
			if okc and path.Status == Enum.PathStatus.Success then
				local w = path:GetWaypoints()
				local gap = #w >= 2 and (w[#w].Position - goal) or nil
				local good = gap and math.abs(gap.Y) <= 7 and Vector3.new(gap.X, 0, gap.Z).Magnitude <= 7
				if good then
					for i = 2, #w do
						local st = w[i].Position - w[i - 1].Position
						if st.Y > 5 and Vector3.new(st.X, 0, st.Z).Magnitude < st.Y * 0.8 then
							good = false -- (a "jump" up a wall: not a route)
							break
						end
					end
				end
				if good then
					wps = w
					break
				end
			end
		end
		if not alive then
			return false
		end
	end
	if not wps then
		return false
	end
	local len = 0
	for i = 2, #wps do
		len += (wps[i].Position - wps[i - 1].Position).Magnitude
	end
	setStatus(('taking the long way round to %s (%.0f studs)'):format(label or 'the rock', len))
	local hp0 = hum.Health
	local speed = math.clamp(tonumber(settings.tweenSpeed) or 55, 30, 70)
	stopTween()
	noclip = true
	local okRun, done = pcall(function()
		for i = 2, #wps do
			local goal = wps[i].Position + Vector3.new(0, 3.5, 0)
			do
				local _, hd = char()
				if hd and Door.hits(hd.Position, goal, 6) then
					return false -- (island 3: never through the locked Red Cave door)
				end
			end
			while true do
				local dt = task.wait()
				local _, h, hm = char()
				if not alive or not h or not hm or hm.Health <= 0 or hm.Health < hp0 * 0.8 then
					return false
				end
				local to = goal - h.Position
				local step = speed * math.min(dt, 0.1)
				if to.Magnitude <= step then
					h.CFrame = CFrame.new(goal)
					h.AssemblyLinearVelocity = Vector3.zero
					break
				end
				h.CFrame = CFrame.new(h.Position + to.Unit * step)
				h.AssemblyLinearVelocity = Vector3.zero
			end
		end
		return true
	end)
	noclip = false
	local _, h2 = char()
	if h2 then
		h2.AssemblyLinearVelocity = Vector3.zero
	end
	if not (okRun and done) then
		setStatus('the long way round was cut short (health dropped or the character was lost)')
	end
	return okRun and done == true
end

-- Stranded. Some places have no walkable way out for the pathfinder (measured on island 3: the
-- sand below an altar - the way up is a ledge too high for its jump and a path too narrow for it;
-- every rock on the island came back "no route" from there, forever). The way out a player would
-- take is "up and over", so: rise straight up through open air, cross to above the nearest spot
-- we know we can walk from, and come down on it. Only clear air is crossed, never a wall.
function Nav.escape()
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 or os.clock() - (Nav.escapeAt or -1e9) < 45 then
		return false
	end
	Nav.escapeAt = os.clock()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
	local me = hrp.Position
	local nodes = {}
	for _, n in ipairs(Nav.nodes) do
		local d = (n - me).Magnitude
		if d > 15 then
			nodes[#nodes + 1] = { n = n, d = d }
		end
	end
	table.sort(nodes, function(a, b)
		return a.d < b.d
	end)
	local function clear(a, b)
		-- (the body is about 4 studs wide: the line and one either side of it)
		local side = (b - a):Cross(Vector3.yAxis)
		side = side.Magnitude > 0.1 and side.Unit * 2 or Vector3.new(2, 0, 0)
		return not workspace:Raycast(a, b - a, rp) and not workspace:Raycast(a + side, b - a, rp)
			and not workspace:Raycast(a - side, b - a, rp)
	end
	for _, lift in ipairs({ 10, 20, 35, 55, 90, 140 }) do
		if workspace:Raycast(me, Vector3.new(0, lift + 4, 0), rp) then
			break -- a roof: no higher than this
		end
		for i = 1, math.min(#nodes, 20) do
			local n = nodes[i].n
			if n.Y + 8 <= me.Y + lift then
				local alt = me.Y + lift
				local top = Vector3.new(me.X, alt, me.Z)
				local over = Vector3.new(n.X, alt, n.Z)
				local land = n + Vector3.new(0, 1, 0)
				if clear(top, over) and clear(over, land) then
					setStatus(('no way out on foot from here — going up and over to a known spot (%.0f studs)'):format(nodes[i].d))
					local function leg(pos)
						local _, h = char()
						if not h then
							return false
						end
						stopTween()
						noclip = true
						local dist = (pos - h.Position).Magnitude
						local speed = math.max(10, tonumber(settings.tweenSpeed) or 55)
						local tw = TweenService:Create(h, TweenInfo.new(dist / speed, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos) })
						currentTween = tw
						local hold = RunService.Heartbeat:Connect(function()
							if h.Parent then
								h.AssemblyLinearVelocity = Vector3.zero
							end
						end)
						tw:Play()
						local deadline = os.clock() + dist / speed + 2
						while alive and os.clock() < deadline and (h.Position - pos).Magnitude > 1 do
							task.wait()
						end
						hold:Disconnect()
						pcall(function()
							tw:Cancel()
						end)
						currentTween = nil
						noclip = false
						return (h.Position - pos).Magnitude <= 3
					end
					local ok = leg(top) and leg(over) and leg(land)
					G.FTEscapes = (G.FTEscapes or 0) + (ok and 1 or 0)
					return ok
				end
			end
		end
	end
	setStatus('no way out on foot from here, and no clear way over either')
	return false
end

local function equip(toolName)
	local c, _, hum = char()
	if not c or not hum then
		return nil
	end
	local held = c:FindFirstChildWhichIsA('Tool')
	if held and held.Name == toolName then
		return held
	end
	local t = LocalPlayer.Backpack:FindFirstChild(toolName)
	if not t then
		return nil
	end
	hum:EquipTool(t)
	task.wait(0.3)
	return c:FindFirstChild(toolName)
end

local function swing(tool)
	local TC = controller('ToolController')
	if TC and tool then
		task.spawn(function()
			pcall(function()
				TC:ToolActivated(tool)
			end)
		end)
	end
end

---------------------------------------------------------------------------
-- Inventory helpers
---------------------------------------------------------------------------
local function oreCounts()
	local d = data()
	local out, total = {}, 0
	if not d or type(d.Inventory) ~= 'table' then
		return out, 0
	end
	local reserve = type(G.FTReserve) == 'table' and G.FTReserve or {}
	for k, v in pairs(d.Inventory) do
		if ORE_NAMES[k] and type(v) == 'number' and v > 0
			and not (type(settings.keepOres) == 'table' and settings.keepOres[k]) then
			-- Ores a quest needs delivered ("Bring Monke 30 bananite") are kept out of forging / selling.
			local n = v - (tonumber(reserve[k]) or 0)
			if n > 0 then
				out[k] = n
				total += n
			end
		end
	end
	return out, total
end

-- What the forge may use: everything oreCounts allows, narrowed to "Ores to use" when any are picked.
local function forgeCounts()
	local all, total = oreCounts()
	local only = type(settings.forgeOnlyOres) == 'table' and next(settings.forgeOnlyOres) and settings.forgeOnlyOres or nil
	if not only then
		return all, total
	end
	local out, n = {}, 0
	for k, v in pairs(all) do
		if only[k] then
			out[k] = v
			n += v
		end
	end
	return out, n
end

local function bagCapacity()
	-- The game's own numbers for the ore / material bag ("Stash"). (The "Capacity (3/39)" label
	-- on the hotbar is the EQUIPMENT bag - reading that one made auto sell never trigger.)
	local used, cap
	pcall(function()
		local inv = controller('UIController').Modules.Inventory
		cap = tonumber(inv:GetBagCapacity())
		used = tonumber(inv:CalculateTotal('Stash'))
	end)
	if not (used and cap and cap > 0) then
		return nil, nil
	end
	return used, cap
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
local _statusText = 'idle'
local statusLabel
local statusLog = {}
local lastProgress = os.clock()
setStatus = function(t)
	if t ~= _statusText then
		lastProgress = os.clock()
		statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. tostring(t)
		if #statusLog > 300 then
			table.remove(statusLog, 1)
		end
	end
	_statusText = t
	G.FTStatus = t
	if statusLabel and statusLabel.SetText then
		pcall(statusLabel.SetText, statusLabel, 'Status: ' .. t)
	end
end
local stats = { mined = 0, sold = 0, forged = 0, kills = 0 }

---------------------------------------------------------------------------
-- Mining
---------------------------------------------------------------------------
local tooStrong = {} -- rock type name -> true (pickaxe did no damage)
G.FTTooStrong = tooStrong
-- Rock kinds we have damaged before can not be "too strong" (measured: Glowy Rock, 14 already mined
-- for a quest, was written off after three swings that missed from a ledge - and the quest with it).
local canBreak = G.FTCanBreak or {}
G.FTCanBreak = canBreak
-- Rocks carry a RequiredDamage attribute. When the game says "You need to deal at least N base
-- damage to mine this rock!", every rock type needing N or more is out of reach for this pickaxe:
-- skip them all at once instead of waiting out 3 no-damage rocks. Cleared when the pickaxe changes.
local ReqDmg = { limit = nil, added = {}, pick = nil }
G.FTReqDmg = ReqDmg
function ReqDmg.pickName()
	return LocalPlayer:GetAttribute('GolemPickaxe')
end
function ReqDmg.reset()
	for name in pairs(ReqDmg.added) do
		tooStrong[name] = nil
	end
	table.clear(ReqDmg.added)
	ReqDmg.limit = nil
	ReqDmg.pick = ReqDmg.pickName()
end
function ReqDmg.learn(n)
	if ReqDmg.pick ~= ReqDmg.pickName() then
		ReqDmg.reset()
	end
	if ReqDmg.limit and ReqDmg.limit <= n then
		return
	end
	ReqDmg.limit = n
	local rocks = workspace:FindFirstChild('Rocks')
	local names = {}
	for _, d in ipairs(rocks and rocks:GetDescendants() or {}) do
		if d:IsA('Model') then
			local req = d:GetAttribute('RequiredDamage')
			if type(req) == 'number' and req >= n and not tooStrong[d.Name] then
				tooStrong[d.Name] = true
				ReqDmg.added[d.Name] = true
				names[#names + 1] = d.Name
			end
		end
	end
	if setStatus and #names > 0 then
		pcall(setStatus, ('pickaxe can\'t mine rocks needing %d+ damage — skipping %s'):format(n, table.concat(names, ', ')))
	end
end
-- (a rock type whose RequiredDamage is already known to be too much, seen after learning)
function ReqDmg.blocks(m)
	local req = ReqDmg.limit and m:GetAttribute('RequiredDamage')
	return type(req) == 'number' and req >= ReqDmg.limit
end
do
	if G.FTReqDmgConn then
		pcall(function()
			G.FTReqDmgConn:Disconnect()
		end)
	end
	local function check(lbl)
		local txt = tostring(lbl.Text or '')
		local n = txt:match('deal at least (%d+) base damage')
		if n then
			ReqDmg.learn(tonumber(n))
		end
	end
	local pg = LocalPlayer:WaitForChild('PlayerGui', 10)
	if pg then
		G.FTReqDmgConn = pg.DescendantAdded:Connect(function(d)
			if d:IsA('TextLabel') then
				task.defer(function()
					pcall(check, d)
					pcall(function()
						local c
						c = d:GetPropertyChangedSignal('Text'):Connect(function()
							if not d.Parent then
								c:Disconnect()
								return
							end
							pcall(check, d)
						end)
						task.delay(10, function()
							c:Disconnect()
						end)
					end)
				end)
			end
		end)
	end
	pcall(function()
		track(LocalPlayer:GetAttributeChangedSignal('GolemPickaxe'):Connect(function()
			ReqDmg.reset()
		end))
	end)
end
local noDamage = {} -- rock type name -> rocks in a row that took no damage
local unreachable = setmetatable({}, { __mode = 'k' }) -- rock Model -> os.clock() until which we skip it
local unreachFails = setmetatable({}, { __mode = 'k' }) -- rock Model -> times we failed to get to it
local zoneNoPath = {} -- zone name -> { n = rocks with no walkable route, at = last time }
local zoneBlocked = {} -- zone name -> os.clock() until which the whole zone is skipped (walled off from here)
local MineHooks = {} -- .clear(pos) is filled in by the mob code: kill mobs around a rock first

-- Living mobs within radius of a position: count, list.
-- Mobs to leave alone altogether (the user's call: "ignore spirit golem mob they take too long to
-- kill, if its for mining then focus on mining if they are nearby" / "same for hellbringer").
-- Never picked as a fight, and invisible to the mining safety checks: no clearing them first, no
-- fighting back, no moving off. Their attacks are still dodged like any other mob's if they turn
-- out to be a real threat.
local IGNORE_MOBS = {} -- (v216, the user: "dont skip no more mobs"; was spirit golem + hellbringer)
local function mobIgnored(m)
	local n = string.lower(m.Name)
	for _, k in ipairs(IGNORE_MOBS) do
		if string.find(n, k, 1, true) then
			return true
		end
	end
	return false
end
local function mobsNear(pos, radius)
	local living = workspace:FindFirstChild('Living')
	local list = {}
	if not living then
		return 0, list
	end
	for _, m in ipairs(living:GetChildren()) do
		if m:GetAttribute('IsNpc') and not Players:GetPlayerFromCharacter(m) and not mobIgnored(m) then
			local h = m:FindFirstChildOfClass('Humanoid')
			local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
			if h and r and h.Health > 0 then
				local d = (r.Position - pos).Magnitude
				if d <= radius then
					list[#list + 1] = { m = m, h = h, r = r, d = d }
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	return #list, list
end

-- Mobs that have killed us (or took ~half our health in one hit) are "deadly": never fought,
-- never mined next to, and run from as soon as they come anywhere near. Remembered per game.
local Deadly = { names = {}, RANGE = 40 }
do
	local path = 'PlayerTools/forgetools_deadly_' .. tostring(game.PlaceId) .. '.json'
	pcall(function()
		if isfile(path) then
			for _, n in ipairs(HttpService:JSONDecode(readfile(path))) do
				Deadly.names[n] = true
			end
		end
	end)
	local function saveDeadly()
		local list = {}
		for n in pairs(Deadly.names) do
			list[#list + 1] = n
		end
		table.sort(list)
		pcall(writefile, path, HttpService:JSONEncode(list))
	end
	local function kind(m)
		return (string.gsub(m.Name, '%d+$', ''))
	end
	function Deadly.is(m)
		do
			return false -- (v246: no mob is left alone for having killed us)
		end
		return settings.fleeDeadly ~= false and Deadly.names[kind(m)] == true
	end
	function Deadly.list()
		local list = {}
		for n in pairs(Deadly.names) do
			list[#list + 1] = n
		end
		table.sort(list)
		return list
	end
	function Deadly.clear()
		table.clear(Deadly.names)
		saveDeadly()
	end
	-- nearest deadly mob within `radius` of pos (or nil)
	function Deadly.near(pos, radius)
		radius = radius or Deadly.RANGE
		local listed = settings.fleeDeadly ~= false and next(Deadly.names) ~= nil
		local _, list = mobsNear(pos, radius + 15)
		for _, e in ipairs(list) do
			local d = (e.r.Position - pos).Magnitude
			if (listed and d <= radius and Deadly.names[kind(e.m)]) or Deadly.big(e.h) then
				return e
			end
		end
		return nil
	end
	-- A mini boss (more than 12x our own health - island 3 on a 342 hp character: Prismarine Spider
	-- 7000, Yeti 11000): wide slams with no warning and shots from range. While mining these are
	-- kept away from like a mob that has killed us - and from 15 studs further out - whether or not
	-- "Avoid mobs that killed me" is on.
	function Deadly.big(h)
		do
			return false -- (v246)
		end
		local _, _, hum = char()
		if hum == nil or h == nil or h.MaxHealth >= 1e8 then
			return false
		end
		if h.Parent ~= nil and string.find(h.Parent.Name, 'Prismarine', 1, true) ~= nil then
			return true
		end
		if h.MaxHealth > math.min(hum.MaxHealth * 8, 5000) then
			-- (size alone is not danger any more: only a big mob the threat ledger counts as a threat)
			local T = G.FTThreat
			if h.Parent == nil or T == nil then
				return true
			end
			if not T.is(h.Parent) then
				return false
			end
			-- (one recorded hit is not enough to run from a kind on sight: a single reading can be
			-- several mobs landing at once. Its attacks are still dodged; keeping away needs two.)
			local rec = T.kind[T.key(h.Parent)]
			if rec and not T.pressure then -- (v178: a measured kind is only kept away from while health is actually going down)
				return false
			end
			return true
		end
		return false
	end
	function Deadly.avoid(m)
		return Deadly.is(m) or Deadly.big(m:FindFirstChildOfClass('Humanoid'))
	end
	local function blame(pos, why, minHp)
		local _, list = mobsNear(pos, minHp and 30 or 12)
		local n = 0
		for _, e in ipairs(list) do
			if e.h.MaxHealth < 1e8 and e.h.MaxHealth >= (minHp or 0) and not e.m.Name:find('Dummy') then
				local k = kind(e.m)
				if not Deadly.names[k] then
					Deadly.names[k] = true
					warn(('[ForgeTools] %s is now on the deadly list (%s)'):format(k, why))
				end
				n += 1
				if n >= 2 then
					break
				end
			end
		end
		if n > 0 then
			saveDeadly()
		end
	end
	-- Watch our own health: a death, or one hit for 45%+ of max health, blames the mobs next to us.
	task.spawn(function()
		local lastHp, lastPos
		while alive do
			local _, hrp, hum = char()
			if hrp and hum then
				local hp, mx = hum.Health, math.max(1, hum.MaxHealth)
				if lastHp and lastHp > 0 then
					if hp <= 0 then
						blame(lastPos or hrp.Position, 'it killed you', mx * 2.2)
					elseif lastHp - hp >= mx * 0.45 then
						blame(hrp.Position, ('one hit took %.0f of your %.0f health'):format(lastHp - hp, mx))
					end
				end
				lastHp, lastPos = hp, hrp.Position
			else
				lastHp = nil
			end
			task.wait(0.1)
		end
	end)
end

-- A live mob close enough to hit us while we mine / walk (training dummies don't count).
-- Deadly mobs count from much farther away.
local function mineThreat()
	local _, hrp = char()
	if not hrp then
		return nil
	end
	local dead = Deadly.near(hrp.Position, 24)
	if dead then
		return dead
	end
	local shrug = MineHooks.shrug
	local _, list = mobsNear(hrp.Position, 12)
	for _, e in ipairs(list) do
		if e.h.MaxHealth < 1e8 and not e.m.Name:find('Dummy') and not (shrug and (shrug[e.m] or 0) > os.clock()) then
			return e
		end
	end
	local att = MineHooks.attacker and MineHooks.attacker() or nil
	if att and att.m and (mobIgnored(att.m) or (shrug and (shrug[att.m] or 0) > os.clock())) then
		att = nil
	end
	return att
end

-- Where we can walk depends on where we are: forget the skip lists after a respawn.
function MineHooks.reset()
	table.clear(unreachFails)
	table.clear(zoneNoPath)
end

local function rockList()
	local _, hrp = char()
	local list = {}
	local rocks = workspace:FindFirstChild('Rocks')
	if not rocks or not hrp then
		return list
	end
	local others = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local oc = pl ~= LocalPlayer and pl.Character
		local oh = oc and oc:FindFirstChild('HumanoidRootPart')
		local om = oc and oc:FindFirstChildOfClass('Humanoid')
		if oh and om and om.Health > 0 then
			others[#others + 1] = oh.Position
		end
	end
	for _, zone in ipairs(rocks:GetChildren()) do
		-- (v273, asked for: "its going to an area thats not been unlocked ... do the quests avoiding
		-- the blocked off area". On Island 2 it was after the Basalt Rocks in the Goblin Cave, which is
		-- shut until its quest is done, and bounced off it for minutes. That zone is left out unless
		-- G.FTZoneOpen[zone] is set; the user's own zone pick still wins.
		-- v289: same for any zone named '...Closed' - it stood at Island2CaveLavaClosed's Basalt Vein for minutes.)
		local shut = (zone.Name == 'Island2GoblinCave' or string.find(zone.Name, 'Closed', 1, true) ~= nil) and not (type(G.FTZoneOpen) == 'table' and G.FTZoneOpen[zone.Name]) and settings.mineZone ~= zone.Name
		if not shut and (settings.mineZone == 'Any' or settings.mineZone == zone.Name) and os.clock() >= (zoneBlocked[zone.Name] or 0) then
			for _, sp in ipairs(zone:GetChildren()) do
				local m = sp:FindFirstChildWhichIsA('Model')
				local hb = m and m:FindFirstChild('Hitbox')
				local hp = m and m:GetAttribute('Health')
				if hb and type(hp) == 'number' and hp > 0 and not tooStrong[m.Name] and not ReqDmg.blocks(m)
					and not (unreachable[m] and os.clock() < unreachable[m])
					and not ((settings.skipLucky or G.FTQuestWantsOre) and string.find(m.Name, 'Lucky', 1, true))
					and not Deadly.near(hb.Position, Deadly.RANGE + 8)
					and not Lava.at(groundAt(standNear(hb, 2).Position))
				then
					-- Rocks with mobs around them count as much farther away, so clear ones win.
					local danger = mobsNear(hb.Position, 22)
					local d = (hb.Position - hrp.Position).Magnitude
					local want = ((G.FTQuestRock and m.Name == G.FTQuestRock) or (G.FTQuestRocks and G.FTQuestRocks[m.Name]) or (G.FTCraftRocks and G.FTCraftRocks[m.Name] and craftWant())) and -350 or 0 -- quest asks for this rock type (or for an ore only these rocks give)
					local climb = math.abs(hb.Position.Y - hrp.Position.Y)
					-- someone else is already on this rock: leave it to them (unless we are on it too)
					local taken = 0
					local half = math.max(hb.Size.X, hb.Size.Z) / 2
					if d > half + 8 then
						for _, op in ipairs(others) do
							if (op - hb.Position).Magnitude <= half + 13 then
								taken = 1
								break
							end
						end
					end
					if taken == 1 then
						continue -- someone is at this rock: it is theirs
					end
					list[#list + 1] = { m = m, hb = hb, d = d, zone = zone.Name, danger = danger, maxHp = tonumber(m:GetAttribute('MaxHealth')) or hp,
						score = d + ((climb > 10 and d < 80) and climb * 4 or 0) + math.min(danger, 3) * 35 + taken * 150 + want }
				end
			end
		end
	end
	-- Rock selector: the picked kinds come first, wherever they are. With none of them to be had,
	-- the next best kind is the one with the most health below the picked ones (huge > large >
	-- medium > small), and kinds bigger than the picked ones come last.
	local sel = type(settings.mineRocks) == 'table' and next(settings.mineRocks) and settings.mineRocks or nil
	-- (v322, reported "i had selected mine only picked rocks and it just ceases". Rocks spawn as a random
	-- kind at each spot - island 4's Spirit Cave has 36 spots and only 3 Spirit Rocks up at a time - so
	-- the zones a picked kind spawns in are learned by seeing it. That memory used to live only until a
	-- rejoin; with none of the picked rocks up right then nothing was left to mine and it stood still.
	-- Now it is kept in the settings file, per rock kind.)
	if sel then
		settings.pickedZones = type(settings.pickedZones) == 'table' and settings.pickedZones or {}
		if not settings.pickedZones['Spirit Rock'] then
			settings.pickedZones['Spirit Rock'] = { I4_SpiritCave = true } -- (seen there, 2026-11-17)
		end
		local learned = false
		for _, zone in ipairs(rocks:GetChildren()) do
			for _, sp in ipairs(zone:GetChildren()) do
				local m = sp:FindFirstChildWhichIsA('Model')
				if m and sel[m.Name] then
					local zt = settings.pickedZones[m.Name]
					if type(zt) ~= 'table' then
						zt = {}
						settings.pickedZones[m.Name] = zt
					end
					if not zt[zone.Name] then
						zt[zone.Name] = true
						learned = true
					end
				end
			end
		end
		if learned then
			save()
		end
	end
	-- (v293, asked: Spirit Rocks only. With "mine only the picked rocks" on, no other kind is mined
	-- when none of the picked ones is standing - it waits for them instead. Quest rocks still win.)
	if sel and settings.mineOnlyPicked and not G.FTQuestRock and not G.FTQuestRocks then
		-- (v294, asked: "shit stopped mining" - every Spirit Rock was mined out and it stood still.
		-- Zones where a picked rock has stood are remembered; while none is up, it mines the other
		-- rocks in those zones only, so it stays where the picked ones spawn. No zone known yet: waits.)
		G.FTPickedZones = {}
		for name in pairs(sel) do
			for zn in pairs(type(settings.pickedZones[name]) == 'table' and settings.pickedZones[name] or {}) do
				G.FTPickedZones[zn] = true
			end
		end
		local anyPicked = false
		for _, e in ipairs(list) do
			if sel[e.m.Name] then
				anyPicked = true
			end
		end
		local kept = {}
		for _, e in ipairs(list) do
			if sel[e.m.Name] or (not anyPicked and G.FTPickedZones[e.zone]) then
				kept[#kept + 1] = e
			end
		end
		-- (nothing at all left - no zone known for the picked kinds yet, or every rock there is mined or
		-- taken: mine the nearest rocks rather than stand still. The picked kinds still come first the
		-- moment one is up.)
		if #kept > 0 then
			list = kept
			G.FTPickedFallback = nil
		else
			G.FTPickedFallback = os.clock()
		end
	end
	if sel and not G.FTQuestRock and not G.FTQuestRocks then
		local ref = 0
		for _, e in ipairs(list) do
			if sel[e.m.Name] then
				ref = math.max(ref, e.maxHp)
			end
		end
		if ref == 0 then
			ref = MineHooks.selRef or math.huge -- (none of the picked kind around right now: remember how big it is)
		else
			MineHooks.selRef = ref
		end
		local kinds, order = {}, {}
		for _, e in ipairs(list) do
			if not sel[e.m.Name] and not kinds[e.m.Name] then
				kinds[e.m.Name] = e.maxHp
				order[#order + 1] = e.m.Name
			end
		end
		table.sort(order, function(a, b)
			local ha, hb2 = kinds[a], kinds[b]
			local ua, ub = ha <= ref, hb2 <= ref
			if ua ~= ub then
				return ua
			end
			if ua then
				return ha > hb2
			end
			return ha < hb2
		end)
		local tier = {}
		for i, name in ipairs(order) do
			tier[name] = i
		end
		-- (v323, reported: "it really likes to go away from the spirit cave even though i got spirit rock and
		-- sakura crystal selected". With no Spirit Rock up, the next kind by size was Glowy Rock (18k, just
		-- under the Spirit Rock's 20k) in the Holy Cave, 100+ studs up, wherever it was; the cave's own Soul
		-- Boulders and Thunder Cores are bigger, so they came last. Now: picked kinds first, then any rock
		-- in a zone where a picked kind spawns (nearest first), then the size order elsewhere.)
		local homeZones = {}
		for name in pairs(sel) do
			for zn in pairs(type(settings.pickedZones) == 'table' and type(settings.pickedZones[name]) == 'table' and settings.pickedZones[name] or {}) do
				homeZones[zn] = true
			end
		end
		for _, e in ipairs(list) do
			if sel[e.m.Name] then
				e.score -= 100000
			elseif not homeZones[e.zone] then
				e.score += (tier[e.m.Name] or 0) * 100000
			end
		end
	end
	-- Marked rocks (the game's "RockMutation" attribute: Galaxy = Galactic, Blessed, Prismatic...)
	-- picked in the menu go before everything else, whatever kind of rock they are and wherever.
	local muts = type(settings.mineMutations) == 'table' and next(settings.mineMutations) and settings.mineMutations or nil
	if muts and not G.FTQuestRock and not G.FTQuestRocks then
		for _, e in ipairs(list) do
			local mu = e.m:GetAttribute('RockMutation')
			if mu and muts[mu] then
				e.score -= 1e7
				e.mut = mu
			end
		end
	end
	-- A quest's rocks come first wherever they are (measured: with the bamboo rocks 740+ studs off,
	-- a 350-stud head start still picked the pebble next door, which gives none of the quest's ore).
	if G.FTQuestRock or G.FTQuestRocks then
		for _, e in ipairs(list) do
			if e.m.Name == G.FTQuestRock or (G.FTQuestRocks and G.FTQuestRocks[e.m.Name]) then
				e.score -= 1e6
			end
		end
	end
	if G.FTCraftRocks and craftWant() then
		for _, e in ipairs(list) do
			if G.FTCraftRocks[e.m.Name] then
				e.score -= 3e6
			end
		end
	end
	-- Waiting for a focused quest's mobs to respawn (v185): mine the rocks around where they live,
	-- not wherever another quest points (measured: 1,000 studs away in the bamboo while the
	-- Frostburn Onis respawned in their cave).
	if G.FTCamp then
		for _, e in ipairs(list) do
			if e.hb and (e.hb.Position - G.FTCamp).Magnitude <= 280 then
				e.score -= 2e6
			end
		end
	end
	table.sort(list, function(a, b)
		return a.score < b.score
	end)
	return list
end

local function mineOnce()
	local pick = LocalPlayer.Backpack:FindFirstChild('Pickaxe') or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('Pickaxe'))
	if not pick then
		setStatus('no pickaxe')
		return false
	end
	local target = rockList()[1]
	if not target then
		local soon
		for _, untilT in pairs(zoneBlocked) do
			if untilT > os.clock() then
				soon = true
			end
		end
		setStatus(soon and 'no rocks I can walk to from here — go into a cave (retrying soon)'
			or ('no rocks to mine in ' .. tostring(settings.mineZone)
				.. (next(Deadly.names) and settings.fleeDeadly ~= false and ' (rocks next to mobs that killed you are skipped)' or '')))
		return false
	end
	if (target.danger or 0) > 0 and MineHooks.clear then
		-- Every reachable rock has mobs on it: kill those first, then mine.
		if MineHooks.clear(target.hb.Position) then
			return true
		end
	end
	setStatus(('mining %s (%.0f studs)'):format(target.m.Name, target.d))
	local alt = {}
	do
		local hb = target.hb
		local r = math.max(hb.Size.X, hb.Size.Z) / 2 + 2
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2
			alt[#alt + 1] = hb.Position + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		end
	end
	-- On the way to a rock (more than 30 studs out) mobs are not a reason to stop: we walk faster
	-- than they run, and stopping for each one turned every trip into a string of fights. Only a
	-- kind that has killed us before still gets a wide berth. At the rock itself they are dealt with.
	local function threatNow()
		local th = mineThreat()
		if th and not Deadly.avoid(th.m) then
			local _, me = char()
			if me and (me.Position - target.hb.Position).Magnitude > 30 then
				return nil
			end
		end
		return th
	end
	local function why(txt)
		G.FTMineLog = G.FTMineLog or {}
		local _, me = char()
		local off = me and (me.Position - target.hb.Position)
		local log = G.FTMineLog
		log[#log + 1] = ('%s %s hp=%s | %s | horiz %.1f vert %.1f half %.1f'):format(os.date('%H:%M:%S'), target.m.Name, tostring(target.m:GetAttribute('Health')),
			txt, off and (off * Vector3.new(1, 0, 1)).Magnitude or -1, off and off.Y or 0, math.max(target.hb.Size.X, target.hb.Size.Z) / 2)
		if #log > 120 then
			table.remove(log, 1)
		end
	end
	-- (v291, asked: "mine spirit rocks ignore mobs". With ignoreMobs on, a mob near the rock is not
	-- fought: mining goes on. Kinds that have killed us and low health still pull us away, and
	-- attack markers / projectiles are still stepped out of by the hazard loop.)
	local function ignored(th)
		if not settings.ignoreMobs then
			return false
		end
		local _, _, hm = char()
		local pctI = hm and hm.MaxHealth > 0 and hm.Health / hm.MaxHealth * 100 or 100
		return not Deadly.avoid(th.m) and pctI >= math.max(40, tonumber(settings.retreatHp) or 0)
	end
	local function handleThreat()
		local th = threatNow()
		if not th or ignored(th) then
			return false
		end
		why('threat ' .. tostring(th.m and th.m.Name) .. (' %.0f studs from us'):format(th.d or -1))
		-- (measured: 10 of 14 rocks were left this way, each for one spider, and the next rock was 100-200
		-- studs off. Only a kind we must keep away from is a reason to leave the rock alone for a while.)
		if Deadly.avoid(th.m) or (th.h and Deadly.big(th.h)) then
			unreachable[target.m] = os.clock() + 60
		end
		local tD = os.clock()
		if MineHooks.defend then
			MineHooks.defend(th)
		end
		if os.clock() - tD < 1.5 then
			unreachable[target.m] = math.max(unreachable[target.m] or 0, os.clock() + 30)
		end
		return true
	end
	if handleThreat() then
		return true
	end
	G.FTNavDbg = nil
	-- someone else reaches the rock while we are still on the way: leave it to them
	local takenAt, takenNow = 0, false
	local function takenByOther()
		if os.clock() - takenAt < 0.4 then
			return takenNow
		end
		takenAt, takenNow = os.clock(), false
		local _, me = char()
		local half = math.max(target.hb.Size.X, target.hb.Size.Z) / 2
		if me and (me.Position - target.hb.Position).Magnitude > half + 8 then
			for _, pl in ipairs(Players:GetPlayers()) do
				local oh = pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild('HumanoidRootPart')
				if oh and (oh.Position - target.hb.Position).Magnitude <= half + 13 then
					takenNow = true
					unreachable[target.m] = os.clock() + 45
					break
				end
			end
		end
		return takenNow
	end
	local okGo, whyGo = tweenTo(standNear(target.hb, 2), { alt = alt, abort = function()
		if not (settings.autoMine or G.FTQuestWantsOre) or not target.m.Parent or takenByOther() then
			return true
		end
		-- (v321, reported "stops mining sometimes": with Ignore mobs on, a mob within 30 studs of the rock
		-- called the trip off 26 studs short, the mob was then ignored, and "knocked far away" ended the
		-- mining - 15 times in 4 s, standing still until the mob wandered off.)
		local th = threatNow()
		return th ~= nil and not ignored(th)
	end, onRelay = function()
		setStatus(('mining %s (%.0f studs) — long route, walking via known spots'):format(target.m.Name, target.d))
	end })
	if handleThreat() then
		return true
	end
	if takenNow then
		why('taken by another player')
		setStatus(('someone else got to that %s first — picking another'):format(target.m.Name))
		return true
	end
	if not okGo then
		local _, myh = char()
		why('travel failed: ' .. tostring(whyGo) .. ' nav=' .. tostring(G.FTNavDbg))
		if (settings.autoMine or G.FTQuestWantsOre) and target.m.Parent and myh and whyGo ~= 'wedged'
			and (myh.Position - target.hb.Position).Magnitude > math.max(target.hb.Size.X, target.hb.Size.Z) / 2 + 10 then
			local fails = (unreachFails[target.m] or 0) + 1
			unreachFails[target.m] = fails
			-- (a rock in another cave, hundreds of studs off, that the trip to failed for whatever
			-- reason: measured, it went back to the same unreachable boulder 770 studs away for
			-- minutes while 15 others of the kind had a route. Rule it out, and its zone after two.)
			local far = (myh.Position - target.hb.Position).Magnitude > 300
			if far and os.clock() - (MineHooks.crossAt or -1e9) > 2 then
				MineHooks.crossAt = os.clock()
				if Nav.cross(target.hb, target.m.Name) then
					table.clear(unreachable)
					table.clear(unreachFails)
					table.clear(zoneNoPath)
					table.clear(zoneBlocked)
					return true
				end
			end
			if whyGo == 'nopath' or far then
				-- Third rock in a row with no route at all, from the same place: it is not the rocks,
				-- it is where we are standing. Get out, and forget what was ruled out from in here.
				local sp = MineHooks.strandPos
				if far then
					MineHooks.strandN = 0
				elseif sp and (myh.Position - sp).Magnitude < 25 then
					MineHooks.strandN = (MineHooks.strandN or 0) + 1
				else
					MineHooks.strandPos, MineHooks.strandN = myh.Position, 1
				end
				if MineHooks.strandN >= 3 and Nav.escape() then
					MineHooks.strandPos, MineHooks.strandN = nil, 0
					table.clear(unreachable)
					table.clear(unreachFails)
					table.clear(zoneNoPath)
					table.clear(zoneBlocked)
					return true
				end
				-- No walkable route at all (walled off / different cave): don't keep coming back.
				unreachable[target.m] = os.clock() + 600
				local z = zoneNoPath[target.zone]
				if not z or os.clock() - z.at > 120 then
					z = { n = 0, at = os.clock() }
					zoneNoPath[target.zone] = z
				end
				z.n += 1
				z.at = os.clock()
				if (z.n >= 2 or far) and settings.mineZone == 'Any' then
					-- (a far zone: on to the next zone at once, and back to this one in 3 minutes -
					-- from another spot the same zone often does have a route)
					zoneBlocked[target.zone] = os.clock() + (far and z.n < 2 and 180 or 1200)
					zoneNoPath[target.zone] = nil
					setStatus(target.zone .. ' is walled off from here — mining other zones')
				else
					setStatus('no route to ' .. target.m.Name .. ' — skipping it')
				end
			else
				unreachable[target.m] = os.clock() + math.min(45 * fails, 300)
				setStatus('cannot reach ' .. target.m.Name .. ' on foot — skipping for now [' .. tostring(whyGo) .. ': ' .. tostring(G.FTNavDbg) .. ']')
			end
		end
		return true
	end
	unreachFails[target.m] = nil
	zoneNoPath[target.zone] = nil
	local tool = equip('Pickaxe')
	local lastHp, lastChange = target.m:GetAttribute('Health'), os.clock()
	while alive and (settings.autoMine or G.FTQuestWantsOre) and target.m.Parent do
		local hp = target.m:GetAttribute('Health') or 0
		if hp <= 0 then
			stats.mined += 1
			break
		end
		if tooStrong[target.m.Name] then
			break -- (just learned this type needs more damage than the pickaxe has)
		end
		do
			-- (v321: a mob's hits stun us and the swings do nothing meanwhile - measured 1.5 s stuns from a
			-- Spirit Golem. That is not the rock's fault: stunned time does not count toward "no damage".)
			local cS = LocalPlayer.Character
			local stS = cS and cS:FindFirstChild('Status')
			if stS and stS:FindFirstChild('Stun') then
				lastChange = math.max(lastChange, os.clock() - 1)
				G.FTMineStunned = (G.FTMineStunned or 0) + 1
			end
		end
		if hp ~= lastHp then
			lastHp, lastChange = hp, os.clock()
			noDamage[target.m.Name] = nil
			canBreak[target.m.Name] = true
			tooStrong[target.m.Name] = nil
		elseif os.clock() - lastChange > 4 then
			local bagUsed, bagCap = bagCapacity()
			if bagUsed and bagCap and bagUsed >= bagCap then
				-- a full bag is why nothing is coming off the rock
				setStatus(('bag is full (%d/%d) — %s'):format(bagUsed, bagCap,
					(settings.autoSell or settings.autoForge) and 'going to empty it' or 'turn on Auto sell or Auto forge'))
				G.FTBagFull = os.clock()
				break
			end
			-- No damage for 4s. One rock says little (out of reach on a ledge, a mob in the way...):
			-- leave this rock for a while, and only give up on the TYPE after three different rocks.
			local _, h4 = char()
			local away = h4 and (h4.Position - target.hb.Position).Magnitude or -1
			unreachable[target.m] = os.clock() + 180
			noDamage[target.m.Name] = (noDamage[target.m.Name] or 0) + 1
			if noDamage[target.m.Name] >= 3 and not canBreak[target.m.Name] then
				tooStrong[target.m.Name] = true
				setStatus(target.m.Name .. ' too strong for your pickaxe — skipping that type')
				else
				why('no damage 4s')
				setStatus(('no damage on %s from %.0f studs away (rock is %.0f wide) — trying another'):format(
					target.m.Name, away, math.max(target.hb.Size.X, target.hb.Size.Z)))
			end
			break
		end
		local _, hrp, hum = char()
		if hrp then
			local half = math.max(target.hb.Size.X, target.hb.Size.Z) / 2
			local off = (hrp.Position - target.hb.Position) * Vector3.new(1, 0, 1)
			local topY = target.hb.Position.Y + target.hb.Size.Y / 2
			if off.Magnitude < half and hrp.Position.Y - 3 > topY - 2.5 and os.clock() - (MineHooks.offTopAt or 0) > 1 then
				-- we are ON the rock (measured: horiz 0.7, 3 studs above its top, no damage for 4s,
				-- four times on the same boulder). Get down beside it.
				MineHooks.offTopAt = os.clock()
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living') }
				rp.RespectCanCollide = true
				local base = off.Magnitude > 0.5 and math.atan2(off.Z, off.X) or 0
				for i = 0, 7 do
					local a = base + (i % 2 == 0 and 1 or -1) * math.ceil(i / 2) * math.pi / 4
					local at = target.hb.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * (half + 2.5)
					local hit = workspace:Raycast(Vector3.new(at.X, topY + 3, at.Z), Vector3.new(0, -(target.hb.Size.Y + 30), 0), rp)
					if hit and hit.Position.Y < topY - 3 and not hit.Instance:IsDescendantOf(target.m) and not Lava.at(hit.Position + Vector3.new(0, 3, 0)) then
						local stand = hit.Position + Vector3.new(0, 3, 0)
						why('was on top of the rock - stepping down beside it')
						hrp.CFrame = CFrame.lookAt(stand, Vector3.new(target.hb.Position.X, stand.Y, target.hb.Position.Z))
						hrp.AssemblyLinearVelocity = Vector3.zero
						lastChange = os.clock()
						break
					end
				end
			end
			if off.Magnitude > half + 16 then
				why('knocked far away')
				break -- knocked far away
			elseif hum and os.clock() - lastChange > 1.2 and (function()
				-- (v278: a long rock - a Basalt Vein is 25 by 10 - measured from its middle with its long
				-- half looked "at the edge" 12.5 studs out on the short side, 7 studs from the stone. After
				-- 1.2 s of swings that do nothing: walk to the nearest point of the rock's actual box.)
				local lpos = target.hb.CFrame:PointToObjectSpace(hrp.Position)
				local sz = target.hb.Size
				local cx, cz = math.clamp(lpos.X, -sz.X / 2, sz.X / 2), math.clamp(lpos.Z, -sz.Z / 2, sz.Z / 2)
				local gap = Vector3.new(lpos.X - cx, 0, lpos.Z - cz).Magnitude
				if gap > 1.6 then
					local near = target.hb.CFrame:PointToWorldSpace(Vector3.new(cx, lpos.Y, cz))
					local out = (hrp.Position - near) * Vector3.new(1, 0, 1)
					local stand = near + (out.Magnitude > 0.1 and out.Unit or Vector3.zero) * 0.8
					hum:MoveTo(Vector3.new(stand.X, hrp.Position.Y - 3, stand.Z))
					G.FTRockStepIn = (G.FTRockStepIn or 0) + 1
					return true
				end
				return false
			end)() then
				-- (stepping to the box)
			elseif (off.Magnitude > half + 1.8 or (os.clock() - lastChange > 1.2 and off.Magnitude > half + 0.9)) and hum then
				-- step in: to the rock's edge, not its middle (walking at the middle climbed onto it)
				-- (v277, reported: "it still misses hitting rocks sometimes". Every "no damage 4s" in the log
				-- was 2.2-2.4 studs off the edge - just inside the old 2.5 "close enough". Now 1.8, and
				-- closer still once 1.2 s of swings have done nothing.)
				local edge = target.hb.Position + off.Unit * (half + (os.clock() - lastChange > 1.2 and 0.6 or 1.2))
				hum:MoveTo(Vector3.new(edge.X, hrp.Position.Y - 3, edge.Z))
			end
		end
		if handleThreat() then
			break
		end
		swing(tool)
		-- (v295, reported: "the mining portion of auto mine is really ass ... not efficient so he left
		-- autoclicker running". A click every 0.35 s against the pickaxe's own cooldown: any click
		-- landing inside the cooldown is dropped and the swing waits for the next one, so a cooldown a
		-- little over 0.35 s gave a swing only every ~0.7 s. Clicked like an autoclicker now; the game
		-- still swings only as fast as its cooldown allows.)
		task.wait(0.08)
	end
	return true
end

---------------------------------------------------------------------------
-- Selling (Greedy Cey)
---------------------------------------------------------------------------
local function sellNeeded()
	if not settings.autoSell then
		return false
	end
	local used, cap = bagCapacity()
	local _, total = oreCounts()
	if total <= 0 then
		return false
	end
	if used and cap and cap > 0 then
		-- (a few slots short of the mark still counts: rocks can drop several ores at once)
		return used >= math.floor(cap * math.min(100, tonumber(settings.sellAt) or 90) / 100) - 2
	end
	return total >= 30
end

-- (v212) ores that give a trait to anything (the game's own ore data), for "keep trait ores"
local traitOreSet
local function oreHasTrait(name)
	if not traitOreSet then
		local set = {}
		local okT = pcall(function()
			for _, o in pairs(require(RS.Shared.Data.Ore)) do
				if type(o) == 'table' and o.Name and type(o.Traits) == 'table' and next(o.Traits) ~= nil then
					set[o.Name] = true
				end
			end
		end)
		if not okT then
			return true -- (cannot tell: keep it)
		end
		traitOreSet = set
		G.FTTraitOres = set
	end
	return traitOreSet[name] == true
end

local function sellOres()
	local npc = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Greedy Cey')
	if not npc then
		setStatus('Greedy Cey not found')
		return false
	end
	local ores = oreCounts()
	local keep = settings.autoForge and math.max(0, tonumber(settings.forgeKeep) or 0) or 0
	local basket, count = {}, 0
	for name, n in pairs(ores) do
		local sell = n - keep
		if settings.keepTraitOres and oreHasTrait(name) then
			sell = 0
		end
		if sell > 0 then
			basket[name] = sell
			count += sell
		end
	end
	if count == 0 then
		return false
	end
	setStatus(('selling %d ores'):format(count))
	local PS, DS = service('ProximityService'), service('DialogueService')
	-- The shop takes the sale from anywhere on the map: no walk needed.
	local function sale()
		local goldBefore = (data() or {}).Gold or 0
		pcall(function()
			PS:ForceDialogue(npc, 'SellConfirmMisc')
		end)
		task.wait(0.4)
		pcall(function()
			DS:RunCommand('SellConfirm', { Basket = basket })
		end)
		-- the gold shows up a moment after the sale
		local tg = os.clock()
		while os.clock() - tg < 3 and ((data() or {}).Gold or 0) == goldBefore do
			task.wait(0.1)
		end
		-- (the game roots you while a dialogue is open: always close it)
		pcall(function()
			getsenv(LocalPlayer.PlayerGui.DialogueUI.DialogueHandler).Close()
		end)
		return ((data() or {}).Gold or 0) - goldBefore
	end
	local gained = sale()
	if gained <= 0 then
		-- did not go through from here: do it the old way, standing at the shop
		local p = npc:GetPivot().Position
		local _, hrp = char()
		local dir = hrp and ((hrp.Position - p) * Vector3.new(1, 0, 1)) or Vector3.new(1, 0, 0)
		dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
		if not tweenTo(CFrame.lookAt(p + dir * 5, Vector3.new(p.X, p.Y, p.Z))) then
			return false
		end
		task.wait(0.3)
		gained = sale()
	end
	if gained <= 0 then
		setStatus('selling ores did not go through — trying again soon')
		task.wait(2)
		return false
	end
	stats.sold += count
	setStatus(('sold %d ores for %s gold'):format(count, tostring(math.floor(gained * 100) / 100)))
	return true
end

---------------------------------------------------------------------------
-- Forging (perfect minigames)
---------------------------------------------------------------------------
local hooked = false
local function hookMinigames(FC)
	if hooked or not FC.Minigames then
		return FC.Minigames ~= nil
	end
	local M = FC.Minigames
	local function finishTime(startTime, wait)
		local offset = workspace:GetServerTimeNow() - startTime
		task.wait(wait)
		return workspace:GetServerTimeNow() - offset
	end
	if M.MeltMinigame then
		M.MeltMinigame.Start = function(_, d)
			local t = finishTime(d.StartTime, (tonumber(d.RequiredTime) or 2) + 0.6)
			pcall(function()
				local ui = controller('UIController')
				for _, v in pairs(ui.Modules.Forge.physicalOres or {}) do
					v:Destroy()
				end
			end)
			return t, true
		end
	end
	if M.PourMinigame then
		M.PourMinigame.Start = function(_, d)
			return finishTime(d.StartTime, (tonumber(d.RequiredTime) or 2) + 0.4), true
		end
	end
	if M.HammerMinigame then
		-- Every note is "clicked" exactly on the beat (Lifetime * 25/44 after it appears).
		M.HammerMinigame.CreateNote = function(_, note)
			task.wait((tonumber(note.Lifetime) or 1) * 25 / 44)
			return true
		end
		-- Before the notes, the hammer waits for 3 clicks on the mould to break it open.
		-- Keep the game's original across reloads so wrappers never stack.
		G.FTOrigHammerStart = G.FTOrigHammerStart or M.HammerMinigame.Start
		local origStart = G.FTOrigHammerStart
		M.HammerMinigame.Start = function(self, d)
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 15 do
					local mold
					for _, c in ipairs(workspace.Debris:GetChildren()) do
						if c.Name == 'Mold' and c:GetAttribute('IsDestroyed') ~= true and c:FindFirstChild('ClickDetector') then
							mold = c
						end
					end
					if mold then
						task.wait(0.3)
						for _ = 1, 3 do
							local cd = mold:FindFirstChild('ClickDetector')
							if not cd then
								break
							end
							local fired = false
							pcall(function()
								for _, conn in ipairs(getconnections(cd.MouseClick)) do
									conn:Fire()
									fired = true
								end
							end)
							if not fired then
								pcall(fireclickdetector, cd)
							end
							task.wait(0.2)
						end
						return
					end
					task.wait(0.1)
				end
			end)
			return origStart(self, d)
		end
	end
	hooked = true
	return true
end

-- What the active quests want from farming (filled in by the quest module each step).
local QS = { wantMobs = false, wantMine = false, storyMobs = false, storyMine = false, mobTarget = nil }

-- "Aim for piece". The game rolls WHICH weapon / armor piece you get from how many ores go in
-- (ItemRarity:CalculateProbabilities), so a piece can't be forced: we use the ore count that gives
-- the wanted piece its best odds and keep forging until it comes out.
local Piece = {}
do
	local function IR()
		return require(RS.Shared.ItemRarity)
	end
	function Piece.typeOf(piece)
		if type(piece) ~= 'string' or piece == 'Any' then
			return nil
		end
		local found
		pcall(function()
			local ir = IR()
			for _, ty in ipairs({ 'Weapon', 'Armor' }) do
				for _, v in ipairs(ir[ty] or {}) do
					if v.name == piece then
						found = ty
					end
				end
			end
		end)
		return found
	end
	function Piece.names()
		local out = { 'Any' }
		pcall(function()
			local ir = IR()
			for _, ty in ipairs({ 'Weapon', 'Armor' }) do
				for _, v in ipairs(ir[ty] or {}) do
					out[#out + 1] = v.name
				end
			end
		end)
		return out
	end
	-- The piece to aim for when forging `itemType`, or nil.
	function Piece.want(itemType)
		local piece = settings.forgePiece
		return Piece.typeOf(piece) == itemType and piece or nil
	end
	-- Pieces this forge can make for us right now (same filter the game's forge screen uses).
	local function available(itemType)
		local ir = IR()
		local d = data()
		local okS, st = pcall(ir.ResolveStation, ir, 'Island1', d)
		if not okS then
			local f = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Forge')
			st = f and f:FindFirstChild('Station') and f.Station.Value and f.Station.Value.Name or 'Island1'
		end
		local okD, SD = pcall(ir.GetStationData, ir, st, itemType)
		local list = {}
		for _, v in ipairs(ir[itemType] or {}) do
			local ok = not (okD and type(SD) == 'table' and not SD[v.name])
			if ok then
				local okA, a = pcall(ir.GetAvailableItems, ir, st, itemType, v.name, d)
				if okA and type(a) == 'table' and #a == 0 then
					ok = false
				end
			end
			if ok then
				list[#list + 1] = v
			end
		end
		return list
	end
	local cache = {}
	-- Ore count (3..cap) with the best odds for the piece, and those odds in %. nil = can't be made.
	function Piece.count(itemType, piece)
		local cap = tonumber(settings.forgeOres) or 3
		cap = cap > 3 and cap or 60
		local c = cache[piece]
		if c and c.cap == cap and os.clock() - c.at < 60 then
			return c.n, c.chance
		end
		local chances, top = {}, 0
		pcall(function()
			local ir = IR()
			local list = available(itemType)
			for n = 3, cap do
				for _, pr in ipairs(ir:CalculateProbabilities(n, list)) do
					if pr.name == piece then
						chances[n] = tonumber(pr.chance or pr.probability) or 0
						top = math.max(top, chances[n])
					end
				end
			end
		end)
		local bestN
		if top > 0 then
			for n = 3, cap do
				-- fewest ores that get within a point of the best odds
				if chances[n] and chances[n] >= top - 1 then
					bestN = n
					break
				end
			end
		end
		cache[piece] = { cap = cap, at = os.clock(), n = bestN, chance = bestN and chances[bestN] or 0 }
		return bestN, bestN and chances[bestN] or 0
	end
end

-- Active quest that wants something forged ("Forge Weapon 1/2") -> 'Weapon' / 'Armor', else nil.
local function questForgeType()
	if not settings.autoCompleteQuests then
		return nil
	end
	local d = data()
	for qid, q in pairs(d and d.Quests or {}) do
		-- (only the quest being worked on: one quest at a time)
		for _, p in ipairs(type(q) == 'table' and (G.FTQuestLock == nil or G.FTQuestLock == qid) and q.Progress or {}) do
			if type(p) == 'table' and p.questType == 'Forge'
				and (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 0) then
				return (p.target == 'Armor') and 'Armor' or 'Weapon'
			end
		end
	end
	return nil
end
-- "Alternate weapon / armor": the type flips after every item that was actually made.
local forgeAlt, forgeFails = nil, 0
local forgeBad = {} -- [item type] = os.clock() until which the server keeps refusing it
local function forgeTypeNow()
	local forced = questForgeType() or Piece.typeOf(settings.forgePiece)
	if forced then
		return forced
	end
	if settings.forgeAlternate and forgeAlt then
		-- (measured: Weapon forges were refused every time while Armor went through; alternating
		-- then lost ~10s on every second forge and a 5 minute pause after two in a row)
		local other = (forgeAlt == 'Weapon') and 'Armor' or 'Weapon'
		if (forgeBad[forgeAlt] or 0) > os.clock() and (forgeBad[other] or 0) <= os.clock() then
			return other
		end
		return forgeAlt
	end
	return settings.forgeType
end

-- Molds: the game's way to aim a forge at one item. Each item has its own number of molds that
-- guarantees it (Cutlass 12, Dagger 2, Excalibur 150...); with fewer the chance is
-- (molds / guarantee) squared - half the molds is a quarter of the chance - so anything short of
-- the full number mostly burns molds. The item also needs a minimum ore count (by its class:
-- a straight sword 9, a colossal sword 50). We only ever use molds when the full number is owned.
local Mold = {}
do
	local cache = {}
	function Mold.info(name)
		if cache[name] == nil then
			local out = false
			pcall(function()
				local E = require(RS.Shared.Data.Equipments)
				local IRm = require(RS.Shared.ItemRarity)
				local d = E:GetItemData(name)
				local base = E:GetItemBaseType(name)
				local cfg = base and IRm:GetItemDataConfig(base)
				local kind = E:GetItemType(name)
				if d and base and (kind == 'Weapon' or kind == 'Armor') then
					out = { kind = kind, molds = tonumber(d.Molds) or tonumber(IRm.MoldGuarantee) or 30, minOres = cfg and tonumber(cfg.lock_min_ores) or 3 }
				end
			end)
			cache[name] = out
		end
		return cache[name] or nil
	end
	function Mold.owned(itemType)
		local key = itemType == 'Weapon' and 'WeaponMold' or 'ArmorMold'
		local n = 0
		local d = data()
		for _, it in pairs(d and d.Inventory and d.Inventory.Misc or {}) do
			if type(it) == 'table' and it.Name == key then
				n += tonumber(it.Quantity) or 1
			end
		end
		return n
	end
	-- The mold target for a forge of `itemType`: name, molds to use, least ores - or nil when
	-- none is picked, it is the other type, or we do not own enough molds to guarantee it.
	function Mold.plan(itemType)
		local name = settings.forgeMold
		if type(name) ~= 'string' or name == 'None' then
			return nil
		end
		local info = Mold.info(name)
		if not info or info.kind ~= itemType then
			return nil
		end
		if Mold.owned(itemType) < info.molds then
			return nil, 0, 0, info
		end
		return name, info.molds, info.minOres, info
	end
end

local function forgeNeeded()
	local _, total = oreCounts()
	if questForgeType() then
		return total >= 3
	end
	if not settings.autoForge then
		return false
	end
	_, total = forgeCounts() -- (only the ores picked under "Ores to use" count from here on)
	if os.clock() < (G.FTForgeFailUntil or 0) then
		return false -- the forge refused twice in a row: mine for a while instead of standing at it
	end
	if settings.forgeWhenFull then
		local used, cap = bagCapacity()
		if used and cap then
			-- Once the stash is full, keep forging until it is used up (fewer than 3 ores left)
			-- before the next mining trip. Gives up if 2 minutes pass without an ore being used.
			local keep = math.max(0, tonumber(settings.forgeKeep) or 0)
			local D = G.FTForgeDrain
			if D and (total - keep < 3 or (total >= D.total and os.clock() - D.at > 120)) then
				D = nil
			elseif D and total < D.total then
				D.total, D.at = total, os.clock()
			end
			if not D and total >= 3 and used >= cap - 1 then
				D = { total = total, at = os.clock() }
			end
			G.FTForgeDrain = D
			return D ~= nil
		end
	end
	local piece = Piece.want(forgeTypeNow())
	if piece then
		local n = Piece.count(forgeTypeNow(), piece)
		return n ~= nil and total >= n
	end
	local need = math.max(3, tonumber(settings.forgeOres) or 3)
	if (settings.forgeBest or settings.forgeTraits) and need <= 3 then
		need = 20 -- wait for enough ores to make something bigger than a dagger
	end
	local moldName, _, moldMin = Mold.plan(forgeTypeNow())
	if moldName then
		need = moldMin -- (a molded item: exactly as many ores as that item needs is enough)
	end
	return total >= need
end

-- Mining vs mobs when both are on: take turns in blocks so ores still come in.
-- A pending forge quest with too few ores always mines.
-- Quests can switch farming on by themselves (kill X zombies / get Y ore).
local turnStart, turnMobs = os.clock(), true
local function chooseFarm()
	local mobs = settings.autoMobs or QS.wantMobs
	local mine = settings.autoMine or QS.wantMine or craftWant()
	if questForgeType() then
		local _, total = oreCounts()
		if total < 3 then
			return 'mine'
		end
	end
	if mobs and mine then
		-- Story quests (one-time) beat repeatable ones like "Rotten Depths".
		-- The side the quest does not need but the user ticked themselves still gets its turn
		-- (measured on island 3: a spider-kill quest plus Auto mine = 5 minutes without one rock).
		local userOther = (QS.wantMobs and not QS.wantMine and (settings.autoMine or craftWant()))
			or (QS.wantMine and not QS.wantMobs and settings.autoMobs)
		if not userOther then
			if QS.storyMine ~= QS.storyMobs then
				return QS.storyMine and 'mine' or 'mobs'
			end
			if QS.wantMobs ~= QS.wantMine then
				return QS.wantMobs and 'mobs' or 'mine'
			end
		end
		local mins = math.max(1, tonumber(settings.switchMins) or 3)
		if os.clock() - turnStart >= mins * 60 then
			turnStart, turnMobs = os.clock(), not turnMobs
		end
		return turnMobs and 'mobs' or 'mine'
	end
	return (mobs and 'mobs') or (mine and 'mine') or nil
end

-- "Best gear" ore picking. Item strength = base stat of the item type x the AVERAGE multiplier of
-- the ores used x quality. More ores unlock bigger item types (Dagger 4.3 dmg ... Colossal Sword 20),
-- but adding weak ores drags the average multiplier down. So: rank ores by multiplier, and for every
-- ore count N take the N best ores and score  avgMultiplier(N) x expectedBaseStat(N), using the
-- game's own type odds (ItemRarity:CalculateProbabilities). Pick the N with the best score.
local Best = {}
do
	local multCache, neutral = nil, {}
	local function oreMult(name)
		if not multCache then
			multCache = {}
			pcall(function()
				for _, o in pairs(require(RS.Shared.Data.Ore)) do
					if type(o) == 'table' and o.Name then
						multCache[o.Name] = tonumber(o.Multiplier) or 0
						neutral[o.Name] = o.NeutralMultiplier == true
					end
				end
			end)
		end
		return multCache[name] or 0, neutral[name]
	end
	local baseCache = {}
	local function expectedBase(itemType, n)
		local key = itemType .. n
		if baseCache[key] then
			return baseCache[key]
		end
		local ev = 0
		pcall(function()
			local IR = require(RS.Shared.ItemRarity)
			local E = require(RS.Shared.Data.Equipments)
			local d = data()
			local okS, st = pcall(IR.ResolveStation, IR, 'Island1', d)
			if not okS then
				local f = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Forge')
				st = f and f:FindFirstChild('Station') and f.Station.Value and f.Station.Value.Name or 'Island1'
			end
			local okD, SD = pcall(IR.GetStationData, IR, st, itemType)
			local list = {}
			for _, v in ipairs(IR[itemType] or {}) do
				local ok = not (okD and type(SD) == 'table' and not SD[v.name])
				if ok then
					local okA, a = pcall(IR.GetAvailableItems, IR, st, itemType, v.name, d)
					if okA and type(a) == 'table' and #a == 0 then
						ok = false
					end
				end
				if ok then
					list[#list + 1] = v
				end
			end
			for _, p in ipairs(IR:CalculateProbabilities(n, list)) do
				local pr = tonumber(p.probability or p.chance or p.Probability) or 0
				if pr == 0 then
					for k, v in pairs(p) do
						if type(v) == 'number' and k ~= 'min_ores' and k ~= 'lock_min_ores' and k ~= 'base_weight' and k ~= 'scaling_factor' and k ~= 'current_weight' then
							pr = v
						end
					end
				end
				pr = pr > 1 and pr / 100 or pr
				local bt = E.BaseTypes[p.name]
				local stat = 0
				if bt and bt.Damage then
					stat = bt.Damage
				elseif bt and type(bt.Types) == 'table' then
					local sum, c = 0, 0
					for _, t in ipairs(bt.Types) do
						local a = E.Items.Armor and E.Items.Armor[t]
						if a and a.Health then
							sum += a.Health
							c += 1
						end
					end
					stat = c > 0 and sum / c or 0
				end
				ev += pr * stat
			end
		end)
		baseCache[key] = ev
		return ev
	end

	-- Returns pick {ore = n}, count, score. The forge takes at most 4 different ore types, so try
	-- every set of up to 4 of your best ore types and every ore count, and keep the best score.
	function Best.pick(itemType, maxOres, exactN, minN)
		local types = {}
		for name, n in pairs((forgeCounts())) do
			local m, neu = oreMult(name)
			if not neu and n > 0 then
				types[#types + 1] = { name = name, m = m, n = n }
			end
		end
		table.sort(types, function(a, b)
			return a.m > b.m
		end)
		while #types > 12 do
			table.remove(types) -- only the 12 strongest types are worth combining
		end
		local best = { score = -1 }
		local chosen = {}
		local function evaluate()
			-- ores of the chosen types, strongest first
			local list = {}
			for _, t in ipairs(chosen) do
				list[#list + 1] = t
			end
			table.sort(list, function(a, b)
				return a.m > b.m
			end)
			local sum, n = 0, 0
			local used = {}
			for _, t in ipairs(list) do
				for _ = 1, t.n do
					if n >= maxOres then
						break
					end
					n += 1
					sum += t.m
					used[t.name] = (used[t.name] or 0) + 1
					-- every type in the set must actually be used, else it's a smaller set (tried separately)
					local all = true
					for _, c in ipairs(list) do
						if not used[c.name] then
							all = false
							break
						end
					end
					if n >= math.max(3, minN or 3) and all and (not exactN or n == exactN) then
						local score = (sum / n) * (exactN and 1 or expectedBase(itemType, n))
						if score > best.score then
							local pick = {}
							for k, v in pairs(used) do
								pick[k] = v
							end
							best = { score = score, pick = pick, n = n }
						end
					end
				end
			end
		end
		local function combos(start, depth)
			if depth > 0 then
				evaluate()
			end
			if depth == 4 then
				return
			end
			for i = start, #types do
				chosen[#chosen + 1] = types[i]
				combos(i + 1, depth + 1)
				chosen[#chosen] = nil
			end
		end
		combos(1, 0)
		if not best.pick then
			return {}, 0
		end
		return best.pick, best.n, best.score
	end

	-- Traits. Measured with the game's own maths (Runes:GetRunesFromItem on a made-up item): an
	-- ore's traits switch on at 10% of the mix and climb in a straight line to full strength at
	-- 30%; more than 30% adds nothing. So the strongest item is three trait ores at 30%+ each
	-- (three full sets of traits), with whatever is left over as filler.
	local traitCache
	function Best.traitOres(itemType)
		if not traitCache then
			traitCache = {}
			pcall(function()
				for _, o in pairs(require(RS.Shared.Data.Ore)) do
					if type(o) == 'table' and o.Name and type(o.Traits) == 'table' then
						for _, t in ipairs(o.Traits) do
							for _, w in ipairs(type(t) == 'table' and type(t.Whitelist) == 'table' and t.Whitelist or {}) do
								traitCache[w] = traitCache[w] or {}
								traitCache[w][o.Name] = true
							end
						end
					end
				end
			end)
		end
		return traitCache[itemType] or {}
	end
	-- Returns pick {ore = n}, count, how many ores are at full trait strength.
	function Best.traitPick(itemType, maxOres, exactN, minN)
		local has = Best.traitOres(itemType)
		local counts = forgeCounts()
		local cands, others = {}, {}
		for name, n in pairs(counts) do
			local m, neu = oreMult(name)
			if has[name] then
				cands[#cands + 1] = { name = name, m = m, n = n }
			elseif not neu then
				others[#others + 1] = { name = name, m = m, n = n }
			end
		end
		table.sort(cands, function(a, b)
			return a.m > b.m
		end)
		table.sort(others, function(a, b)
			return a.m > b.m
		end)
		while #cands > 10 do
			table.remove(cands)
		end
		local best = { k = 0, score = -1 }
		local function try(set, n)
			local need = math.ceil(n * 0.3 - 1e-6)
			local pick, used, sum = {}, 0, 0
			for _, t in ipairs(set) do
				if t.n < need then
					return
				end
				pick[t.name] = need
				used += need
				sum += need * t.m
			end
			if used > n then
				return
			end
			-- what is left over: more of the same ores first (no new type), then one filler type
			local left = n - used
			for _, t in ipairs(set) do
				local add = math.min(left, t.n - pick[t.name])
				if add > 0 then
					pick[t.name] += add
					left -= add
					sum += add * t.m
				end
			end
			if left > 0 then
				for _, t in ipairs(#set < 4 and cands or {}) do
					if not pick[t.name] and t.n >= left then
						pick[t.name] = left
						sum += left * t.m
						left = 0
						break
					end
				end
			end
			if left > 0 then
				for _, t in ipairs(#set < 4 and others or {}) do
					if t.n >= left then
						pick[t.name] = left
						sum += left * t.m
						left = 0
						break
					end
				end
			end
			if left > 0 then
				return
			end
			local score = (sum / n) * (exactN and 1 or expectedBase(itemType, n))
			if #set > best.k or (#set == best.k and score > best.score) then
				best = { k = #set, score = score, pick = pick, n = n }
			end
		end
		local lo, hi = exactN or math.max(3, minN or 3), exactN or math.max(3, maxOres)
		for n = lo, hi do
			for i = 1, #cands do
				try({ cands[i] }, n)
				for j = i + 1, #cands do
					try({ cands[i], cands[j] }, n)
					for l = j + 1, #cands do
						try({ cands[i], cands[j], cands[l] }, n)
					end
				end
			end
		end
		if not best.pick then
			return {}, 0, 0
		end
		return best.pick, best.n, best.k
	end
end

local function pickForgeOres(itemType)
	-- A quest that just wants "forge something" (auto forge off): use the 3 cheapest ores,
	-- don't burn your good ones on it.
	if not settings.autoForge and questForgeType() then
		local units = {}
		local okO, OreMod = pcall(function()
			return require(RS.Shared.Data.Ore)
		end)
		local mult = {}
		for _, o in pairs(okO and OreMod or {}) do
			if type(o) == 'table' and o.Name then
				mult[o.Name] = tonumber(o.Multiplier) or 0
			end
		end
		for name, n in pairs((forgeCounts())) do
			for _ = 1, n do
				units[#units + 1] = { name = name, m = mult[name] or 0 }
			end
		end
		table.sort(units, function(a, b)
			return a.m < b.m
		end)
		local pick, got = {}, 0
		for i = 1, math.min(3, #units) do
			pick[units[i].name] = (pick[units[i].name] or 0) + 1
			got += 1
		end
		return pick, got
	end
	local function plentiful(want)
		local list = {}
		for name, n in pairs((forgeCounts())) do
			list[#list + 1] = { name = name, n = n }
		end
		table.sort(list, function(a, b)
			return a.n > b.n
		end)
		local pick, got, kinds = {}, 0, 0
		for _, e in ipairs(list) do
			if got >= want or kinds >= 4 then
				break
			end
			kinds += 1
			local take = math.min(e.n, want - got)
			pick[e.name] = take
			got += take
		end
		return pick, got
	end
	local piece = Piece.want(itemType or settings.forgeType)
	if piece then
		-- Aiming for one piece: exactly the ore count with the best odds for it.
		local n = Piece.count(itemType or settings.forgeType, piece)
		if not n then
			return {}, 0
		end
		local pick, got
		if settings.forgeTraits then
			pick, got = Best.traitPick(itemType or settings.forgeType, n, n)
		end
		if got == n then
			-- (traits first: three ores at 30% each)
		elseif settings.forgeBest then
			pick, got = Best.pick(itemType or settings.forgeType, n, n)
			if got ~= n then
				pick, got = plentiful(n)
			end
		else
			pick, got = plentiful(n)
			if got ~= n then
				pick, got = Best.pick(itemType or settings.forgeType, n, n)
			end
		end
		if got ~= n then
			return {}, 0
		end
		return pick, got
	end
	local moldName, _, moldMin = Mold.plan(itemType or settings.forgeType)
	moldMin = moldName and moldMin or 3
	moldMin = math.max(moldMin, math.clamp(tonumber(settings.forgeMinOres) or 3, 3, 60))
	if settings.forgeTraits then
		local cap = tonumber(settings.forgeOres) or 3
		cap = math.max(cap > 3 and cap or 60, moldMin)
		local pick, got = Best.traitPick(itemType or settings.forgeType, cap, nil, moldMin)
		if got >= moldMin then
			return pick, got
		end
	end
	if settings.forgeBest then
		-- Slider left at the old default (3) would cap "best" at a dagger: treat <=3 as "no cap" (60).
		local cap = tonumber(settings.forgeOres) or 3
		cap = cap > 3 and cap or 60
		cap = math.max(cap, moldMin)
		local pick, got = Best.pick(itemType or settings.forgeType, cap, nil, moldMin)
		if got >= moldMin then
			return pick, got
		end
	end
	local want = math.max(3, tonumber(settings.forgeOres) or 3, moldMin)
	local ores = forgeCounts()
	local list = {}
	for name, n in pairs(ores) do
		list[#list + 1] = { name = name, n = n }
	end
	-- Most plentiful first, so common ore gets used up.
	table.sort(list, function(a, b)
		return a.n > b.n
	end)
	local pick, got, kinds = {}, 0, 0
	for _, e in ipairs(list) do
		if got >= want or kinds >= 4 then -- the forge takes at most 4 ore types
			break
		end
		kinds += 1
		local take = math.min(e.n, want - got)
		pick[e.name] = take
		got += take
	end
	return pick, got
end

-- Auto equip: put on any forged item that beats what's in its slot (empty slot, more ores, or
-- same ores with higher quality).
-- Rank items by what they actually do: the game's own damage (weapons) / health (armor) maths,
-- including ore multiplier and quality, but NOT enhancement: items are compared as if both were
-- +0, so a better freshly forged piece is not hidden behind an old one's upgrade levels (the
-- new one can be enhanced too).
local function itemScore(e)
	if type(e) ~= 'table' then
		return 0
	end
	if (tonumber(e.Upgrade) or 0) ~= 0 then
		local c = table.clone(e)
		c.Upgrade = 0
		e = c
	end
	local v = 0
	pcall(function()
		local E = require(RS.Shared.Data.Equipments)
		local slot = E:GetItemType(e.Type or e.Name)
		if slot == 'Weapon' then
			local a, b = E:CalculateDamage(e)
			v = tonumber(b or a) or 0
		elseif slot == 'Armor' then
			local a, b = E:CalculateHealth(e)
			v = tonumber(b or a) or 0
		end
	end)
	return v
end
local function autoEquipBest(force)
	if not settings.autoEquip and not force then
		return
	end
	local d = data()
	if not d or not d.Inventory then
		return
	end
	local okMod, Equip = pcall(function()
		return require(RS.Shared.Data.Equipments)
	end)
	if not okMod or not Equip then
		return
	end
	-- Weapon, or the armor piece (Helmet / Chestplate / Leggings) — each is its own slot.
	local function slotKey(e)
		local ok, t = pcall(Equip.GetItemType, Equip, e.Type or e.Name)
		if not ok or t == 'Pickaxe' or type(t) ~= 'string' then
			return nil
		end
		if t ~= 'Armor' then
			return t
		end
		local okB, base = pcall(Equip.GetItemBaseType, Equip, e.Type or e.Name)
		base = tostring(okB and base or e.Type)
		for _, piece in ipairs({ 'Helmet', 'Chestplate', 'Leggings' }) do
			if base:find(piece) or tostring(e.Type):find(piece) then
				return piece
			end
		end
		return 'Armor:' .. base
	end
	local best = {}
	for _, e in ipairs(d.Inventory.Equipments or {}) do
		if type(e) == 'table' and e.Type and e.GUID then
			local key = slotKey(e)
			if key and (not best[key] or itemScore(e) > itemScore(best[key])) then
				best[key] = e
			end
		end
	end
	local worn = {}
	for _, w in pairs(d.Equipped or {}) do
		if type(w) == 'table' and w.GUID then
			local key = slotKey(w)
			if key then
				worn[key] = w
			end
		end
	end
	for key, e in pairs(best) do
		local cur = worn[key]
		if not (cur and cur.GUID == e.GUID) and (not cur or itemScore(e) > itemScore(cur) + 0.01) then
			pcall(function()
				return service('CharacterService'):EquipItem(e)
			end)
			setStatus(('equipped %s (%.1f vs %.1f)'):format(tostring(e.Type), itemScore(e), cur and itemScore(cur) or 0))
			task.wait(0.5)
		end
	end
end

local function forgeOnce()
	local FC = controller('ForgeController')
	local forge = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Forge')
	if not FC or not forge then
		setStatus('forge not found')
		return false
	end
	-- (v234) a recipe the user asked for by hand: G.FTForgeRecipe = { type = 'Weapon', ores = { ore = n } }.
	-- Forged once, exactly as given, with no mold.
	local rec = type(G.FTForgeRecipe) == 'table' and type(G.FTForgeRecipe.ores) == 'table' and G.FTForgeRecipe or nil
	G.FTForgeRecipe = nil
	local itemType = rec and rec.type or forgeTypeNow()
	local ores, got
	if rec then
		ores, got = rec.ores, 0
		for _, n in pairs(ores) do
			got += n
		end
	else
		ores, got = pickForgeOres(itemType)
	end
	if got < 3 then
		return false
	end
	local aim, aimNote = Piece.want(itemType), ''
	if aim and (settings.autoForge or not questForgeType()) then
		local _, ch = Piece.count(itemType, aim)
		aimNote = (' — aiming for %s (%.0f%% chance)'):format(aim, ch or 0)
	end
	setStatus(('forging a %s from %d ores%s'):format(itemType, got, aimNote))
	if not tweenTo(standNear(forge, 3)) then
		return false
	end
	task.wait(0.3)
	-- A forge left "open" on our side (e.g. from before a reload) is often already closed on the
	-- server, which then rejects every forge: close it and open a fresh one.
	if FC.ForgeActive and (FC.Sequence == 'OreSelect' or FC.Sequence == 'Close') then
		pcall(function()
			FC:EndForge()
		end)
		task.wait(1.5)
	end
	if not FC.ForgeActive then
		pcall(function()
			service('ProximityService'):Forge(forge)
		end)
		local t0 = os.clock()
		while not FC.ForgeActive and os.clock() - t0 < 8 do
			task.wait(0.2)
		end
	end
	if not FC.ForgeActive then
		setStatus('forge did not open')
		return false
	end
	local t1 = os.clock()
	while not FC.Minigames and os.clock() - t1 < 5 do
		task.wait(0.2)
	end
	hookMinigames(FC)
	task.wait(1.2) -- let the ore-select screen settle
	local before = #(((data() or {}).Inventory or {}).Equipments or {})
	FC.Ores = ores
	FC.ItemType = itemType
	-- The forge request also carries what the forge SCREEN has selected (mold, locked class).
	-- Left over from the other item type (e.g. weapon molds picked by hand, then an armor
	-- forge) the game refuses the whole forge: make the screen agree with what we are making.
	pcall(function()
		local F = controller('UIController').Modules.Forge
		F.selectedItemType = itemType
		F.MoldItem, F.MoldCount, F.LockedClass = nil, 0, nil
		-- the mold target, when we own enough molds to guarantee it and the ores reach its minimum
		local moldName, moldCount, moldMin = Mold.plan(itemType)
		local total = 0
		for _, n in pairs(ores) do
			total += n
		end
		if rec and type(rec.mold) == 'string' and (tonumber(rec.molds) or 0) > 0 then
			-- (v293: a hand-picked recipe can carry its own mold target and count, e.g. the Moon
			-- Crescent Spear with every Weapon Mold owned; the user okays the chance)
			local n = math.min(math.floor(tonumber(rec.molds)), Mold.owned(itemType))
			F.MoldItem, F.MoldCount = rec.mold, n
			G.FTLastMold = ('%s with %d molds (by hand)'):format(rec.mold, n)
		elseif moldName and total >= moldMin and not rec then
			F.MoldItem, F.MoldCount = moldName, moldCount
			G.FTLastMold = ('%s with %d molds'):format(moldName, moldCount)
		else
			G.FTLastMold = nil
		end
	end)
	local oreNote = {}
	for name, n in pairs(ores) do
		oreNote[#oreNote + 1] = tostring(name) .. ' x' .. tostring(n)
	end
	table.sort(oreNote)
	G.FTLastForge = itemType .. ': ' .. table.concat(oreNote, ', ')
	-- The game's own call comes back as soon as the server has answered; refused = it has put the
	-- screen back on ore select by then (no need to sit there 6 seconds to find out).
	local meltBack = false
	task.spawn(function()
		pcall(function()
			FC:ChangeSequence('Melt')
		end)
		meltBack = true
	end)
	-- Wait for the new item to land in the inventory (or give up after 90s).
	local t2 = os.clock()
	local ok = false
	local rejected = false
	while alive and os.clock() - t2 < 90 do
		local now = #(((data() or {}).Inventory or {}).Equipments or {})
		if now > before then
			ok = true
			break
		end
		-- The server refused to start (the game drops back to ore select): stop waiting.
		if FC.Sequence == 'OreSelect' and (os.clock() - t2 > 6 or (meltBack and os.clock() - t2 > 0.5)) then
			rejected = true
			break
		end
		task.wait(0.25)
	end
	if rejected then
		setStatus('forge was rejected — reopening it next time [' .. tostring(G.FTLastForge):sub(1, 160) .. ']')
	end
	task.wait(ok and 1 or 0.3)
	pcall(function()
		FC:EndForge()
	end)
	pcall(function()
		local ui = controller('UIController')
		if ui and ui.Modules and ui.Modules.Forge and ui.Modules.Forge.Close then
			ui.Modules.Forge:Close()
		end
	end)
	-- Closing the forge from code can leave the forge screen's blur on: clear it once it's closed.
	task.delay(1.5, function()
		local FC2 = controller('ForgeController')
		if not (FC2 and FC2.ForgeActive) then
			pcall(function()
				local b = game:GetService('Lighting'):FindFirstChild('ForgeBlur')
				if b and b:IsA('BlurEffect') then
					b.Size = 0
				end
			end)
		end
	end)
	if ok then
		stats.forged += 1
		local made = itemType
		pcall(function()
			local inv = data().Inventory.Equipments
			local newest = inv[#inv]
			local E = require(RS.Shared.Data.Equipments)
			local name = newest.Type or newest.Name
			local base = E:GetItemBaseType(name)
			made = (base and base ~= name) and (name .. ' (' .. base .. ')') or name
			if aimNote ~= '' then
				made = made .. ((base == aim or name == aim) and ' — the piece you wanted' or (' — not a ' .. aim .. ', will try again'))
			end
		end)
		setStatus('forged a ' .. tostring(made))
		forgeFails = 0
		if settings.forgeAlternate then
			forgeAlt = (itemType == 'Weapon') and 'Armor' or 'Weapon'
		end
		task.wait(1)
		pcall(autoEquipBest)
	else
		forgeFails += 1
		local other = (itemType == 'Weapon') and 'Armor' or 'Weapon'
		if rejected then
			forgeBad[itemType] = os.clock() + 600
		end
		if rejected and settings.forgeAlternate and (forgeBad[other] or 0) <= os.clock()
			and not questForgeType() and not Piece.typeOf(settings.forgePiece) then
			forgeFails = 0
			forgeAlt = other
			setStatus(('the forge refused a %s [%s] — making %s only for the next 10 minutes'):format(itemType, tostring(G.FTLastForge):sub(1, 120), other))
		elseif forgeFails >= 2 then
			forgeFails = 0
			G.FTForgeFailUntil = os.clock() + 300
			G.FTForgeDrain = nil
			if settings.forgeAlternate then
				forgeAlt = (itemType == 'Weapon') and 'Armor' or 'Weapon' -- maybe the other type goes through
			end
			setStatus(('forging a %s from %d ores failed twice — back to other work for 5 minutes'):format(itemType, got))
		else
			setStatus('forge timed out')
		end
	end
	return ok
end

---------------------------------------------------------------------------
-- Mobs
---------------------------------------------------------------------------
local function baseName(n)
	return (string.gsub(n, '%d+$', ''))
end
-- Mob attack warning. Every mob gets a BoolValue "Attacking" ~0.6s before its hit lands (then a
-- "ParryWindow" attachment ~0.35s before). Tested on island 2 slimes: stepping out when "Attacking"
-- appears and coming back ~1s later took 0 damage over 6 attacks in a row.
local attackWarn = {} -- [mob model] = os.clock() when its attack started
-- Threat ledger. With strong gear most mobs cannot hurt us faster than we heal, and stepping away
-- from every one of them only costs hits. So an attack is only treated as something to dodge
-- (= put in attackWarn, which every dodge reads) when that KIND of mob has shown it matters:
--   * one of its hits took 12% of our health or more, or
--   * its hit size / its attack rhythm is more than we heal per second (both measured), or
--   * we are under pressure right now: below 45% health, or losing 12% more than we healed
--     over the last 8 seconds (several small mobs at once) - then everything is dodged until
--     health is back over 85%.
-- A kind we have never been hit by is not dodged: its first hit is the measurement.
local Threat = { all = setmetatable({}, { __mode = 'k' }), kind = G.FTThreatKinds or {}, heal = G.FTThreatHeal or 0.01,
	took = {}, healed = {}, pressure = false, told = {} }
G.FTThreatKinds = Threat.kind
G.FTThreat = Threat
function Threat.key(m)
	local k = (string.gsub(m.Name, '%d+$', ''))
	local mu = m:GetAttribute('Mutation')
	return type(mu) == 'string' and (mu .. ' ' .. k) or k
end
function Threat.period(m)
	local k = (string.gsub(m.Name, '%d+$', ''))
	local g = G.FTAtkGap and G.FTAtkGap[k]
	local gap = g and g.n > 0 and g.sum / g.n or 1.5
	return math.clamp(gap + ((G.FTAtkDur or {})[k] or 1), 1, 6)
end
function Threat.keyIs(key)
	if combatStyle() == 'Attack only' then
		return false
	end
	if settings.dodgeWhat == 'Everything' or Threat.pressure then
		return true
	end
	local rec = Threat.kind[key]
	if rec and os.time() - (rec.at or 0) > (rec.hit >= 0.35 and 3600 or 600) then
		Threat.kind[key] = nil
		rec = nil
	end
	return rec ~= nil and (rec.hit >= 0.25 or rec.hit / 3 > Threat.heal + 0.02)
end
function Threat.recIs(rec, m)
	return rec.hit >= 0.25 or rec.hit / Threat.period(m) > Threat.heal + 0.02 -- (a clear net drain: 2%/s more than we heal back)
end
function Threat.is(m)
	if combatStyle() == 'Attack only' then
		return false
	end
	if settings.dodgeWhat == 'Everything' or Threat.pressure then
		return true
	end
	local _, _, hum = char()
	if not hum or hum.MaxHealth <= 0 then
		return true
	end
	local key = Threat.key(m)
	local rec = Threat.kind[key]
	-- (measured against other gear, or long ago: measure again)
	if rec and (os.time() - (rec.at or 0) > (rec.hit >= 0.35 and 3600 or 600) or math.abs((rec.max or 0) - hum.MaxHealth) > 0.15 * hum.MaxHealth) then
		Threat.kind[key] = nil
		rec = nil
	end
	if not rec then
		-- never hit by it: only something far out of our league is dodged unseen
		local mh = m:FindFirstChildOfClass('Humanoid')
		return mh ~= nil and mh.MaxHealth > hum.MaxHealth * 20
	end
	return Threat.recIs(rec, m)
end
task.spawn(function()
	local last, lastMax, lastHum
	local accHeal, accTime = 0, 0
	while alive do
		local dt = task.wait(0.05)
		local _, hrp, hum = char()
		if hrp and hum and hum.Health > 0 and hum.MaxHealth > 0 then
			local h, mx, now = hum.Health, hum.MaxHealth, os.clock()
			if last and lastMax == mx and lastHum == hum then
				local d = (h - last) / mx
				if d < -0.003 then
					Threat.took[#Threat.took + 1] = { now, -d }
					local best, bestD
					for m, t in pairs(Threat.all) do
						local r = m.Parent and (m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart)
						if r and now - t < 3 then
							local dist = (r.Position - hrp.Position).Magnitude
							if dist <= 30 and (not bestD or dist < bestD) then
								best, bestD = m, dist
							end
						end
					end
					-- (a shot or marker we chose not to step out of a moment ago: the damage is its)
					local hz = Threat.hazAt
					local key, per
					if hz and now - hz.t < 1.5 then
						key, per = hz.key, 3
					elseif best then
						key, per = Threat.key(best), Threat.period(best)
					end
					if key then
						local rec = Threat.kind[key] or { hit = -d, n = 0 }
						rec.hit = rec.n == 0 and -d or (rec.hit * 0.6 + -d * 0.4)
						rec.n += 1
						rec.at, rec.max = os.time(), mx
						Threat.kind[key] = rec
						local is = rec.hit >= 0.25 or rec.hit / per > Threat.heal + 0.02
						if Threat.told[key] ~= is then
							Threat.told[key] = is
							statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. (is
								and ('now dodging %s: it hits for %.1f%% of your health every ~%.1fs, you heal %.1f%%/s'):format(key, rec.hit * 100, per, Threat.heal * 100)
								or ('not dodging %s: %.1f%% per hit every ~%.1fs is less than the %.1f%%/s you heal'):format(key, rec.hit * 100, per, Threat.heal * 100))
						end
					end
				elseif d > 0 and d < 0.5 then
					Threat.healed[#Threat.healed + 1] = { now, d }
					accHeal += d
				end
				if h < mx - 0.5 then
					accTime += dt
				end
			end
			if accTime >= 5 then
				-- healing per second, over time spent below full health
				Threat.heal = math.max(0.002, Threat.heal * 0.5 + (accHeal / accTime) * 0.5)
				G.FTThreatHeal = Threat.heal
				accHeal, accTime = 0, 0
			end
			local tk, hl = 0, 0
			while Threat.took[1] and now - Threat.took[1][1] > 8 do
				table.remove(Threat.took, 1)
			end
			while Threat.healed[1] and now - Threat.healed[1][1] > 8 do
				table.remove(Threat.healed, 1)
			end
			for _, e in ipairs(Threat.took) do
				tk += e[2]
			end
			for _, e in ipairs(Threat.healed) do
				hl += e[2]
			end
			local frac = h / mx
			local was = Threat.pressure
			if frac < 0.45 or (tk - hl > 0.12 and frac < 0.8) then
				Threat.pressure = true
			elseif frac > 0.85 then
				Threat.pressure = false
			end
			if Threat.pressure ~= was and settings.dodgeWhat ~= 'Everything' then
				statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. (Threat.pressure
					and ('under pressure (health %.0f%%, lost %.0f%% / healed %.0f%% in 8s): dodging everything'):format(frac * 100, tk * 100, hl * 100)
					or 'health back over 85%: dodging only threats again')
			end
			last, lastMax, lastHum = h, mx, hum
		else
			last = nil
		end
	end
end)
G.FTAtkDur = G.FTAtkDur or {}
-- [kind] = { min, max }: seconds into its attack at which the hit lands. Measured on island 3 with a
-- great sword (hitbox 0.95s after the press): treating the WHOLE attack as "do not stand there"
-- left no gap to swing in - a Diamond Spider attacks for 1.7s and starts again ~1s later - and 31
-- of 75 swings missed, 28 of them because we were standing clear at hitbox time. But its hit only
-- lands 1.2-1.4s in: the first second of the wind-up, and everything after the hit, is free.
G.FTAtkHit3 = G.FTAtkHit3 or { ['Crystal Spider'] = { min = 0.5, max = 0.85, n = 0, seed = true }, ['Diamond Spider'] = { min = 1.15, max = 1.45, n = 0, seed = true } }
G.FTAtkHit = G.FTAtkHit3
local Attack = { flag = setmetatable({}, { __mode = 'k' }), off = setmetatable({}, { __mode = 'k' }), dur = G.FTAtkDur, hit = nil, d0 = setmetatable({}, { __mode = 'k' }) }
pcall(function()
	if G.FTAttackWarnConn then
		G.FTAttackWarnConn:Disconnect()
	end
	G.FTAttackWarnConn = workspace:WaitForChild('Living', 10).DescendantAdded:Connect(function(d)
		if d.Name == 'Attacking' and d:IsA('ValueBase') then
			local m = d.Parent
			while m and m.Parent ~= workspace.Living do
				m = m.Parent
			end
			-- (players live in workspace.Living too and get the same flag when THEY swing: counting our
			-- own made the bot dodge away from itself after every swing of its weapon or pickaxe)
			if m and m:GetAttribute('IsNpc') and not Players:GetPlayerFromCharacter(m) then
				local t0 = os.clock()
				Threat.all[m] = t0
				if Threat.is(m) then
					attackWarn[m] = t0
				end
				Attack.flag[m] = d
				if Attack.off[m] and t0 - Attack.off[m] < 8 then
					local k = (string.gsub(m.Name, '%d+$', ''))
					G.FTAtkGap = G.FTAtkGap or {}
					local g = G.FTAtkGap[k] or { min = 99, sum = 0, n = 0 }
					g.min = math.min(g.min, t0 - Attack.off[m])
					g.sum += t0 - Attack.off[m]
					g.n += 1
					G.FTAtkGap[k] = g
				end
				Attack.off[m] = nil
				do
					local _, myRoot = char()
					local mr = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
					Attack.d0[m] = myRoot and mr and (myRoot.Position - mr.Position).Magnitude or nil
				end
				d.AncestryChanged:Once(function()
					if Attack.flag[m] == d then
						Attack.flag[m] = nil
						Attack.off[m] = os.clock()
					end
					local dur = os.clock() - t0
					if dur > 0.3 and dur < 6 then
						local k = (string.gsub(m.Name, '%d+$', ''))
						Attack.dur[k] = math.max(Attack.dur[k] or 0, dur)
					end
				end)
			end
		end
	end)
end)
local ATTACK_WINDOW = 1.0 -- seconds from "Attacking" until the swing is over (when nothing better is known)
-- When is mob m's current attack over? Measured on island 3: a Crystal Spider's flag lasts ~1.0s
-- and its hit lands at 0.6-0.8s, but a Diamond Spider's lasts up to 1.65s with the hit at ~1.3s,
-- and a Prismarine Spider's up to 4s. Going back in after a flat 1.0s walked into every Diamond
-- Spider hit. So: while the flag is up, the longest this kind has ever kept it up; once it is
-- gone, a moment after it went.
Attack.hit = G.FTAtkHit
-- Measured (23 Diamond Spider attacks): started with us 16+ studs away it is a SPIT - released 0.63-
-- 0.72s in, aimed at where we stand right then, flying 100 studs/s; started closer it is a BITE that
-- lands 1.15-1.45s in. A spit from under ~20 studs cannot be side-stepped (the hit is decided on
-- the server before our step gets there): 4 of 5 hits in one run were exactly that.
if Attack.hit['Diamond Spider'] then
	Attack.hit['Diamond Spider'].far = { d = 15, min = 0.6, max = 0.75 }
end
-- a mob near us that is about to shoot (position), so the caller can get out to dodging range
function Attack.rangedThreat(radius)
	local _, hrp = char()
	if not hrp then
		return nil
	end
	local now = os.clock()
	for m, t in pairs(attackWarn) do
		local hw = Attack.hit[(string.gsub(m.Name, '%d+$', ''))]
		local far = hw and hw.far
		if far and (Attack.d0[m] or 0) >= far.d - 2 and now - t < far.max + 0.1 then
			local r = m.Parent and (m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart)
			if r and (r.Position - hrp.Position).Magnitude < radius then
				return r.Position
			end
		end
	end
	return nil
end
task.spawn(function()
	-- learn it: we lost health while exactly one mob within 16 studs was mid-attack
	local last
	while alive do
		task.wait()
		local _, hrp, hum = char()
		if hrp and hum then
			if last and hum.Health < last - 1 and hum.Health > 0 then
				local now = os.clock()
				local n, kk, age = 0, nil, nil
				for m, t in pairs(attackWarn) do
					local r = m.Parent and (m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart)
					if r and (r.Position - hrp.Position).Magnitude <= 16 then
						n += 1
						kk, age = (string.gsub(m.Name, '%d+$', '')), now - t
					end
				end
				if n == 1 and not (Attack.hit[kk] and Attack.hit[kk].far) and age > 0.15 and age < math.max(1.2, (Attack.dur[kk] or 0) + 0.3) then
					local w = Attack.hit[kk] or { min = age, max = age, n = 0 }
					w.s = w.s or {}
					w.s[#w.s + 1] = age
					if #w.s > 60 then
						table.remove(w.s, 1)
					end
					w.n += 1
					if #w.s >= 8 then
						-- (one stray sample - damage from something else at that moment - must not move it)
						local sorted = table.clone(w.s)
						table.sort(sorted)
						w.min = sorted[math.max(1, math.floor(#sorted * 0.15 + 0.5))]
						w.max = sorted[math.min(#sorted, math.ceil(#sorted * 0.85))]
					elseif w.n == #w.s then
						-- (a kind with no measured window yet: what we have seen so far)
						w.min, w.max = math.min(w.min, age), math.max(w.max, age)
					end
					Attack.hit[kk] = w
				end
			end
			last = hum.Health
		else
			last = nil
		end
	end
end)
function Attack.ends(m, t)
	local off = Attack.off[m]
	if off and off >= t then
		return off + 0.15
	end
	local k = (string.gsub(m.Name, '%d+$', ''))
	return t + math.max(ATTACK_WINDOW, Attack.dur[k] or 0) + 0.15
end
local function mobRoot(m)
	return m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart or m:FindFirstChild('Head')
		or m:FindFirstChild('Torso') or m:FindFirstChildWhichIsA('BasePart')
end
-- Closest mob (within radius) whose attack is winding up right now -> its position, time it ends.
local function attackThreat(radius)
	local _, hrp = char()
	if not hrp then
		return nil
	end
	local now = os.clock()
	local bestPos, bestEnd, bestD
	for m, t in pairs(attackWarn) do
		local ends = m.Parent and Attack.ends(m, t)
		if not ends or now > ends then
			attackWarn[m] = nil
		else
			local r = mobRoot(m)
			local d = r and (r.Position - hrp.Position).Magnitude
			if d and d <= radius and (not bestD or d < bestD) then
				bestPos, bestEnd, bestD = r.Position, ends, d
			end
		end
	end
	return bestPos, bestEnd
end
-- a mob that started an attack on us in the last second (we may already have stepped clear of it)
MineHooks.attacker = function()
	local _, hrp = char()
	if not hrp then
		return nil
	end
	local now = os.clock()
	for m, t in pairs(attackWarn) do
		if now - t < 1 and m.Parent then
			local r = mobRoot(m)
			local h = m:FindFirstChildOfClass('Humanoid')
			if r and h and h.Health > 0 and h.MaxHealth < 1e8 then
				local d = (r.Position - hrp.Position).Magnitude
				if d <= 40 then
					return { m = m, r = r, h = h, d = d }
				end
			end
		end
	end
	return nil
end
-- "Slime" also matches variants like "Blazing Slime"; "Skeleton Rogue" matches "Elite Rogue Skeleton".
local function mobMatches(name, filter)
	if filter == nil or filter == 'Any' then
		return true
	end
	name = string.lower(name)
	if name == string.lower(filter) then
		return true
	end
	for word in string.gmatch(string.lower(filter), '%S+') do
		if not string.find(' ' .. name .. ' ', ' ' .. word .. ' ', 1, true) then
			return false
		end
	end
	return true
end

-- A mob with more than 12x our own health (island 3 on a 342 hp character: Prismarine Spider 7000,
-- Yeti 11000) is a mini boss: area slams with no warning to step out of, and minutes of trading
-- hits to bring it down. Left alone unless it is the only thing to fight (a tower wave's boss) or
-- it is picked by name as the Target.
local function mobTooBig(h)
	do
		return false -- (v246, the user: remove everything that makes the bot leave a mob alone - "the health pool, strong mob, etc")
	end
	local _, _, hum = char()
	if hum == nil then
		return false
	end
	if h.Parent ~= nil and string.find(h.Parent.Name, 'Prismarine', 1, true) ~= nil then
		return true
	end
	-- Size alone no longer makes a mob "too big" (measured: a 7,800 HP Samurai Ape that hits for
	-- 2.4% of our health was walked away from, rock after rock). A big mob is only left alone when
	-- it is also a threat: its hits are on record as outpacing our healing, or it has never hit us
	-- and is over 20x our health.
	if h.MaxHealth > math.min(hum.MaxHealth * 8, 5000) then
		return h.Parent == nil or Threat.is(h.Parent)
	end
	return false
end

-- Mobs no route was found to (measured: stood in town for minutes "fighting" apes 500-750 studs
-- away on another level, every route "no path"). Left alone for 3 minutes; quests see them as absent.
local mobNoRoute = setmetatable({}, { __mode = 'k' })
G.FTMobNoRoute = mobNoRoute
-- The "max mob health" slider, except for the mobs a quest the user FOCUSED asks for: picking that
-- quest is the user saying to fight them (measured: focus on a Monk Panda 10,000 HP / Samurai Ape
-- 7,100-9,200 HP quest with the slider on 7,018 = standing idle, nothing allowed).
local function mobCap(m)
	do
		return 0 -- (v246: the max mob health slider no longer excludes anything)
	end
	local cap = tonumber(settings.maxMobHp) or 0
	if cap > 0 and settings.focusQuest ~= 'Auto' and G.FTQuestLock == settings.focusQuest
		and type(QS.mobTarget) == 'string' and QS.mobTarget ~= 'Any' and mobMatches(baseName(m.Name), QS.mobTarget) then
		return 0
	end
	return cap
end
local function mobList()
	local _, hrp = char()
	local living = workspace:FindFirstChild('Living')
	local list = {}
	if not living or not hrp then
		return list
	end
	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			players[p.Character] = true
		end
	end
	-- A saved "Target" that doesn't live on this island (e.g. Zombie after moving to island 2)
	-- used to leave it idle forever: fall back to any mob.
	local filter = dropTarget() or QS.mobTarget or settings.mobFilter
	if filter ~= 'Any' then
		local exists = false
		for _, m in ipairs(living:GetChildren()) do
			if m:GetAttribute('IsNpc') and mobMatches(baseName(m.Name), filter) then
				exists = true
				break
			end
		end
		if not exists then
			filter = 'Any'
		end
	end
	for _, m in ipairs(living:GetChildren()) do
		if not players[m] and m:GetAttribute('IsNpc') then
			local h = m:FindFirstChildOfClass('Humanoid')
			local r = mobRoot(m)
			local cap = mobCap(m)
			if h and r and h.Health > 0 and m:GetAttribute('KillCredited') ~= true
				and (mobNoRoute[m] or 0) < os.clock()
				and not mobIgnored(m)
				and mobMatches(baseName(m.Name), filter)
				and (cap <= 0 or h.MaxHealth <= cap)
				and h.MaxHealth < 1e8 and not m.Name:find('Dummy') -- training dummies never die
				and not Deadly.is(m) -- never pick a fight with a mob that has killed us (quests included)
				and not string.find(m.Name, 'Bomber', 1, true) -- (they explode in melee range)
				and not Lava.at(r.Position) -- (standing in lava: we would have to stand in it too)
				and (G.FTAbyssAll or workspace:GetAttribute('AbyssRun') ~= true or (r.Position - hrp.Position).Magnitude <= 800) -- (v251: only this floor's mobs)
			then
				list[#list + 1] = { m = m, h = h, r = r, d = (r.Position - hrp.Position).Magnitude, big = mobTooBig(h) }
			end
		end
	end
	-- (v240) waiting where the quest's mob lives (G.FTCampStay): only mobs of that area count -
	-- within 260 studs sideways and on the same level (v239 measured the straight distance, and
	-- the bot flew up to the Frostburn Onis one floor above the spirit area).
	if G.FTCamp and type(G.FTCampStay) == 'table' and G.FTCampStay[tostring(G.FTCampFor)] then
		local camp, kept = G.FTCamp, {}
		for _, e in ipairs(list) do
			local dv = e.r.Position - camp
			if math.abs(dv.Y) <= 45 and Vector3.new(dv.X, 0, dv.Z).Magnitude <= 260 then
				kept[#kept + 1] = e
			end
		end
		list = kept
	end
	if filter == 'Any' then
		-- (and nothing standing within 45 studs of one, while there is anything else to fight:
		-- its area attacks hit us there whatever we do)
		local small, clear = {}, {}
		for _, e in ipairs(list) do
			if not e.big then
				small[#small + 1] = e
				local ok = true
				for _, b in ipairs(list) do
					if b.big and (b.r.Position - e.r.Position).Magnitude < 45 then
						ok = false
						break
					end
				end
				if ok then
					clear[#clear + 1] = e
				end
			end
		end
		if #clear > 0 then
			list = clear
		elseif #small > 0 then
			list = small
		end
	end
	-- (v259, asked for: "when its like this, mobs all over, single out the further enemies that are
	-- by themselves and kill those first".) With 6 or more mobs about, the ones with no other mob
	-- within 16 studs come first (nearest of those first), then the rest by distance.
	if #list >= 6 then
		for _, a in ipairs(list) do
			local nb = 0
			for _, b in ipairs(list) do
				if b ~= a and (b.r.Position - a.r.Position).Magnitude <= 16 then
					nb += 1
				end
			end
			a.alone = nb == 0
		end
		table.sort(list, function(a, b)
			if a.alone ~= b.alone then
				return a.alone
			end
			return a.d < b.d
		end)
		if list[1] and list[1].alone then
			G.FTAlonePicks = (G.FTAlonePicks or 0) + 1
		end
		return list
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	return list
end

-- Special enemies picked to hunt (the game marks them with a "Mutation" attribute: Heaven, Hell,
-- Lucky...): nearest first. They go before quests and farming.
local huntSkip = {} -- [modifier .. ' ' .. kind] = os.clock() until which it is left alone (it killed us)
local function specialTargets()
	local want = settings.huntSpecial
	local list = {}
	if type(want) ~= 'table' or not next(want) then
		return list
	end
	local _, hrp = char()
	local living = workspace:FindFirstChild('Living')
	if not hrp or not living then
		return list
	end
	for _, m in ipairs(living:GetChildren()) do
		local mut = m:GetAttribute('Mutation')
		if mut and want[mut] and m:GetAttribute('IsNpc') and m:GetAttribute('KillCredited') ~= true then
			local h = m:FindFirstChildOfClass('Humanoid')
			local r = mobRoot(m)
			local key = tostring(mut) .. ' ' .. (string.gsub(m.Name, '%d+$', ''))
			if h and r and h.Health > 0 and h.MaxHealth < 1e8 and not Lava.at(r.Position) and not Deadly.is(m)
				and (huntSkip[key] or 0) < os.clock() then
				list[#list + 1] = { m = m, h = h, r = r, d = (r.Position - hrp.Position).Magnitude, mut = mut, hunt = true, key = key }
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	return list
end

-- Event meteors (Inferno / Prismatic / Fichillium / comet rocks). They are not in workspace.Rocks:
-- the game's CometRockController knows where each one is, they last 90 seconds, and they are broken
-- with the pickaxe from within 6 studs (CometRocks.HitRange). Standing within 5 studs of one as it
-- LANDS kills (KillRadius), so we wait 12 studs off until it has been there a few seconds.
local Meteor = { seen = {}, bad = {} }
function Meteor.list()
	local out = {}
	local CC = controller('CometRockController')
	local ok, ps = pcall(function()
		return CC:Positions()
	end)
	local _, hrp = char()
	if ok and type(ps) == 'table' and hrp then
		for _, pos in ipairs(ps) do
			if typeof(pos) == 'Vector3' then
				local key = ('%d,%d,%d'):format(pos.X, pos.Y, pos.Z)
				Meteor.seen[key] = Meteor.seen[key] or os.clock()
				if (Meteor.bad[key] or 0) < os.clock() then
					out[#out + 1] = { pos = pos, key = key, d = (pos - hrp.Position).Magnitude }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	return out
end
function Meteor.step()
	if not settings.mineMeteors then
		return false
	end
	local t = Meteor.list()[1]
	if not t or t.d > 1500 then
		return false
	end
	local function there()
		for _, e in ipairs(Meteor.list()) do
			if (e.pos - t.pos).Magnitude < 4 then
				return true
			end
		end
		return false
	end
	local _, hrp = char()
	if not hrp then
		return false
	end
	setStatus(('meteor (%.0f studs)'):format(t.d))
	local flat = (hrp.Position - t.pos) * Vector3.new(1, 0, 1)
	local dir = flat.Magnitude > 1 and flat.Unit or Vector3.new(1, 0, 0)
	local function spot(dist)
		local at = t.pos + dir * dist
		local g = groundAt(at + Vector3.new(0, 8, 0))
		local y = (g and math.abs(g.Y - 3 - t.pos.Y) < 12) and g.Y or t.pos.Y + 3 -- (groundAt already stands us 3 up)
		local sp = Vector3.new(at.X, y, at.Z)
		return CFrame.lookAt(sp, Vector3.new(t.pos.X, sp.Y, t.pos.Z))
	end
	if t.d > 16 then
		tweenTo(spot(12), { abort = function()
			return not settings.mineMeteors or not there()
		end })
	end
	-- (not under it while it lands)
	while alive and settings.mineMeteors and there() and os.clock() - (Meteor.seen[t.key] or 0) < 4 do
		task.wait(0.2)
	end
	if not there() then
		return true
	end
	local _, h2 = char()
	if not h2 then
		return true
	end
	h2.CFrame = spot(3.5)
	h2.AssemblyLinearVelocity = Vector3.zero
	local tool = equip('Pickaxe')
	local t0 = os.clock()
	local swings = 0
	while alive and settings.mineMeteors and there() and os.clock() - t0 < 60 do
		local _, h3, hum = char()
		if not h3 or not hum or hum.Health <= 0 or hum.Health / math.max(1, hum.MaxHealth) < 0.3 then
			break
		end
		if ((h3.Position - t.pos) * Vector3.new(1, 0, 1)).Magnitude > 5 then
			h3.CFrame = spot(3.5)
			h3.AssemblyLinearVelocity = Vector3.zero
		else
			h3.CFrame = CFrame.lookAt(h3.Position, Vector3.new(t.pos.X, h3.Position.Y, t.pos.Z))
		end
		if not (tool and tool.Parent == LocalPlayer.Character) then
			tool = equip('Pickaxe')
		end
		swing(tool)
		swings += 1
		setStatus(('breaking meteor (%d swings)'):format(swings))
		task.wait(0.35)
	end
	if there() then
		-- still standing after a minute of swings (or we had to leave): not this one again for a while
		Meteor.bad[t.key] = os.clock() + 45
		statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('meteor not broken after %d swings'):format(swings)
	else
		statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('meteor broken (%d swings)'):format(swings)
	end
	return true
end

local function lowHp()
	local _, _, hum = char()
	return hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth * 100 < (tonumber(settings.retreatHp) or 35)
end

-- Low health: tween back to spawn (mobs don't follow that far) and wait to heal to 90%.
local function retreatAndHeal()
	local spawn = workspace:FindFirstChild('SpawnLocation')
	if spawn and spawn:IsA('BasePart') then
		setStatus('low health — retreating to spawn')
		tweenTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
	end
	local t0 = os.clock()
	while alive and (settings.autoMobs or QS.wantMobs) and os.clock() - t0 < 120 do
		local _, _, hum = char()
		if not hum or hum.Health <= 0 then
			return
		end
		local pct = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth * 100 or 100
		if pct >= math.clamp(tonumber(settings.healTo) or 60, 5, 100) then
			return
		end
		setStatus(('healing at spawn (%.0f%%)'):format(pct))
		task.wait(1)
	end
end

-- Auto block / parry. Mobs play a wind-up animation, then the hit lands. The parry window is
-- a short time before the hit, so it learns each attack animation's hit time (from when damage /
-- the Parry / BlockHit effect actually happens) and starts the block "parry lead" before it.
local Block = {}
do
	local blockUntil = 0
	-- (v303, measured standing still with auto block off: a press less than ~0.16 s after our own
	-- let-go never comes up - 0.04-0.12 s after letting go failed 6 of 6 even with the guard up 0.5 s
	-- before, 0.26-0.30 s worked. So every let-go is timed, and a press waits out that gap.)
	function Block.stop(tc)
		Block.relAt = os.clock()
		pcall(tc.StopBlock, tc)
	end
	if type(G.FTBlockConns) == 'table' then
		for _, c in ipairs(G.FTBlockConns) do
			pcall(function()
				c:Disconnect()
			end)
		end
	end
	local blockConns = {}
	G.FTBlockConns = blockConns
	local hookedAnims = setmetatable({}, { __mode = 'k' })
	G.FTHitDelay = G.FTHitDelay or {} -- [animation id] = seconds from wind-up start to the hit
	local hitDelay = G.FTHitDelay
	local pending = {} -- recent attack wind-ups near us: { id, t }
	-- The parry cue (v190). The game adds an Attachment "ParryWindow" (the shine) to the mob's root
	-- part a moment before the hit. The user's own testing: blocking exactly on the shine, or just
	-- before it, always parries; after it is too late. The old timing (0.2 s before the learned hit)
	-- came ~0.15 s AFTER the shine. So: learn, per attack animation, how long after its start the
	-- shine appears, and block "parry lead" before that. An animation not seen yet is blocked the
	-- instant its shine appears.
	G.FTShineDelay = G.FTShineDelay or {}
	G.FTShineGap2 = G.FTShineGap2 or {} -- [animation id] = { d = seconds from the shine to the hit, n }
	Block.cues = {}
	Block.lastShine = setmetatable({}, { __mode = 'k' }) -- [mob] = when it last shone
	G.FTShinePeriod = G.FTShinePeriod or {} -- [mob kind] = seconds between its attacks (shine to shine)
	Block.period = G.FTShinePeriod
	G.FTShineCombo = G.FTShineCombo or {} -- [mob kind] = longest gap between the hits of one combo
	Block.combo = G.FTShineCombo
	G.FTShineIvB = G.FTShineIvB or {} -- [mob kind] = { { iv = seconds from a shine to the next, n = times seen, id } }
	Block.ivs = G.FTShineIvB -- (also [kind .. '#' .. id of the gap before] = the same, after that gap)
	Block.prevB = setmetatable({}, { __mode = 'k' }) -- [mob] = which of its kind's gaps came before its last shine
	G.FTShineGmin = G.FTShineGmin or {} -- [mob kind] = shortest shine-to-hit time used for it
	Block.gmin = G.FTShineGmin
	Block.hits = {} -- expected hit times still to be parried, soonest first
	local shineDelay = G.FTShineDelay
	G.FTParryStats = { shines = 0, early = 0, onShine = 0, parry = 0, blockHit = 0, presses = 0, by = {} }
	local PStats = G.FTParryStats
	-- (v257, asked for: "a system that learns".) Traced in the Abyss: every parry came 0.34-0.36 s
	-- after the mob's shine - the one timing the press assumed - while the hits that got through came
	-- 0.05-0.3 s or 0.5-0.9 s after it (Monk Panda 0.87, Savage Ape 0.65, Crystal Centipede 0.76).
	-- Those were never learned: only a parry taught the timing, so a mob that never got parried
	-- stayed wrong forever. Now every parry AND every hit taken with exactly one shine waiting (so
	-- we know whose it was) is a sample of that mob's shine-to-hit time, kept per mob kind and
	-- attack animation, saved to a file so it carries over runs and sessions. At a shine, the times
	-- that mob has actually hit at are each given their own press.
	local LEARN_PATH = 'PlayerTools/forgetools_parrylearn.json'
	if type(G.FTGapLearn) ~= 'table' then
		G.FTGapLearn = {}
		pcall(function()
			if isfile(LEARN_PATH) then
				local t = HttpService:JSONDecode(readfile(LEARN_PATH))
				if type(t) == 'table' then
					G.FTGapLearn = t
				end
			end
		end)
	end
	local Learn = { dirty = false }
	Block.Learn = Learn
	function Learn.add(kind, id, age, how)
		if type(kind) ~= 'string' or type(age) ~= 'number' or age < 0.03 or age > 1 then
			return
		end
		for _, key in ipairs({ kind .. '|' .. tostring(id or ''), kind }) do
			local list = G.FTGapLearn[key]
			if type(list) ~= 'table' then
				list = {}
				G.FTGapLearn[key] = list
			end
			list[#list + 1] = math.floor(age * 100 + 0.5) / 100
			while #list > 40 do
				table.remove(list, 1)
			end
		end
		Learn.dirty = true
		PStats.learned = (PStats.learned or 0) + 1
		if how == 'hit' then
			PStats.learnedHit = (PStats.learnedHit or 0) + 1
		end
	end
	-- The times (seconds after the shine) this mob's hits have landed at: samples within 0.12 s of
	-- each other are one timing; a timing counts once it has 3 samples and a fifth of all of them.
	function Learn.modes(kind, id)
		local list = G.FTGapLearn[kind .. '|' .. tostring(id or '')]
		if type(list) ~= 'table' or #list < 4 then
			list = G.FTGapLearn[kind]
		end
		if type(list) ~= 'table' or #list < 4 then
			return nil
		end
		local sorted = table.clone(list)
		table.sort(sorted)
		local out, i = {}, 1
		while i <= #sorted do
			local j = i
			while j < #sorted and sorted[j + 1] - sorted[j] < 0.12 and sorted[j + 1] - sorted[i] < 0.2 do
				j += 1
			end
			local cnt = j - i + 1
			if cnt >= 3 and cnt >= #sorted / 5 then
				out[#out + 1] = sorted[i + math.floor(cnt / 2)]
			end
			i = j + 1
		end
		return #out > 0 and out or nil
	end
	task.spawn(function()
		while alive and G.FTBlockConns == blockConns do
			task.wait(30)
			if Learn.dirty then
				Learn.dirty = false
				pcall(function()
					writefile(LEARN_PATH, HttpService:JSONEncode(G.FTGapLearn))
				end)
			end
		end
	end)

	-- A hit / parry just happened: credit it to the most recent wind-up 0.2-1.6 s ago.
	local function learn()
		local now = os.clock()
		local bi
		for i, p in ipairs(pending) do
			local dt = now - p.t
			if dt > 0.2 and dt < 1.6 and (not bi or p.t > pending[bi].t) then
				bi = i
			end
		end
		if bi then
			local p = table.remove(pending, bi)
			local dt = now - p.t
			local old = hitDelay[p.id]
			hitDelay[p.id] = old and (old * 0.6 + dt * 0.4) or dt
		end
		for i = #pending, 1, -1 do
			if now - pending[i].t > 2 then
				table.remove(pending, i)
			end
		end
	end
	pcall(function()
		blockConns[#blockConns + 1] = workspace:WaitForChild('Debris', 5).ChildAdded:Connect(function(x)
			if x.Name == 'Parry' or x.Name == 'BlockHit' then
				Block.fxAt = os.clock()
				if x.Name == 'Parry' then
					PStats.parry += 1
				else
					PStats.blockHit += 1
				end
				-- (which kind of press earned it, and how long after the press)
				-- shine -> hit, per attack animation: the oldest cue still waiting for its hit
				for i, cue in ipairs(Block.cues) do
					local g = os.clock() - cue.t
					if g > 0.15 and g < 0.7 then
						G.FTHitGapLog = G.FTHitGapLog or {}
						if #G.FTHitGapLog < 800 then
							table.insert(G.FTHitGapLog, { ev = x.Name, k = cue.k, id = cue.id, age = g, g = cue.g, live = #Block.cues, press = os.clock() - (Block.pressedAt or 0) })
						end
						Learn.add(cue.k, cue.id, g, 'parry')
						if cue.id then
							local rec = G.FTShineGap2[cue.id]
							if rec then
								rec.d = rec.d * 0.6 + g * 0.4
								rec.n += 1
							else
								G.FTShineGap2[cue.id] = { d = g, n = 1 }
							end
						end
						table.remove(Block.cues, i)
						break
					end
				end
				if Block.pressedAt and os.clock() - Block.pressedAt < 1.2 then
					local k = tostring(Block.pressKind) .. ' ' .. x.Name
					local b = PStats.by[k] or { n = 0, sum = 0 }
					b.n += 1
					b.sum += os.clock() - Block.pressedAt
					PStats.by[k] = b
				end
				learn()
			end
		end)
	end)
	local hpConn, hpChar
	local function watchHealth()
		local c, _, hum = char()
		if c and hum and c ~= hpChar then
			hpChar = c
			-- (v305: press-to-guard time learned from every press - the early let-go ends the run loop
			-- before the guard shows, so the loop itself no longer sees most of them)
			pcall(function()
				local st0 = c:WaitForChild('Status', 5)
				blockConns[#blockConns + 1] = st0.ChildAdded:Connect(function(x)
					local pa = Block.pressedAt
					if x.Name == 'Blocking' and pa and os.clock() - pa < 0.6 and pa ~= Block.latFor then
						Block.latFor = pa
						Block.upAt = os.clock()
						local l = G.FTBlockLat
						l[#l + 1] = math.floor((os.clock() - pa) * 1000 + 0.5) / 1000
						while #l > 40 do
							table.remove(l, 1)
						end
						PStats.lat = Block.lat(0.5)
					end
				end)
			end)
			if hpConn then
				hpConn:Disconnect()
			end
			local last = hum.Health
			hpConn = hum.HealthChanged:Connect(function(h)
				if h < last - 0.5 then
					-- (v256 trace: which shines were waiting when a hit got through, and how old)
					G.FTHitGapLog = G.FTHitGapLog or {}
					if #G.FTHitGapLog > 800 then
						table.clear(G.FTHitGapLog)
					end
					do
						local nowH, live = os.clock(), 0
						for _, cue in ipairs(Block.cues) do
							if nowH - cue.t < 1 then
								live += 1
							end
						end
						for _, cue in ipairs(Block.cues) do
							if nowH - cue.t < 1 then
								table.insert(G.FTHitGapLog, { ev = 'hit', k = cue.k, id = cue.id, age = nowH - cue.t, g = cue.g, live = live, dmg = last - h,
									press = nowH - (Block.pressedAt or 0) })
							end
						end
						if live == 1 then
							for _, cue in ipairs(Block.cues) do
								if nowH - cue.t < 1 and not cue.learned then
									cue.learned = true
									Learn.add(cue.k, cue.id, nowH - cue.t, 'hit')
								end
							end
						end
						if live == 0 then
							local nearK = {}
							pcall(function()
								local _, hN = char()
								local _, lst = mobsNear(hN.Position, 60)
								for _, e in ipairs(lst) do
									nearK[#nearK + 1] = ('%s %.0f'):format(baseName(e.m.Name), (e.r.Position - hN.Position).Magnitude)
								end
							end)
							table.insert(G.FTHitGapLog, { ev = 'hit', k = 'NO SHINE', age = -1, live = 0, dmg = last - h, press = nowH - (Block.pressedAt or 0), near = table.concat(nearK, ', ') })
						end
					end
					learn()
				end
				last = h
			end)
			blockConns[#blockConns + 1] = hpConn
		end
	end

	local stopping = false
	local function holdBlock(untilT, kind)
		local tc = controller('ToolController')
		local ch = LocalPlayer.Character
		if not tc or not (ch and ch:FindFirstChild('Weapon')) then
			return
		end
		-- (v191. Measured with v190: 51 shines, only 8 parries and 11 plain blocks. A parry is a fresh
		-- press: the game's StartBlock does nothing while a block is already held, and the old hold ran
		-- 0.7 s past the shine, into the next mob's attack. So every cue is its own press - let go and
		-- press again - unless the last press was under 0.15 s ago, which is the same moment.)
		local nowB = os.clock()
		if tc.isBlocking and nowB - (Block.pressedAt or 0) >= 0.15 then
			Block.stop(tc)
		end
		if not tc.isBlocking then
			pcall(tc.StartBlock, tc)
			Block.pressedAt = nowB
			Block.pressKind = kind or '?'
			PStats.presses += 1
			blockUntil = untilT
		else
			blockUntil = math.max(blockUntil, untilT)
		end
		if stopping then
			return
		end
		stopping = true
		task.spawn(function()
			while os.clock() < blockUntil and alive do
				task.wait()
			end
			stopping = false
			if tc.isBlocking then
				Block.stop(tc)
			end
		end)
	end

	local function onAnim(m, track)
		if not alive then
			return
		end
		local t0 = os.clock()
		local len = track.Length
		if len <= 0 then
			task.wait(0.05)
			len = track.Length
		end
		if len < 0.9 then
			return -- short clips are hit reactions, not attacks
		end
		local c, hrp = char()
		local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
		if not (c and hrp and r) or (r.Position - hrp.Position).Magnitude > 24 then
			return
		end
		local id = tostring(track.Animation and track.Animation.AnimationId or track.Name)
		local hitAt = hitDelay[id] or math.min(0.9, len * 0.55)
		local entry = { id = id, t = t0, m = m, r = r, hitAt = hitAt }
		pending[#pending + 1] = entry
		-- Block / parry style only (hit & run dodges instead).
		if combatStyle() ~= 'Block / parry' or not settings.autoBlock or not c:FindFirstChild('Weapon') then
			return
		end
		if (r.Position - hrp.Position).Magnitude > 16 then
			return
		end
		local sd = shineDelay[id]
		-- (v192. Measured with v191: a press 0.08 s BEFORE the shine was a plain block 6 times out of
		-- 6 - it costs stamina and still takes damage - while a press ON the shine was the real, orange
		-- parry 3 times out of 4, the hit landing 0.35 s later. So nothing is pressed ahead of the
		-- shine any more; the learned timing is only used to keep the sword back just before it.)
		do
			-- (no new swing from the wind-up on: a swing takes ~0.6 s and the shine comes 0.2-0.5 s in)
			local due = t0 + (sd and sd.d or 0.5)
			if not Block.dueAt or due > Block.dueAt or os.clock() > Block.dueAt + 0.2 then
				Block.dueAt = due
			end
		end
		if true then
			return
		end
		local lead = math.clamp((tonumber(settings.parryShineLead) or 8) / 100, 0, 0.4)
		local startIn = math.max(0, sd.d - lead) - (os.clock() - t0)
		entry.blocked = true
		task.delay(math.max(0, startIn), function()
			Block.dueAt = nil
			if alive and m.Parent then
				PStats.early += 1
				holdBlock(t0 + sd.d + 0.5, 'early')
			end
		end)
		-- (no new swing in the last 0.3 s before a press: Block.soon() holds the sword back)
		local due = t0 + math.max(0, sd.d - lead)
		if not Block.dueAt or due < Block.dueAt or os.clock() > Block.dueAt then
			Block.dueAt = due
		end
	end
	-- (v299, traced standing at a Mountain Ape: our guard shows up 0.13-0.27 s after StartBlock - the
	-- round trip to the server - but a press with no guard after 0.12 s was taken as refused, let go
	-- and pressed again, which started the wait over: 26 of 28 hits landed 0.03-0.16 s after that
	-- second press, the guard coming up just after them. So the real press-to-guard time is learned
	-- (every press that comes up), presses wait that long before counting as refused, and go out that
	-- much earlier.)
	G.FTBlockLat = type(G.FTBlockLat) == 'table' and G.FTBlockLat or {}
	function Block.lat(q)
		local l = G.FTBlockLat
		if #l < 3 then
			local okP, ping = pcall(function()
				return LocalPlayer:GetNetworkPing()
			end)
			local v = (okP and tonumber(ping) or 0.1) * 1.1 + 0.03
			return math.clamp(v, 0.08, 0.4)
		end
		-- (v306, the user: "what if the ping is different". Only the last 15 presses count, so a ping
		-- change is followed within about 15 attacks.)
		local sorted = {}
		for i = math.max(1, #l - 14), #l do
			sorted[#sorted + 1] = l[i]
		end
		table.sort(sorted)
		return math.clamp(sorted[math.clamp(math.ceil(#sorted * q), 1, #sorted)], 0.05, 0.45)
	end
	-- the shine itself
	local function onShine(m)
		local now = os.clock()
		Block.anyShineAt = now
		PStats.shines += 1
		-- each mob's own rhythm: the time from one shine to its next (follow-ups inside a combo,
		-- under 0.9 s, are not a rhythm)
		do
			local last = Block.lastShine[m]
			local kind = baseName(m.Name)
			if last and now - last > 0.9 and now - last < 6 then
				local iv = now - last
				local per = Block.period[kind]
				Block.period[kind] = per and (iv < per and iv or (per * 0.9 + iv * 0.1)) or iv
			elseif last and now - last <= 0.9 then
				-- (a follow-up inside a combo: the longest such gap seen for this kind)
				Block.combo[kind] = math.max(Block.combo[kind] or 0, now - last)
			end
			if last and now - last > 0.08 and now - last < 6 then
				-- (v198: every shine-to-next-shine time this kind has shown, in buckets - combos included)
				local iv = now - last
				local list = Block.ivs[kind]
				if not list then
					list = {}
					Block.ivs[kind] = list
				end
				local found
				for _, b in ipairs(list) do
					if math.abs(b.iv - iv) <= 0.12 then
						b.iv = b.iv * 0.8 + iv * 0.2
						b.n += 1
						found = b
						break
					end
				end
				if not found and #list < 24 then
					found = { iv = iv, n = 1, id = #list + 1 }
					list[#list + 1] = found
				end
				-- (v200: and the same, told apart by which gap came BEFORE - inside a combo the time to the
				-- next shine depends on where in the combo the mob is)
				local key = kind .. '#' .. tostring(Block.prevB[m] or 0)
				local l2 = Block.ivs[key]
				if not l2 then
					l2 = {}
					Block.ivs[key] = l2
				end
				local f2
				for _, b in ipairs(l2) do
					if math.abs(b.iv - iv) <= 0.12 then
						b.iv = b.iv * 0.8 + iv * 0.2
						b.n += 1
						f2 = true
						break
					end
				end
				if not f2 and #l2 < 12 then
					l2[#l2 + 1] = { iv = iv, n = 1 }
				end
				Block.prevB[m] = found and found.id or 0
			else
				Block.prevB[m] = 0
			end
			Block.lastShine[m] = now
		end
		local best
		for _, p in ipairs(pending) do
			if p.m == m and not p.shone and now - p.t < 2.5 and (not best or p.t > best.t) then
				best = p
			end
		end
		if best then
			best.shone = true
			local d = now - best.t
			local sd = shineDelay[best.id]
			if sd then
				-- (an animation whose shine comes at very different moments cannot be timed ahead)
				sd.dev = sd.dev * 0.7 + math.abs(d - sd.d) * 0.3
				sd.d = sd.d * 0.6 + d * 0.4
				sd.n += 1
			else
				shineDelay[best.id] = { d = d, dev = 0, n = 1 }
			end
		end
		local c, hrp = char()
		local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
		if combatStyle() ~= 'Block / parry' or not settings.autoBlock or not (c and hrp and r and c:FindFirstChild('Weapon')) then
			return
		end
		-- (v260, asked for: the Spirit Golem's ranged attack. Traced: the golem shines before it fires
		-- from 66 studs, and every shine from further than 16 studs used to be ignored. A far shine is
		-- now remembered under "<mob> @far"; when a hit follows it with no other shine waiting, that
		-- time is learned like any other - and once that mob's far timing is known (3 samples), its far
		-- shines get a parry press too.)
		local farK
		local dS = (r.Position - hrp.Position).Magnitude
		if dS > 16 then
			-- (v269, seen live in a raid: with 14 mobs around, every shine from 16-40 studs away was being
			-- answered too - a guard raised for attacks that cannot reach us, and every one of them also
			-- held our own sword back: 3 swings in 15 s. Only true long-range attacks (40+ studs, the
			-- golem beam) are answered; 16-40 is ignored again, as it was before v260.)
			if dS > 130 or dS <= 40 then
				return
			end
			farK = baseName(m.Name) .. (dS > 40 and ' @long' or ' @far')
			PStats.farShines = (PStats.farShines or 0) + 1
			if not Learn.modes(farK, nil) then
				Block.cues[#Block.cues + 1] = { t = now, k = farK, g = 0 }
				while Block.cues[1] and now - Block.cues[1].t > 1.5 do
					table.remove(Block.cues, 1)
				end
				return
			end
			PStats.farPress = (PStats.farPress or 0) + 1
			best = nil
		end
		PStats.onShine += 1
		-- (v194. Measured on our own character: after a press the game's "Parrying" state lasts
		-- 0.24-0.30 s, our own swing ("Attacking") lasts 0.54-0.67 s, and a block asked for while
		-- Attacking simply does not come up - 9 of the hits that got through were that, 5 more were a
		-- block still held from the attack before, whose Parrying had run out. So each expected hit
		-- (shine + the learned shine-to-hit time, ~0.34 s) gets its own press, sent about a quarter
		-- of a second before it, held back while our swing is still out, and asked for again if the
		-- Parrying state does not show up.)
		local gap = best and G.FTShineGap2[best.id]
		local g = gap and math.clamp(gap.d, 0.2, 0.6) or 0.34
		-- (v198, traced on the Savage Ape: its combo opener shines in the very frame its animation
		-- starts and the hit lands 0.08-0.23 s later, where the press used to go out 0.25 s after the
		-- shine. An animation known to shine without a wind-up, caught at its start, is pressed at once.)
		pcall(function()
			local mh = m:FindFirstChildOfClass('Humanoid')
			local an = mh and mh:FindFirstChildOfClass('Animator')
			for _, tr in ipairs(an and an:GetPlayingAnimationTracks() or {}) do
				local sd0 = tr.Animation and shineDelay[tr.Animation.AnimationId]
				if sd0 and sd0.d < 0.1 and tr.TimePosition < 0.12 then
					g = math.min(g, 0.15)
				end
			end
		end)
		g += math.clamp((tonumber(settings.parryShineLead) or 0) / 100, 0, 0.3)
		do
			local kind = baseName(m.Name)
			Block.gmin[kind] = math.min(Block.gmin[kind] or 0.34, g)
		end
		local extraG = {}
		do
			local modes = Learn.modes(farK or baseName(m.Name), best and best.id or nil)
			if modes then
				local first
				for _, mg in ipairs(modes) do
					if mg >= 0.12 then
						if not first then
							first = mg
						elseif mg - first >= 0.3 then
							extraG[#extraG + 1] = mg -- (a second timing far enough behind the first for its own press)
						end
					end
				end
				if first then
					g = first
					PStats.usedLearn = (PStats.usedLearn or 0) + 1
				end
			end
		end
		Block.cues[#Block.cues + 1] = { t = now, id = best and best.id or nil, k = farK or baseName(m.Name), g = g }
		-- (v211, traced on Asura: 14 of 19 hits taken were the SECOND hit of a combo, 0.6-0.75 s after
		-- the first shine. Our swing went out right after the first parry and was past its cancel window
		-- when the second shine came. So which shine of which animation is followed by another one, and
		-- how long after, is learned here; Block.soon holds the sword around the expected one.)
		pcall(function()
			local mh = m:FindFirstChildOfClass('Humanoid')
			local an = mh and mh:FindFirstChildOfClass('Animator')
			local tr0
			for _, tr in ipairs(an and an:GetPlayingAnimationTracks() or {}) do
				if not tr.Looped and tr.Animation and (not tr0 or tr.TimePosition < tr0.TimePosition) then
					tr0 = tr
				end
			end
			if not tr0 then
				return
			end
			local aid = tr0.Animation.AnimationId
			local key = aid .. '@' .. math.floor(tr0.TimePosition / 0.3 + 0.5)
			G.FTComboNext = G.FTComboNext or {}
			local CN = G.FTComboNext
			Block.lastKey = Block.lastKey or setmetatable({}, { __mode = 'k' })
			local prev = Block.lastKey[m]
			if prev and prev.aid == aid and prev.key ~= key and now - prev.t > 0.15 and now - prev.t < 1.7 then
				local rec = CN[prev.key]
				if rec then
					rec.gap = rec.n == 0 and (now - prev.t) or (rec.gap * 0.7 + (now - prev.t) * 0.3)
					rec.n += 1
				end
			end
			local rec = CN[key]
			if not rec then
				rec = { gap = 0, n = 0, seen = 0 }
				CN[key] = rec
			end
			rec.seen += 1
			Block.lastKey[m] = { aid = aid, key = key, t = now }
			Block.expect = (rec.n >= 1 and rec.n / rec.seen >= 0.4) and (now + rec.gap) or nil
			-- (v307: one per mob - with two mobs in combos the second overwrote the first's)
			Block.expectBy = Block.expectBy or setmetatable({}, { __mode = 'k' })
			Block.expectBy[m] = Block.expect
		end)
		while Block.cues[1] and now - Block.cues[1].t > 1 do
			table.remove(Block.cues, 1)
		end
		table.insert(Block.hits, now + g)
		Block.hitMob = Block.hitMob or {}
		Block.hitMob[now + g] = r
		for _, mg in ipairs(extraG) do
			table.insert(Block.hits, now + mg)
			Block.hitMob[now + mg] = r
		end
		table.sort(Block.hits)
		if Block.running then
			return
		end
		Block.running = true
		task.spawn(function()
			local tc = controller('ToolController')
			local lastPress, confirmed = 0, false
			local atkSeen, blkSeen = 0, 0 -- when our swing / our block was last seen still out
			local blkUpAt, blkWas = 0, false -- when our block last came up
			local steppedFor = nil
			local okRun, errRun = pcall(function()
				while alive and Block.hits[1] do
					local ch = LocalPlayer.Character
					local st = ch and ch:FindFirstChild('Status')
					if not (tc and st and ch:FindFirstChild('Weapon')) or combatStyle() ~= 'Block / parry' or not settings.autoBlock then
						break
					end
					local t = os.clock()
					while Block.hits[1] and Block.hits[1] < t - 0.06 do
						table.remove(Block.hits, 1)
					end
					-- (v303: the parry has landed - let go now, not 0.1 s later, so the next press is free
					-- sooner. The guard stays up on the server ~0.28 s after the let-go, which still covers a
					-- second mob hitting just behind.)
					local fx = Block.fxAt
					if fx and t - fx < 0.3 and G.FTEarlyRelease ~= false then
						while Block.hits[1] and Block.hits[1] > fx - 0.15 and Block.hits[1] < fx + 0.12 do
							table.remove(Block.hits, 1)
						end
					end
					-- (v304: the let-go reaches the server as late as the press did, so the guard is still up
					-- there for a hit landing up to ~one round trip after we let go. Letting go that early - just
					-- before the hit, from our side - frees the next press in time for a combo follow-up 0.46 s
					-- behind, which a let-go after the hit could never be.)
					if G.FTEarlyRel ~= false and lastPress > 0 then
						-- (v310: on a steady connection 0.05 s - the 0.08 s miss blamed on the margin in v305 was
						-- really a guard that never came up from a too-short hold (v308). Traced with 0.12 s: the next
						-- press missed a 0.30 s-behind second mob by 3 ms.)
						local steady0 = Block.lat(0.9) - Block.lat(0.25) < 0.05
						local margin = tonumber(G.FTRelMargin) or 0.12 -- (v311: back to 0.12 - with 0.05, holds of 0.12-0.16 s left no guard 1 time in 10 even on a steady connection; 7 hits either way)
						-- (v308, traced on a jumpy connection - press-to-guard 0.31 s typical, 0.55 s one time in
						-- ten: let-goes 0.12-0.16 s after the press left no guard at all 1 time in 4, against ~2% on
						-- a steady one. So the let-go goes by the quicker presses and never comes sooner than
						-- 0.2 s after the press.)
						local cut = t + Block.lat(0.25) - margin
						-- (v309, traced on a steady connection: 5 of 7 hits were a second mob shining 0.30 s after the
						-- first - a 0.2 s hold left the next press 0.04 s too late. A held guard past its parry window
						-- is worth nothing here (heavy hits go through it, light ones 22 -> 20), so with a steady
						-- connection the hold is cut to 0.15 s; a jumpy one keeps 0.2 s.)
						local steady = Block.lat(0.9) - Block.lat(0.25) < 0.05
						local minHold = tonumber(G.FTMinHold) or (steady and 0.15 or 0.2)
						if t - lastPress < math.max(minHold, Block.lat(0.5) * (steady and 0.5 or 0.7)) then
							cut = -math.huge
						end
						local lim = lastPress + Block.lat(0.9) + 0.27
						local relGap = tonumber(G.FTRelGap) or 0.16
						while Block.hits[1] and Block.hits[1] <= cut and Block.hits[1] >= lastPress + 0.1 and Block.hits[1] <= lim do
							-- (v306, traced with two Apes 0.23 s apart: let go early for the first, the second could
							-- not get a fresh guard in time - 110 a hit. If a let-go now leaves the next hit no time
							-- for a fresh press, the guard we have stays up for it instead.)
							local H2 = Block.hits[2]
							if H2 and H2 > cut and t + relGap + Block.lat(0.75) + 0.03 > H2 then
								PStats.keptFor2 = (PStats.keptFor2 or 0) + 1
								break
							end
							-- (v307, traced with two Apes both in combos: 5 of 6 hits were one Ape's follow-up,
							-- shining 0.06-0.12 s after we let go early for the other one - too soon for a fresh
							-- guard. A follow-up some mob is expected to throw that soon keeps the guard up.)
							local keep = false
							if G.FTKeepForExpect ~= false then
								local g0 = 0.34
								for _, P in pairs(Block.expectBy or {}) do
									if P and P > t - 0.08 and t + relGap > P + g0 - Block.lat(0.75) - 0.03 then
										keep = true
									end
								end
							end
							if keep then
								PStats.keptForExpect = (PStats.keptForExpect or 0) + 1
								break
							end
							table.remove(Block.hits, 1)
							PStats.earlyRel = (PStats.earlyRel or 0) + 1
						end
					end
					local H = Block.hits[1]
					if not H then
						break
					end
					blockUntil = H + 0.1
					local parrying = st:FindFirstChild('Parrying') ~= nil
					local attacking = st:FindFirstChild('Attacking') ~= nil
					local blockUp = st:FindFirstChild('Blocking') ~= nil
					if parrying or (blockUp and lastPress > 0 and t - lastPress > 0.03) then
						confirmed = true
					end
					if attacking then
						atkSeen = t
					end
					if blockUp then
						blkSeen = t
						if not blkWas then
							blkUpAt = t
							if lastPress > 0 and t - lastPress < 0.6 and Block.latFor ~= lastPress then
								Block.latFor = lastPress
								local l = G.FTBlockLat
								l[#l + 1] = math.floor((t - lastPress) * 1000 + 0.5) / 1000
								while #l > 40 do
									table.remove(l, 1)
								end
								PStats.lat = Block.lat(0.5)
								Block.upAt = t
							end
						end
					end
					blkWas = blockUp
					-- (v201: the hits still getting through were ones no press could stop - our own swing, or a
					-- stun, still running when the hit is 0.16 s away. Those are stepped out of instead, with the
					-- same hop Hit & run uses; the fight loop walks straight back in.)
					-- (v202: also when the block cannot come up in time because the last one came up under 0.26 s
					-- ago - two mobs hitting a quarter of a second apart, traced on the Onis: 16% a hit.)
					local cov0 = lastPress > 0 and H <= lastPress + Block.lat(0.9) + 0.27 and (parrying or t - lastPress < Block.lat(0.9) + 0.04)
					-- (v203: 5 of 23 steps at 0.16 s still took the hit. A swing pressed so late that it cannot be
					-- over in time - it shows for at least 0.61 s after the press - is stepped out of at 0.26 s.)
					-- (v264, traced on floor 61-65: 5 of 6 stuns began with a hit landing 0.03-0.10 s after our
					-- own guard went DOWN - it was dropped to raise a fresh parry for that hit, but a guard that
					-- came up under 0.4 s ago cannot be re-raised in time. So in that case the guard we have
					-- stays up through the hit: a plain block instead of an open hit.)
					-- (v301, traced at the Mountain Ape: after the parry the guard is let go, but the game's
					-- "Blocking" stays on for another ~0.25 s - the same round trip. The combo follow-up shone in
					-- that time, the leftover Blocking was taken for a guard of ours just raised, and "hold it
					-- through" pressed nothing until it went: 8 of 8 hits taken. Only a guard we really hold counts.)
					-- (v302, measured standing still: once our guard has come up, a fresh press is ignored until
					-- ~0.3 s after that - let go and pressed 0.03-0.13 s later never came up, 0.16 s+ did. The
					-- Ape's follow-up hits 0.81 s after its first shine, a fresh guard could not be up before
					-- ~0.87 s. So when a let-go-and-press cannot be up in time, the guard we hold stays up: a plain
					-- block instead of a full hit.)
					-- (v306: what stops a fresh guard is the ~0.17 s after a let-go, not the time since the last
					-- guard came up - measured. A guard we hold, or have just pressed and is on its way, stays.)
					local noFresh = t + (tonumber(G.FTRelGap) or 0.16) + Block.lat(0.75) > H - 0.02
					local ours = tc.isBlocking and (blockUp or (lastPress > 0 and t - lastPress < Block.lat(0.9) + 0.05))
					local holdThrough = G.FTHoldThrough ~= false and ours and not attacking and (blkUpAt + 0.40 > H or noFresh)
					if holdThrough and Block.heldFor ~= H then
						Block.heldFor = H
						PStats.heldThrough = (PStats.heldThrough or 0) + 1
					end
					local lead = 0.16 -- (v204: stepping at 0.26 s was worse, 14 of 36 still hit against 5 of 23 - the mob still turns and lunges that early)
					if t >= H - lead and t < H - 0.02 and steppedFor ~= H and Block.dodge and not cov0 and not holdThrough
						and (attacking or st:FindFirstChild('Stun') ~= nil or blkUpAt + 0.34 > H - 0.20 or t - atkSeen < 0.03) then
						steppedFor = H
						local src = Block.hitMob and Block.hitMob[H]
						local okStep = src ~= nil and src.Parent ~= nil and Block.dodge(src.Position, 24)
						if okStep then
							PStats.stepped = (PStats.stepped or 0) + 1
						end
						G.FTStepLog = G.FTStepLog or {}
						if #G.FTStepLog < 200 then
							local _, h1 = char()
							G.FTStepLog[#G.FTStepLog + 1] = { t = t, ok = okStep, lead = H - t, d = (src and src.Parent and h1) and (src.Position - h1.Position).Magnitude or -1,
								why = attacking and 'swing' or (st:FindFirstChild('Stun') and 'stun') or 'block just used' }
						end
					end
					-- is the next hit inside the window of the press we already made?
					-- (v197: a press shows up as Blocking 0.05-0.11s later; one that has not by 0.13s was refused)
					local latHi = Block.lat(0.9)
					local pressLead = math.clamp(Block.lat(0.75) + 0.10, 0.26, 0.5)
					local covered = lastPress > 0 and H <= lastPress + latHi + 0.27 and (parrying or confirmed or t - lastPress < latHi + 0.04)
					-- (v197, measured over 57 presses: a block asked for in the very frame our swing ends, or
					-- within 0.05s of the old block ending, is silently refused - 6 of 6 - while 0.05s after the
					-- swing and 0.09s after a block it always came up. So the old block is let go early, and
					-- the press waits those few hundredths unless the hit is too close to wait.)
					-- (v300, traced at the Mountain Ape with v299: all 5 hits still taken in 60 s were its combo
					-- follow-up, shining 0.47 s after the first; the press waited out the "settle" time after the
					-- old guard and went out 0.26 s after the shine, the guard landing 0.2 s after the hit. Those
					-- settle times were measured when slow guards were wrongly called refused. Inside the press
					-- window now nothing waits.)
					local urgent = t >= H - (G.FTSettleOld and 0.10 or pressLead)
					-- (v206, traced in fights: the block only cuts a swing short in its first 0.3 s - 7 of 7 up to
					-- 0.32 s after the swing was sent, 0 of 3 from 0.39 s on, where the block stays refused until
					-- the swing is over. So a swing that is still young is cut a little early, while it still can be.)
					local locked = attacking and t - (Block.swingAt or 0) >= 0.30
					if holdThrough then
						-- (guard stays up)
					elseif not covered and tc.isBlocking and t >= H - (pressLead + 0.16) and not attacking then
						Block.stop(tc) -- (let go of the old / refused block; pressed again once it is down)
						if lastPress > 0 and not confirmed then
							PStats.refused = (PStats.refused or 0) + 1
						end
						lastPress = 0
					elseif not covered and t >= H - ((attacking and not locked) and (pressLead + 0.03) or pressLead) then
						-- (v205, tested directly: a block asked for DURING our swing cuts the swing short and comes up
						-- with its parry 0.06 s later - 5 of 5, asked 0.07-0.32 s into the swing. A swing asked for
						-- during a block is refused and the block stays. So the press no longer waits for the swing.)
						if attacking and (locked or G.FTSwingCancel == false) then
							PStats.waitedSwing = (PStats.waitedSwing or 0) + 1 -- (our swing is still out: next frame)
						elseif tc.isBlocking then
							Block.stop(tc)
							lastPress = 0
						-- (v198, traced: a press 0.08 s after the old block went down was refused 3 of 3, and the ones
						-- that came up were all 0.33 s or more after the old block came UP)
						elseif not urgent and ((not attacking and t - atkSeen < 0.05) or t - blkSeen < 0.10 or t - blkUpAt < 0.34) then
							PStats.settled = (PStats.settled or 0) + 1 -- (too soon after our swing / block: next frame)
						elseif t - (Block.relAt or 0) < (tonumber(G.FTRelGap) or 0.16) then
							PStats.relWait = (PStats.relWait or 0) + 1 -- (v303: too soon after our let-go, it would be ignored)
						elseif t < H - 0.03 then
							pcall(tc.StartBlock, tc)
							lastPress, confirmed = t, false
							Block.pressedAt = t
							Block.pressKind = 'run'
							PStats.presses += 1
						end
					end
					task.wait()
				end
			end)
			-- (v302: a combo follow-up expected soon - keep the guard up for it instead of letting go
			-- just before its shine, which leaves no time for a fresh guard)
			local P = Block.expect
			local nowE = os.clock()
			if G.FTEarlyRel ~= false then
				-- (v307: with the early let-go, only a follow-up too close for a fresh guard is held for)
				P = nil
				if G.FTKeepForExpect ~= false then
					for _, Pm in pairs(Block.expectBy or {}) do
						if Pm and Pm > nowE - 0.08 and nowE + (tonumber(G.FTRelGap) or 0.16) > Pm + 0.34 - Block.lat(0.75) - 0.03 and (not P or Pm > P) then
							P = Pm
						end
					end
				end
			end
			if tc and tc.isBlocking and P and P > nowE - 0.08 and P - nowE < 0.7 and G.FTHoldCombo ~= false then
				PStats.heldCombo2 = (PStats.heldCombo2 or 0) + 1
				task.defer(function() -- (deferred: Block.running is cleared just below)
					local untilT = P + 0.55
					while os.clock() < untilT and not Block.running and alive do
						task.wait()
					end
					if not Block.running and tc.isBlocking then
						Block.stop(tc)
					end
				end)
			elseif tc and tc.isBlocking then
				Block.stop(tc)
			end
			table.clear(Block.hits)
			if Block.hitMob then
				table.clear(Block.hitMob)
			end
			blockUntil = 0
			Block.running = false
			if not okRun then
				warn('[ForgeTools] parry: ' .. tostring(errRun))
			end
		end)
	end
	-- Soonest incoming hit from a mob within radius: returns attacker position, seconds until it lands.
	function Block.threat(radius)
		local now = os.clock()
		local _, hrp = char()
		if not hrp then
			return nil
		end
		local bestPos, bestRem
		for i = #pending, 1, -1 do
			local p = pending[i]
			local rem = p.t + (hitDelay[p.id] or p.hitAt) - now
			if rem < -0.35 or now - p.t > 2.5 then
				if now - p.t > 2.5 then
					table.remove(pending, i)
				end
			elseif p.m.Parent and p.r.Parent then
				local h = p.m:FindFirstChildOfClass('Humanoid')
				if (not h or h.Health > 0) and (p.r.Position - hrp.Position).Magnitude <= radius and Threat.is(p.m) then
					if not bestRem or rem < bestRem then
						bestPos, bestRem = p.r.Position, rem
					end
				end
			end
		end
		return bestPos, bestRem
	end
	local function hook(m)
		if hookedAnims[m] or not m:GetAttribute('IsNpc') then
			return
		end
		local h = m:FindFirstChildOfClass('Humanoid') or m:FindFirstChildOfClass('AnimationController')
		local an = h and h:FindFirstChildOfClass('Animator')
		if not an then
			return
		end
		hookedAnims[m] = true
		blockConns[#blockConns + 1] = an.AnimationPlayed:Connect(function(track)
			task.spawn(onAnim, m, track)
		end)
		blockConns[#blockConns + 1] = m.DescendantAdded:Connect(function(d)
			if d.Name == 'ParryWindow' and d:IsA('Attachment') then
				onShine(m)
			end
		end)
	end
	local living = workspace:FindFirstChild('Living')
	if living then
		for _, m in ipairs(living:GetChildren()) do
			task.spawn(hook, m)
		end
	end
	-- Mobs respawn and their Animator can show up late: keep hooking new ones.
	task.spawn(function()
		while alive and G.FTBlockConns == blockConns do
			local lv = workspace:FindFirstChild('Living')
			for _, m in ipairs(lv and lv:GetChildren() or {}) do
				if not hookedAnims[m] then
					pcall(hook, m)
				end
			end
			pcall(watchHealth)
			if #blockConns > 400 then
				for i = #blockConns, 1, -1 do
					if not blockConns[i].Connected then
						table.remove(blockConns, i)
					end
				end
			end
			task.wait(2)
		end
	end)
	Block.nearSince = setmetatable({}, { __mode = 'k' }) -- [mob] = since when it has been within 8 studs of us
	local nearAt = 0
	function Block.soon()
		local d = Block.dueAt
		local now = os.clock()
		if G.FTSwingCancel ~= false then
			-- (v205: since the block cancels a swing, a swing only has to be held back when it could not
			-- reach its own hitbox - about 0.35 s after the press - before the block has to go up)
			local H1 = Block.hits[1]
			if (H1 ~= nil and H1 - now < (tonumber(G.FTSwingHold) or 0.82) and H1 - now > -0.1) or (d ~= nil and d - now < 0.47 and d - now > -0.1) then
				return true
			end
			-- (v211: a follow-up shine is expected at P. A swing sent now must either be over before the
			-- press for it (~0.62 s) or still be cancellable then (sent no more than 0.2 s before P).)
			local P = Block.expect
			if P ~= nil and now > P - 0.62 and now < P - 0.20 then
				PStats.heldCombo = (PStats.heldCombo or 0) + 1
				return true
			end
			return false
		end
		if Block.running == true or (d ~= nil and d - now < 0.75 and d - now > -0.1) then
			return true
		end
		-- (v199, traced: 6 of the 7 swings still caught by a shine were pressed within 0.1 s of the mob
		-- STARTING its attack, after it had been quiet for 2-7 s: we step up to it, it attacks the moment
		-- we are in reach, and we swing the same moment. So next to a mob that has not attacked lately
		-- the first swing waits 0.4 s: if it winds up, the wind-up rule above holds the sword.)
		if combatStyle() == 'Block / parry' and settings.autoBlock then
			local _, hrp0 = char()
			local living = workspace:FindFirstChild('Living')
			if hrp0 and living then
				if now - nearAt > 0.3 then
					table.clear(Block.nearSince) -- (not looked at for a while: start counting again)
				end
				if now - nearAt >= 0.06 then
					nearAt = now
					for _, m in ipairs(living:GetChildren()) do
						if m:GetAttribute('IsNpc') then
							local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
							local mh = m:FindFirstChildOfClass('Humanoid')
							if r and mh and mh.Health > 0 and (r.Position - hrp0.Position).Magnitude <= 8 then
								Block.nearSince[m] = Block.nearSince[m] or now
							else
								Block.nearSince[m] = nil
							end
						end
					end
				end
				for m, t0 in pairs(Block.nearSince) do
					local last = Block.lastShine[m]
					if now - t0 < 0.4 and (not last or now - last > 2) then
						return true
					end
				end
			end
		end
		-- (v195. Measured with v194: no plain blocks left, 33 parries, and all 14 hits that got through
		-- came while our own swing was still out when the shine appeared - a swing lasts ~0.6 s and
		-- cannot be called back. So a swing only starts when it will be over before the next shine
		-- of every mob in reach: after its hit has landed, and at least 0.75 s before its rhythm
		-- says the next one is due.)
		local _, hrp = char()
		if not hrp then
			return false
		end
		local hold, hot = false, false
		for m, last in pairs(Block.lastShine) do
			local r = m.Parent and (m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart)
			if r and now - last < 8 and (r.Position - hrp.Position).Magnitude <= 16 then
				-- (v196. With v195 the hits left were a mob's attack after a pause, and the later hits of
				-- a combo. So a mob that has attacked in the last 8 s only leaves one opening: after its
				-- hit - and after its combo, if its kind has one - until 0.75 s before its rhythm says
				-- the next attack is due. Outside that opening the sword stays back.)
				local since = now - last
				local kind = baseName(m.Name)
				-- (v198: v196's rule left no opening at all against a Savage Ape - 0 swings in 150 s. Now the
				-- next shine is read off the times this kind has actually shown between two shines: a swing
				-- may start once the last hit has landed, if it is over - 0.67 s swing, then the block has to
				-- come up - before the earliest next hit this kind could still throw.)
				local list = Block.ivs[kind]
				-- (v200: v198's list mixed every gap of a combo together, which against a lone Savage Ape -
				-- shines 0.16 / 0.44 / 0.86 / 0.30 / 1.23 s apart - left no opening: 0 swings in 180 s. The
				-- gaps seen after THIS point of its pattern are used once there are 3 of them.)
				local l2 = Block.ivs[kind .. '#' .. tostring(Block.prevB[m] or 0)]
				local seen2 = 0
				for _, b in ipairs(l2 or {}) do
					seen2 += b.n
				end
				if seen2 >= 3 then
					list = l2
				end
				local nextIv
				for _, b in ipairs(list or {}) do
					if b.n >= 2 and b.iv > since - 0.15 and (not nextIv or b.iv < nextIv) then
						nextIv = b.iv
					end
				end
				local need = 0.85 - (Block.gmin[kind] or 0.34)
				if since < 0.4 then
					hot = true
				end
				if since < 0.4 or (nextIv ~= nil and nextIv - since < need) then
					hold = true
				end
			end
		end
		-- (v200: an opening that never comes must not mean never attacking: after 4 s of holding, the
		-- sword goes out at the first moment no hit is on its way)
		if hold then
			Block.heldAt = Block.heldAt or now
			if hot or now - Block.heldAt < 4 then
				return true
			end
			PStats.forcedSwing = (PStats.forcedSwing or 0) + 1
		end
		Block.heldAt = nil
		return false
	end
	function Block.active()
		return os.clock() < blockUntil
	end
	function Block.hold(seconds)
		holdBlock(os.clock() + math.max(0.1, tonumber(seconds) or 0.5))
	end
end

-- Hit & run: step out of reach just before a hit lands, toward open floor away from other mobs.
local dodgeParams = RaycastParams.new()
dodgeParams.FilterType = Enum.RaycastFilterType.Exclude
local function dodgeOnce(fromPos, distOverride)
	if (G.FTNoDodge or settings.dodgeWhat == 'Low health only') and not G.FTKiting then
		return false -- (v299, asked for while testing parries: no stepping out at all)
	end
	local c, hrp = char()
	if not hrp then
		return false
	end
	local filter = { c }
	local living = workspace:FindFirstChild('Living')
	if living then
		filter[#filter + 1] = living
	end
	local debris = workspace:FindFirstChild('Debris')
	if debris then
		filter[#filter + 1] = debris
	end
	dodgeParams.FilterDescendantsInstances = filter
	local dist = distOverride or tonumber(settings.dodgeDist) or 16
	local away = (hrp.Position - fromPos) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.2 then
		away = -hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	away = away.Unit
	local _, near = mobsNear(hrp.Position, 40)
	local best, bestScore
	-- On the way somewhere (30+ studs still to go): never step back down the route - sideways or
	-- onward only, onward preferred.
	local toDest = G.FTTravel and (G.FTTravel - hrp.Position) * Vector3.new(1, 0, 1)
	toDest = toDest and toDest.Magnitude >= 30 and toDest.Unit or nil
	for _, ang in ipairs({ 0, 30, -30, 60, -60, 90, -90, 135, -135, 165, -165 }) do
		local a = math.rad(ang)
		local dir = Vector3.new(away.X * math.cos(a) - away.Z * math.sin(a), 0, away.X * math.sin(a) + away.Z * math.cos(a))
		local target = hrp.Position + dir * dist
		if toDest and dir:Dot(toDest) < -0.1 then
			target = nil
		end
		-- clear path (no wall) and floor under the landing spot
		local wall = target and workspace:Raycast(hrp.Position, dir * dist, dodgeParams)
		local floor = target and workspace:Raycast(target + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), dodgeParams)
		if target and not wall and floor and not Lava.at(floor.Position + Vector3.new(0, 3, 0)) then
			local score = math.huge
			for _, e in ipairs(near) do
				score = math.min(score, (e.r.Position - target).Magnitude)
			end
			score = math.min(score, 60)
			if toDest then
				score += dir:Dot(toDest) * 8
			else
				score -= math.abs(ang) * 0.02 -- prefer straight back
			end
			if not bestScore or score > bestScore then
				best, bestScore = floor.Position + Vector3.new(0, 3, 0), score
			end
		end
	end
	if not best then
		return false
	end
	hrp.CFrame = CFrame.lookAt(best, Vector3.new(fromPos.X, best.Y, fromPos.Z))
	hrp.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- Lunging mobs (island 3 spiders, measured): the attack starts 12-15 studs away, the mob runs in
-- at 20 studs/s and the hit lands 0.55-0.77s later with the mob still 4-9 studs off. Stepping
-- back 8 studs does nothing against that: callers ask for enough to end up ~30 studs from the mob.
-- In a tight cave the long step may not fit, so shorter ones are tried after it.
local function dodgeFrom(fromPos, distOverride)
	-- (v276: which rule asked for each dodge, by line, so a "jitter" report can be traced)
	do
		local okL, ln = true, debug.info(2, 'l')
		local by = type(G.FTDodgeBy) == 'table' and G.FTDodgeBy or {}
		G.FTDodgeBy = by
		local k = tostring(okL and ln or '?')
		by[k] = (by[k] or 0) + 1
	end
	if combatStyle() == 'Attack only' or ((G.FTNoDodge or settings.dodgeWhat == 'Low health only') and not G.FTKiting) then
		return false -- (v236, asked for: no dodging, no blocking, just stand in reach and swing)
	end
	if dodgeOnce(fromPos, distOverride) then
		return true
	end
	if distOverride and distOverride > 14 then
		return dodgeOnce(fromPos, distOverride * 0.6) or dodgeOnce(fromPos, nil)
	end
	return false
end
Block.dodge = dodgeFrom
-- (v218, asked for after two raids lost to crowds: "when low health, step out ... always staying
-- far from enemies".) Below "Back off below % health" the fight stops and we keep our distance from
-- every mob - one step away at a time, no faster than the normal glide - until health is back at
-- "heal to". Parries of anything that still reaches us keep running on their own.
local function kiteLow()
	local _, _, hum = char()
	local k = tonumber(settings.kiteHp) or 0
	-- (v268, seen live in a raid: it backed off at 49%, was chipped from range the whole time, never
	-- got back to 75% and stood off for minutes while the raid waited. A back-off that did not get
	-- there in 20 s is over; for the next 25 s only half the threshold sends it off again.)
	if os.clock() < (G.FTKiteHold or 0) then
		k = k / 2
	end
	return k > 0 and hum ~= nil and hum.MaxHealth > 0 and hum.Health > 0 and hum.Health / hum.MaxHealth * 100 < k
end
local function kiteHeal()
	local t0, lastHop, hops = os.clock(), 0, 0
	local _, _, hum0 = char()
	local from = hum0 and hum0.MaxHealth > 0 and hum0.Health / hum0.MaxHealth * 100 or 0
	local goal = math.clamp(tonumber(settings.healTo) or 60, math.min((tonumber(settings.kiteHp) or 40) + 25, 95), 100)
	local reached = false
	G.FTKiting = true -- (v320: the only stepping allowed under Dodge = Low health only)
	-- (v319, asked for: "low level dodge can get cornered". Stepping straight away from the mobs ends
	-- against a wall or an edge. Now the ordinary step looks at 32 spots 22 and 36 studs out, all round,
	-- and takes the one farthest from every mob with the fewest walls next to it - jumping past the
	-- mobs if the open side is behind them.)
	local rpK = RaycastParams.new()
	rpK.FilterType = Enum.RaycastFilterType.Exclude
	rpK.RespectCanCollide = true
	local function openStep(hrp, mobsP)
		if G.FTNoDodge or combatStyle() == 'Attack only' then
			return false
		end
		rpK.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
		local function score(pos)
			local sc = 80
			for _, mp in ipairs(mobsP) do
				sc = math.min(sc, (mp - pos).Magnitude)
			end
			for k = 0, 3 do
				local a = k * math.pi / 2
				if workspace:Raycast(pos, Vector3.new(math.cos(a), 0, math.sin(a)) * 10, rpK) then
					sc -= 6
				end
			end
			return sc
		end
		local here = score(hrp.Position)
		local best, bs
		for _, dist in ipairs({ 22, 36 }) do
			for k = 0, 15 do
				local a = k * math.pi / 8
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				if not workspace:Raycast(hrp.Position, dir * dist, rpK) then
					local tgt = hrp.Position + dir * dist
					local fl = workspace:Raycast(tgt + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rpK)
					if fl and math.abs(fl.Position.Y + 3 - hrp.Position.Y) < 14 and not Lava.at(fl.Position + Vector3.new(0, 3, 0)) then
						local pos = fl.Position + Vector3.new(0, 3, 0)
						local sc = score(pos)
						if not bs or sc > bs then
							best, bs = pos, sc
						end
					end
				end
			end
		end
		if best and bs > here + 3 then
			local fwd = (best - hrp.Position) * Vector3.new(1, 0, 1)
			hrp.CFrame = CFrame.lookAt(best, best + fwd)
			hrp.AssemblyLinearVelocity = Vector3.zero
			G.FTKiteOpen = (G.FTKiteOpen or 0) + 1
			return true
		end
		return false
	end
	while alive and os.clock() - t0 < 20 do
		local _, hrp, hum = char()
		if not hrp or not hum or hum.Health <= 0 then
			reached = true
			break
		end
		local pct = hum.Health / hum.MaxHealth * 100
		if pct >= goal then
			reached = true
			break
		end
		local sum, wsum, n, nearD = Vector3.zero, 0, 0, nil
		local mobsP = {}
		local living = workspace:FindFirstChild('Living')
		for _, m in ipairs(living and living:GetChildren() or {}) do
			if m:GetAttribute('IsNpc') then
				local h = m:FindFirstChildOfClass('Humanoid')
				local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
				if h and r and h.Health > 0 and h.MaxHealth < 1e8 then
					local d = (r.Position - hrp.Position).Magnitude
					if d < 80 then
						mobsP[#mobsP + 1] = r.Position
					end
					if d < 50 then
						local wt = 1 / math.max(d, 4)
						sum += r.Position * wt
						wsum += wt
						n += 1
						if not nearD or d < nearD then
							nearD = d
						end
					end
				end
			end
		end
		setStatus(('low health (%d%%) — keeping away from %d mobs until %d%%'):format(pct, n, goal))
		-- (v258, asked for: "low health dodge need to be improved". It stepped 24 studs once a mob was
		-- within 34, at most every 0.6 s, and looked at nothing else. Now: a mob winding up within 26
		-- studs, or a shot coming, is stepped away from at once; and the ordinary step is 30 studs,
		-- from 42 studs out, every 0.4 s.)
		local wK = attackThreat(26) or Attack.rangedThreat(30)
		if wK and os.clock() - lastHop >= 0.2 then
			lastHop = os.clock()
			if dodgeFrom(wK, 30) or openStep(hrp, mobsP) then
				hops += 1
				G.FTKiteFast = (G.FTKiteFast or 0) + 1
			end
		elseif nearD and nearD < 42 and os.clock() - lastHop >= 0.4 then
			lastHop = os.clock()
			if openStep(hrp, mobsP) or dodgeFrom(sum / wsum, 30) then
				hops += 1
			end
		end
		task.wait(0.05)
	end
	G.FTKiting = nil
	if not reached then
		G.FTKiteHold = os.clock() + 25
		G.FTKiteGaveUp = (G.FTKiteGaveUp or 0) + 1
	end
	local _, _, hum1 = char()
	G.FTKite = G.FTKite or { n = 0, hops = 0, died = 0 }
	G.FTKite.n += 1
	G.FTKite.hops += hops
	if not hum1 or hum1.Health <= 0 then
		G.FTKite.died += 1
	end
	statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('backed off at %d%% health: %d steps in %.0fs, now %d%%'):format(from, hops, os.clock() - t0, hum1 and hum1.MaxHealth > 0 and hum1.Health / hum1.MaxHealth * 100 or 0)
end
-- (v262, asked for: "purely random whether I survive ... we need to do better". Traced on floor 65:
-- a hit taken builds up to a 2 s "Stun" (a value in the character's Status folder). Stunned, no
-- parry goes up, and the crowd's next hits land in full - 661 and 1,165 within 0.5 s of one stun,
-- each adding a 3 s burn on top. So the moment a stun lands we leave the crowd: one 30 stud step
-- away from the mobs around us, again every 0.3 s for as long as the stun lasts and a mob is close.)
task.spawn(function()
	local lastHop = 0
	while alive do
		task.wait(0.04)
		local c, hrp, hum = char()
		local st = c and c:FindFirstChild('Status')
		-- (v271: OFF unless G.FTStunEscape is set. Seen live in a raid: a stun every 3-6 s, each one
		-- a 30 stud hop out of the crowd - it was never in reach to parry or swing: 0-7 swings per 30 s.
		-- "whys it dodging and not parrying .... its also not swinging")
		if G.FTStunEscape == true and st and hrp and hum and hum.Health > 0 and st:FindFirstChild('Stun') and combatStyle() ~= 'Attack only'
			and os.clock() - lastHop >= 0.3 then
			local _, near = mobsNear(hrp.Position, 20)
			if near and #near > 0 then
				local sum = Vector3.zero
				for _, e in ipairs(near) do
					sum += e.r.Position
				end
				lastHop = os.clock()
				if dodgeFrom(sum / #near, 30) then
					G.FTStunEscapes = (G.FTStunEscapes or 0) + 1
					setStatus(('stunned — stepped away from %d mobs'):format(#near))
				else
					G.FTStunStuck = (G.FTStunStuck or 0) + 1
				end
			end
		end
	end
end)
-- how far to step to end up clear of a mob at `pos` that is winding up
local function clearDist(pos)
	local _, hrp = char()
	local d = hrp and (hrp.Position - pos).Magnitude or 0
	return math.max(tonumber(settings.dodgeDist) or 16, 30 - d)
end

-- Projectiles and ground markers. The game draws both on the client as objects in workspace.Debris
-- (read from its effect scripts): a thrown rock / spider spit / crystal shard is a part flying at
-- 75-100 studs/s, and an area attack first shows a "GroundIndicator" / "rangeIndicator" marker on
-- the floor for about a second. So: anything in Debris that starts away from us and is flying at
-- us gets side-stepped, and we never stay standing inside a marker.
local Hazard = { seen = {}, n = { proj = 0, ground = 0 }, last = 0, count = 0,
	skipName = { Parry = true, Block = true, BlockHit = true, Shieldd = true, M1Slash = true, M2Slash = true, Effect = true, Head = true, HumanoidRootPart = true, Rig = true, lightningDebris = true, Dust1 = true } }
G.FTHazard = Hazard.n
pcall(function()
	if G.FTHazardConn then
		G.FTHazardConn:Disconnect()
	end
	G.FTHazardConn = workspace:WaitForChild('Debris', 10).ChildAdded:Connect(function(x)
		-- (v274, reported: "ping keeps getting higher" with Auto mobs on in the Abyss. Every effect
		-- the game drops into Debris was tracked here for 6 s and looked at every frame - in an Abyss
		-- crowd that is hundreds of parts, and it grows with the floor. Now: our own guard / slash
		-- effects are not tracked at all, nothing is kept past 3 s (a shot flies 0.3 s; a floor marker
		-- shows for about 1 s), and never more than 250 at once.)
		if (x:IsA('BasePart') or x:IsA('Model')) and not Hazard.skipName[x.Name] and (Hazard.count or 0) < 250 then
			Hazard.seen[x] = { t = os.clock() }
			Hazard.count = (Hazard.count or 0) + 1
		end
		if x.Name == 'ChargeIndicator' and x:IsA('BasePart') then
			-- (v261, asked for: the beam. Traced: a flat strip "ChargeIndicator", 7 studs wide and 30-70
			-- long, is drawn on the floor and the beam fires down it about 0.3 s later - nothing flies, so
			-- the projectile dodge never saw it. While the strip is there we do not stand in it: one step
			-- sideways across it, checked every 0.04 s for as long as it lasts.)
			task.spawn(function()
				local tC = os.clock()
				G.FTBeamSeen = (G.FTBeamSeen or 0) + 1
				while alive and x.Parent and os.clock() - tC < 1.2 do
					local _, hV, humV = char()
					if not hV or not humV or humV.Health <= 0 or combatStyle() == 'Attack only' then
						break
					end
					local okL, loc = pcall(function()
						return x.CFrame:PointToObjectSpace(hV.Position)
					end)
					if not okL then
						break
					end
					local sz = x.Size
					local longX = sz.X >= sz.Z
					local along = longX and loc.X or loc.Z
					local across = longX and loc.Z or loc.X
					local halfL, halfW = math.max(sz.X, sz.Z) / 2, math.min(sz.X, sz.Z) / 2
					if math.abs(along) < halfL + 6 and math.abs(across) < halfW + 4 and math.abs(loc.Y) < 25 then
						local perp = (longX and x.CFrame.LookVector or x.CFrame.RightVector) * Vector3.new(1, 0, 1)
						if perp.Magnitude > 0.1 then
							perp = perp.Unit
							-- the shorter way out first
							local side = (hV.Position - x.Position):Dot(perp) >= 0 and 1 or -1
							if Hazard.sidestep(hV, perp * side) then
								Hazard.last = os.clock()
								G.FTBeamSteps = (G.FTBeamSteps or 0) + 1
								setStatus('stepped out of a beam line')
							else
								G.FTBeamStuck = (G.FTBeamStuck or 0) + 1
							end
						end
					end
					task.wait(0.04)
				end
			end)
		end
		if x.Name == 'bulletCharge' and os.clock() - (Hazard.volleyAt or 0) > 1.5 then
			-- (v259, traced on a Spirit Golem: its ranged attack is one shine, then 13 shards 0.13 s
			-- apart over 1.7 s. A block comes back up every ~0.4 s at best, so a parry stops 4 of the 13.
			-- Instead: keep moving across its line of fire for as long as it shoots.)
			Hazard.volleyAt = os.clock()
			task.spawn(function()
				local okP, src = pcall(function()
					return x:IsA('Model') and x:GetPivot().Position or x.Position
				end)
				if not okP or combatStyle() == 'Attack only' then
					return
				end
				local tV = os.clock()
				while alive and os.clock() - tV < 1.9 do
					local _, hV, humV = char()
					if not hV or not humV or humV.Health <= 0 then
						break
					end
					local rel = (hV.Position - src) * Vector3.new(1, 0, 1)
					if rel.Magnitude > 160 or rel.Magnitude < 1 then
						break
					end
					local perp = rel.Unit:Cross(Vector3.yAxis)
					if Hazard.sidestep(hV, perp) then
						Hazard.last = os.clock()
						G.FTVolleySteps = (G.FTVolleySteps or 0) + 1
						setStatus('moving across a Spirit Golem volley')
					end
					task.wait(0.3)
				end
			end)
		end
	end)
end)
-- Step off a projectile's line. (Not dodgeFrom: that picks whichever direction ends up furthest
-- from mobs, which can be straight along the line - measured: a 12 stud "dodge" that still let the
-- shot pass 2.4 studs from us.)
function Hazard.sidestep(hrp, perp)
	if (G.FTNoDodge or settings.dodgeWhat == 'Low health only') and not G.FTKiting then
		return false -- (v320: Dodge = Low health only - no side-steps from shots either)
	end
	local c = char()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { c, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
	for _, try in ipairs({ { 1, 12 }, { -1, 12 }, { 1, 8 }, { -1, 8 } }) do
		local move = perp * try[1] * try[2]
		local target = hrp.Position + move
		local wall = workspace:Raycast(hrp.Position, move, rp)
		local floor = workspace:Raycast(target + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rp)
		if not wall and floor and not Lava.at(floor.Position + Vector3.new(0, 3, 0)) then
			hrp.CFrame = hrp.CFrame.Rotation + (floor.Position + Vector3.new(0, 3, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
			return true
		end
	end
	return false
end
-- Several shooters at once (4 Diamond Spiders): side-stepping one shot at a time is not enough, each
-- spit is aimed at where we stand when it is released. What a shot cannot hit is something moving
-- across its line the whole time it is in the air. So while any shooter near us is in its release
-- window we keep moving - 6 studs every 0.08s - in the direction that crosses ALL their lines best.
function Hazard.strafe(hrp, now)
	if ((G.FTNoDodge or settings.dodgeWhat == 'Low health only') and not G.FTKiting) or now - (Hazard.strafeAt or 0) < 0.08 or now < (G.FTStrikeUntil or 0) then
		return
	end
	local me = hrp.Position
	local lines
	for m, t in pairs(attackWarn) do
		local hw = Attack.hit[(string.gsub(m.Name, '%d+$', ''))]
		local far = hw and hw.far
		local age = now - t
		if far and (Attack.d0[m] or 0) >= far.d - 2 and age > far.min - 0.15 and age < far.max + 0.4 then
			local r = m.Parent and (m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart)
			local off = r and (me - r.Position) * Vector3.new(1, 0, 1)
			if off and off.Magnitude < 70 and off.Magnitude > 1 then
				lines = lines or {}
				lines[#lines + 1] = off.Unit
			end
		end
	end
	if not lines then
		return
	end
	Hazard.strafeAt = now
	local c = char()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { c, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
	local best, bestScore, bestDir
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local score = math.huge
		for _, u in ipairs(lines) do
			score = math.min(score, math.abs(dir.X * u.Z - dir.Z * u.X)) -- how squarely it crosses that line
		end
		if Hazard.strafeDir and now - (Hazard.strafeLast or 0) < 0.5 then
			score += dir:Dot(Hazard.strafeDir) * 0.3 -- keep going the same way: no jittering on the spot
		end
		if not bestScore or score > bestScore then
			local move = dir * 6
			local floor = not workspace:Raycast(me, move, rp) and workspace:Raycast(me + move + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rp)
			if floor and math.abs(floor.Position.Y + 3 - me.Y) < 6 and not Lava.at(floor.Position + Vector3.new(0, 3, 0)) then
				best, bestScore, bestDir = floor.Position + Vector3.new(0, 3, 0), score, dir
			end
		end
	end
	if best then
		hrp.CFrame = hrp.CFrame.Rotation + best
		hrp.AssemblyLinearVelocity = Vector3.zero
		Hazard.strafeDir, Hazard.strafeLast = bestDir, now
		Hazard.n.strafe = (Hazard.n.strafe or 0) + 1
	end
end
function Hazard.step()
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	local me = hrp.Position
	Hazard.strafe(hrp, now)
	me = hrp.Position
	for x, e in pairs(Hazard.seen) do
		if not x.Parent or now - e.t > 3 then
			Hazard.seen[x] = nil
			Hazard.count = math.max(0, (Hazard.count or 1) - 1)
		elseif x.Name == 'GroundIndicator' or x.Name == 'rangeIndicator' then
			if now - Hazard.last > 0.3 then
				local ok, cf, size = pcall(function()
					if x:IsA('Model') then
						return x:GetBoundingBox()
					end
					return x.CFrame, x.Size
				end)
				if ok and cf and size then
					local rad = math.max(size.X, size.Y, size.Z) / 2
					local flat = (me - cf.Position) * Vector3.new(1, 0, 1)
					if flat.Magnitude < rad + 2 and math.abs(me.Y - cf.Position.Y) < 20 then
						Hazard.last = now
						-- (v258, asked for: "watching out for projectiles". These used to be stood in / taken once
						-- to measure what they cost before any was dodged - and that memory is lost on every
						-- teleport. On floor 60+ one costs 400-700 health. Now always dodged.)
						if dodgeFrom(cf.Position, math.max(10, rad + 6 - flat.Magnitude)) then
							Hazard.n.ground += 1
							setStatus('stepping out of an attack marker')
						end
					end
				end
			end
		else
			local ok, pos = pcall(function()
				return x:IsA('Model') and x:GetPivot().Position or x.Position
			end)
			if ok and pos then
				e.from = e.from or pos
				if not e.done and not e.fast and now - e.t < 0.3 then
					-- (waiting to see it fly 6 studs first cost 0.06s+ of a 0.2-0.3s flight)
					local bv = x:FindFirstChildWhichIsA('BodyVelocity', true)
					if bv and bv.Velocity.Magnitude >= 40 then
						e.fast = true
						local dir = bv.Velocity.Unit
						local rel = me - pos
						local along = rel:Dot(dir)
						if along > 0 and along < 80 and (rel - dir * along).Magnitude < 7 and mobsNear(pos, 30) > 0 then
							local perp = dir:Cross(Vector3.yAxis)
							if perp.Magnitude < 0.1 then
								perp = hrp.CFrame.RightVector
							end
							perp = (perp * Vector3.new(1, 0, 1)).Unit
							if rel:Dot(perp) < 0 then
								perp = -perp
							end
							Hazard.last = now
							e.done = true
							if combatStyle() ~= 'Attack only' and Hazard.sidestep(hrp, perp) then
								Hazard.n.proj += 1
								setStatus(('dodged a projectile (%s)'):format(x.Name))
							end
						end
					end
				end
				if e.p and now > e.at and not e.done then
					local v = (pos - e.p) / (now - e.at)
					local sp = v.Magnitude
					-- (40+: our own and other players' slash effects drift at 15-35; 400+: a teleport, not a flight)
					if e.mob == nil and sp >= 40 then
						-- (a shot starts at the mob that fired it, and is built like one: the game's shots are parts
						-- pushed by a BodyVelocity, thrown weapons are models, attack volumes are "Hitbox<n>".
						-- Measured over 5 minutes of mining: bare parts - sparks, ore drops - made 3 of 8 dodges.)
						e.mob = mobsNear(e.from, 18) > 0 and (x:IsA('Model') or string.sub(x.Name, 1, 6) == 'Hitbox'
							or x:FindFirstChildWhichIsA('BodyMover', true) ~= nil)
					end
					if e.mob and sp >= 40 and sp < 400 and (e.from - me).Magnitude > 10 and (pos - e.from).Magnitude >= 6 and (pos - e.from).Unit:Dot(v.Unit) > 0.9 then -- (really flying in a line: sparks and roar rings only jump for a frame)
						local dir = v.Unit
						local rel = me - pos
						local along = rel:Dot(dir)
						if along > 0 and along / sp < 0.5 and (rel - dir * along).Magnitude < 7 and now - Hazard.last > 0.15 then
							-- step sideways off its line (to the side we are already on)
							local perp = dir:Cross(Vector3.yAxis)
							if perp.Magnitude < 0.1 then
								perp = hrp.CFrame.RightVector -- (falling straight down on us: any way out)
							end
							perp = (perp * Vector3.new(1, 0, 1)).Unit
							if rel:Dot(perp) < 0 then
								perp = -perp
							end
							Hazard.last = now
							e.done = true
							if combatStyle() ~= 'Attack only' and Hazard.sidestep(hrp, perp) then
								Hazard.n.proj += 1
								setStatus(('dodged a projectile (%s)'):format(x.Name))
							end
						end
					end
				end
				e.p, e.at = pos, now
			end
		end
	end
end
task.spawn(function()
	local forging, checked = false, 0
	while alive do
		task.wait()
		local now = os.clock()
		if now - checked > 0.5 then
			checked = now
			local FC = controller('ForgeController')
			forging = (FC and FC.ForgeActive) and true or false
		end
		if not forging and (next(Hazard.seen) or next(attackWarn)) and (settings.autoMine or settings.autoMobs or settings.autoAbyss
			or settings.autoCompleteQuests or QS.wantMobs or QS.wantMine) then
			local tH = os.clock()
			pcall(Hazard.step)
			local PF = G.FTPerf or { ms = 0, at = os.clock(), msPerSec = 0, peak = 0, seenPeak = 0 }
			G.FTPerf = PF
			PF.ms += (os.clock() - tH) * 1000
			PF.seenPeak = math.max(PF.seenPeak, Hazard.count or 0)
			if os.clock() - PF.at >= 1 then
				PF.msPerSec = PF.ms / (os.clock() - PF.at)
				PF.peak = math.max(PF.peak, PF.msPerSec)
				PF.ms, PF.at = 0, os.clock()
			end
		end
	end
end)

-- Bombers run up to you and explode (measured: 91 of 116 health in one blast, while the bot was
-- just walking to a quest NPC). Whatever the bot is doing, it steps away when one gets close.
task.spawn(function()
	while alive do
		task.wait(0.1)
		local ok = pcall(function()
			if not (settings.autoMine or settings.autoMobs or settings.autoCompleteQuests or settings.autoForge) then
				return
			end
			local _, hrp, hum = char()
			local living = workspace:FindFirstChild('Living')
			if not hrp or not hum or hum.Health <= 0 or not living then
				return
			end
			for _, m in ipairs(living:GetChildren()) do
				if string.find(m.Name, 'Bomber', 1, true) and m:GetAttribute('IsNpc') then
					local r = mobRoot(m)
					local h = m:FindFirstChildOfClass('Humanoid')
					-- (v277, reported: "some enemy is causing it to jitter back and forth". Measured: 53 of
					-- these steps in 6 s on one Bomber - this rule stepped 24 studs off it and the fight glided
					-- straight back in, three times a second. The rule dates from a 116-health character; a
					-- blast is about 90. The Bomber the bot is fighting is now left to the fight, unless the
					-- character is still weak enough for one blast to matter.)
					local fightingIt = _statusText == 'fighting ' .. m.Name or string.sub(_statusText, 1, #m.Name + 10) == 'fighting ' .. m.Name .. ' '
					if r and h and h.Health > 0 and (r.Position - hrp.Position).Magnitude < 22
						and hum.MaxHealth < 600 then -- (v279: also while mining - 21 steps in 150 s threw it off its rock; a Bomber is simply fought)
						dodgeFrom(r.Position, 24)
						break
					end
				end
			end
			-- mining: a mob near us started its attack - be gone before it lands
			if string.sub(_statusText, 1, 6) == 'mining' then
				-- (not on the way there: that status is up for the whole walk, and each of these steps
				-- threw us back down the route - we outrun the hit by just keeping going)
				local onTheWay = G.FTTravel and (G.FTTravel - hrp.Position).Magnitude > 30
				local wPos = not onTheWay and attackThreat(22)
				if wPos then
					dodgeFrom(wPos, clearDist(wPos))
				end
			end
			-- standing in lava (and not just passing over it): step out to the nearest dry floor
			local ground = groundAt(hrp.Position)
			if Lava.at(ground) and hrp.Position.Y - ground.Y < 2 then
				local best, bestD
				for ring = 6, 48, 6 do
					for i = 0, 11 do
						local a = i / 12 * math.pi * 2
						local spot = groundAt(hrp.Position + Vector3.new(math.cos(a) * ring, 6, math.sin(a) * ring))
						if not Lava.at(spot) and math.abs(spot.Y - hrp.Position.Y) < 14 then
							local _, near = mobsNear(spot, 12)
							local d = ring + #near * 20
							if not bestD or d < bestD then
								best, bestD = spot, d
							end
						end
					end
					if best then
						break
					end
				end
				if best then
					hrp.CFrame = CFrame.new(best + Vector3.new(0, 0.5, 0))
					hrp.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end)
		if not ok then
			task.wait(1)
		end
	end
end)

local function weaponReach()
	local reach = 6
	pcall(function()
		local w = data().Equipped.Weapon
		local E = require(RS.Shared.Data.Equipments)
		local base = E.BaseTypes[E:GetItemBaseType(w.Type)]
		reach = tonumber(base and base.Info and base.Info.Range) or reach
	end)
	return reach
end

-- The game's own swing data for the equipped weapon type: per-combo-hit cooldown, when the
-- hitbox comes out after the swing starts, and how long it stays.
local function weaponCombat()
	local combat
	pcall(function()
		local w = data().Equipped.Weapon
		local E = require(RS.Shared.Data.Equipments)
		combat = E.BaseTypes[E:GetItemBaseType(w.Type)].Combat
	end)
	return type(combat) == 'table' and combat or nil
end

local function fightOnce(forced)
	local function allowed()
		-- (v320: in a raid, Auto kill mobs switched off ends the fight at once - a fight already under
		-- way used to run on for ~9 s on the raid's own "want mobs" flag)
		if forced == nil and not settings.autoMobs and game.PlaceId == 84980181568016
			and not (settings.autoAbyss and workspace:GetAttribute('AbyssRun') == true) then
			return false
		end
		return forced ~= nil or settings.autoMobs or QS.wantMobs
	end
	if not (LocalPlayer.Backpack:FindFirstChild('Weapon') or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('Weapon'))) then
		setStatus('no weapon — forge one first')
		return false
	end
	if kiteLow() then
		kiteHeal()
		return true
	elseif lowHp() then
		retreatAndHeal()
		return true
	end
	local target = forced or mobList()[1]
	if not target then
		setStatus('no mobs found')
		return false
	end
	setStatus(('fighting %s (%.0f studs)%s'):format(target.m.Name, target.d,
		(not forced and not settings.autoMobs and G.FTQuestLock) and (' — for quest ' .. tostring(G.FTQuestLock)) or ''))
	local tool = equip('Weapon')
	local t0 = os.clock()
	-- Swing pacing. A swing's hitbox only exists for ~0.1s, some time after the swing starts
	-- (0.25s for a dagger, 1.4s for a great axe), while a mob's hit lands ~0.6s after it winds up.
	-- So: start swings whenever the cooldown allows (even while standing clear), and be on the mob,
	-- facing it, just for the moment the hitbox is out. Never stand next to a mob mid wind-up.
	local function crowdCheck()
		if os.clock() < (G.FTCrowdAt or 0) then
			return G.FTCrowdMode == true
		end
		G.FTCrowdAt = os.clock() + 0.5
		local _, hC = char()
		local nC = hC and mobsNear(hC.Position, 16) or 0
		-- (on at 5, off again only at 2 or fewer: no flipping back and forth at the edge)
		if false and nC >= 5 and not G.FTCrowdMode then -- (v253: crowd mode OFF. Measured: Hit & run 46 hits / 20,229 hp in 37 s, parry 35 hits / 13,556 hp in 71 s, and a death. The user: revert.)
			G.FTCrowdMode = true
			G.FTCrowdFlips = (G.FTCrowdFlips or 0) + 1
		elseif nC <= 2 and G.FTCrowdMode then
			G.FTCrowdMode = nil
		end
		return G.FTCrowdMode == true
	end
	local crowd0 = crowdCheck()
	local hitRun = combatStyle() == 'Hit & run'
	local atkOnly = combatStyle() == 'Attack only' -- (v237: no swing is ever held back for a block)
	local swingIdx, lastSwingAt, nextSwingAt, sentAt, ownAnimAt, animWorks = 0, 0, 0, nil, 0, false
	local strikeAt, strikeEnd = nil, 0 -- when our hitbox comes out / is gone again
	local STRIKE_LEAD = 0.12 -- be in place this long before the hitbox (position has to reach the server)
	-- (set per swing in swingTick: 0.35s for slow weapons - measured: hopping in 0.12s before a
	-- scythe's hitbox, from 30 studs out, missed 4 swings in 5)
	local UNSAFE_FROM, UNSAFE_TO = 0.22, 0.85 -- seconds into a mob's wind-up during which we must not be near it
	local animConn
	-- our own "Attacking" flag appears when the server has accepted a swing
	local ownAtkAt, ownAtkConn = 0, nil
	pcall(function()
		local c0 = char()
		local st = c0 and c0:FindFirstChild('Status')
		if st then
			ownAtkConn = st.ChildAdded:Connect(function(d)
				if d.Name == 'Attacking' then
					ownAtkAt = os.clock()
					-- (measured with a spear: the flag shows 0.29s after the press and the damage 0.65-0.8s
					-- after it, for a hitbox the data puts at 0.40 - the server runs the swing that much late.
					-- Leaving at 0.40 + 0.2 missed 15 swings of 26.)
					local lag = ownAtkAt - lastSwingAt
					if lag > 0.05 and lag < 0.6 then
						G.FTAccLag = (G.FTAccLag or lag) * 0.7 + lag * 0.3
					end
				end
			end)
		end
	end)
	pcall(function()
		local _, _, myHum = char()
		local animator = myHum and myHum:FindFirstChildOfClass('Animator')
		if animator then
			animConn = animator.AnimationPlayed:Connect(function()
				ownAnimAt = os.clock()
				if sentAt and ownAnimAt - sentAt < 0.3 then
					animWorks = true
				end
			end)
		end
	end)
	-- Safe to be next to the target `ahead` seconds from now? (looks at every mob winding up near it)
	local function strikeSafe(reach, ahead, margin)
		margin = margin or 0.2
		local at = os.clock() + (ahead or 0)
		for m, t in pairs(attackWarn) do
			local r = m.Parent and mobRoot(m)
			if r and target.r.Parent and (r.Position - target.r.Position).Magnitude <= math.max(reach + 10, 22) then
				local age = at - t
				local hw = Attack.hit[(string.gsub(m.Name, '%d+$', ''))]
				if hw and not (hw.seed or (hw.s and #hw.s >= 8)) then
					hw = nil -- (too few samples to trust yet: its whole attack counts as unsafe)
				end
				if hw then
					-- (known kind: only the moment its hit lands is off limits)
					local d0 = Attack.d0[m] or 0
					local far = hw.far
					if not (far and d0 > far.d + 2) and age > hw.min - margin and age < hw.max + 0.12 then
						return false
					end
					if far and d0 >= far.d - 2 and age > far.min - 0.25 and age < far.max + 0.15 then
						return false -- (its shot is aimed about now: not next to it)
					end
				elseif age > UNSAFE_FROM and at < math.max(t + UNSAFE_TO, Attack.ends(m, t)) then
					return false
				end
			end
		end
		return true
	end
	G.FTSwingLog = G.FTSwingLog or {}
	local pend
	local forcedStrike = false -- (this swing went out after being held 2.5s: step in for it whatever is winding up)
	local function track(flush)
		if not pend then
			return
		end
		local now = os.clock()
		local _, h = char()
		if not h or not target.r.Parent then
			pend = nil
			return
		end
		local gap = (h.Position - target.r.Position).Magnitude - math.max(target.r.Size.X, target.r.Size.Z) / 2
		-- (trace: every 0.05s from the press, our gap to the mob; '!' = it is attacking, 'f' = we face away)
		do
			local rel = now - (pend.at - pend.ht)
			pend.tr = pend.tr or {}
			if rel < 1.25 and rel >= (pend.trNext or 0) then
				pend.trNext = rel + 0.05
				local st = target.m:FindFirstChild('Status')
				local atk = st and st:FindFirstChild('Attacking')
				local to = (target.r.Position - h.Position) * Vector3.new(1, 0, 1)
				local facing = to.Magnitude < 0.1 or h.CFrame.LookVector:Dot(to.Unit) > 0.7
				pend.tr[#pend.tr + 1] = ('%.2f:%d%s%s%s'):format(rel, gap, atk and '!' or '', facing and '' or 'f', (target.r.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 3 and ('v%d'):format((target.r.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude) or '')
			end
		end
		if now >= pend.at and not pend.gapAt then
			pend.gapAt = gap -- (where we stood the moment the hitbox was due)
		end
		if now >= pend.at - 0.3 and not pend.dmg and target.h.Health < (pend.hp or target.h.Health) - 0.5 then
			pend.dmg, pend.dmgGap = now - (pend.at - pend.ht), gap -- (when the damage really showed up)
		end
		if now < pend.at - 0.3 then
			pend.hp = target.h.Health
		elseif now <= pend.at + (pend.lag or 0) + pend.hd + 0.05 then
			pend.far = math.max(pend.far or 0, gap)
			if not strikeSafe(pend.reach, 0) then
				pend.unsafe = true
			end
			pend.nearest = math.min(pend.nearest or 999, gap)
		end
		if flush or now > pend.at + (pend.lag or 0) + pend.hd + 0.6 then
			local log = G.FTSwingLog
			log[#log + 1] = ('%s %s#%d ht=%.2f gap %.0f..%.0f reach=%.0f %s'):format((pend.why or '?') .. (pend.unsafe and ' UNSAFE' or '') .. (ownAtkAt >= pend.at - pend.ht - 0.05 and (' acc%.2f'):format(ownAtkAt - (pend.at - pend.ht)) or ' REJECTED') .. (' tool=' .. tostring(pend.tool)), target.m.Name:gsub('%d+$', ''), pend.idx, pend.ht,
				pend.nearest or -1, pend.far or -1, pend.reach, (target.h.Health < (pend.hp or target.h.Health) - 0.5 and 'HIT' or 'miss')
					.. (' at=%.0f'):format(pend.gapAt or -1) .. (pend.dmg and (' dmg+%.2f@%.0f'):format(pend.dmg, pend.dmgGap or -1) or '')
					.. ' | ' .. table.concat(pend.tr or {}, ' '))
			if #log > 80 then
				table.remove(log, 1)
			end
			-- (also kept on disk: the in-memory list is lost on every teleport / rejoin)
			pcall(function()
				local _, _, hm = char()
				appendfile('PlayerTools/forgetools_swings_' .. string.lower(LocalPlayer.Name) .. '.txt',
					('%s hp=%.0f %s\n'):format(os.date('%H:%M:%S'), hm and hm.Health or -1, log[#log]))
			end)
			pend = nil
		end
	end
	-- In a group, where we stand decides the fight: on the side of the target facing away from the
	-- rest, every other mob is behind the target - in front of our swing and further from us -
	-- instead of all around us. Alone (or if that spot is a wall / a drop / lava) it is the old spot:
	-- the side we are already on.
	local function standFor(gap)
		local base = standNear(target.r, gap)
		local tp = target.r.Position
		local _, others = mobsNear(tp, 25)
		local sum, n = Vector3.zero, 0
		for _, e in ipairs(others) do
			if e.m ~= target.m then
				sum += e.r.Position
				n += 1
			end
		end
		if n == 0 then
			return base
		end
		local away = (tp - sum / n) * Vector3.new(1, 0, 1)
		if away.Magnitude < 1 then
			return base
		end
		local r = math.max(target.r.Size.X, target.r.Size.Z) / 2 + (gap or 2)
		local spot = tp + away.Unit * r
		local c = char()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { c, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
		local floor = workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rp)
		if not floor or math.abs(floor.Position.Y + 3 - base.Position.Y) > 6 or Lava.at(floor.Position + Vector3.new(0, 3, 0))
			or workspace:Raycast(tp, spot - tp, rp) then
			return base
		end
		spot = Vector3.new(spot.X, floor.Position.Y + 3, spot.Z)
		return CFrame.lookAt(spot, Vector3.new(tp.X, spot.Y, tp.Z))
	end
	-- Where the SERVER has the mob. The game's hitbox (HitboxClass) is a box around our own
	-- character, about 5.5 studs each way for a spear, tested on the server against the mob as the
	-- server has it. What we see is the mob ~0.25s ago and our hop takes ~0.15s to get there, so a mob
	-- running at 20 is 6-8 studs from where it is on screen: standing right next to its picture missed
	-- (6 swings of 36, all on mobs that were moving). So aim at where it is going.
	local function leadOffset()
		local v = target.r.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		if v.Magnitude < 3 then
			return Vector3.zero
		end
		local off = v * math.clamp((G.FTAccLag or 0.3) + 0.1, 0.2, 0.5)
		if off.Magnitude > 8 then
			off = off.Unit * 8
		end
		-- (a mob running at us stops when it gets to us: never aim past ourselves)
		local _, h0 = char()
		if h0 then
			local toUs = (h0.Position - target.r.Position) * Vector3.new(1, 0, 1)
			if toUs.Magnitude > 0.5 and off:Dot(toUs.Unit) > toUs.Magnitude - 2.5 then
				local along = math.max(0, toUs.Magnitude - 2.5)
				off = toUs.Unit * math.min(along, off:Dot(toUs.Unit))
			end
		end
		return off
	end
	local function hopIn(h, reach)
		-- The hitbox only reaches ~reach studs in front of us: stand well inside it, facing the mob.
		-- (traced: 4-5 studs off missed 14 swings of 16, 2-3 off hit 9 of 10)
		local cf = standFor(math.clamp(reach - 3.5, 1.5, 2.3))
		if settings.combatStyle == 'Behind + dodge' then
			-- (v296) in at the mob's back: its swing goes out the front, away from us
			local tpB = target.r.Position
			local lookB = target.r.CFrame.LookVector * Vector3.new(1, 0, 1)
			if lookB.Magnitude > 0.1 then
				local spotB = tpB - lookB.Unit * (math.max(target.r.Size.X, target.r.Size.Z) / 2 + math.clamp(reach - 3.5, 1.5, 2.3))
				local rpB = RaycastParams.new()
				rpB.FilterType = Enum.RaycastFilterType.Exclude
				rpB.RespectCanCollide = true
				rpB.FilterDescendantsInstances = { (char()), workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
				local floorB = workspace:Raycast(spotB + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rpB)
				if floorB and math.abs(floorB.Position.Y + 3 - h.Position.Y) <= 10 and not Lava.at(floorB.Position + Vector3.new(0, 3, 0))
					and not workspace:Raycast(tpB, spotB - tpB, rpB) then
					spotB = Vector3.new(spotB.X, floorB.Position.Y + 3, spotB.Z)
					cf = CFrame.lookAt(spotB, Vector3.new(tpB.X, spotB.Y, tpB.Z))
					G.FTBehindN = (G.FTBehindN or 0) + 1
				end
			end
		end
		if Lava.at(groundAt(cf.Position)) then
			-- that side of the mob is lava: any dry side will do
			local tp = target.r.Position
			local rad = (Vector3.new(cf.Position.X - tp.X, 0, cf.Position.Z - tp.Z)).Magnitude
			for i = 1, 7 do
				local a = i / 8 * math.pi * 2
				local spot = Vector3.new(tp.X + math.cos(a) * rad, cf.Position.Y, tp.Z + math.sin(a) * rad)
				if not Lava.at(groundAt(spot)) then
					cf = CFrame.lookAt(spot, Vector3.new(tp.X, spot.Y, tp.Z))
					break
				end
			end
		end
		local off = leadOffset()
		if off.Magnitude > 0.5 then
			local spot = cf.Position + off
			if not Lava.at(groundAt(spot)) then
				local tp = target.r.Position + off
				local flat = Vector3.new(tp.X, spot.Y, tp.Z)
				cf = (flat - spot).Magnitude > 0.5 and CFrame.lookAt(spot, flat) or (cf + off)
			end
		end
		h.CFrame = cf
		-- (the server slides the hitbox by our own velocity / 6: stand still for it)
		h.AssemblyLinearVelocity = Vector3.zero
	end
	local function swingTick(reach)
		local now = os.clock()
		if sentAt and now - sentAt > 0.4 then
			-- (only when we know swing animations show up) none for the last press: the game dropped it.
			-- Measured with the scythe: deciding this after 0.18s and pressing again at once re-started
			-- "swing 1" over and over, so the bot never knew when the real hitbox came out.
			if animWorks and ownAnimAt < sentAt then
				swingIdx = math.max(0, swingIdx - 1)
				nextSwingAt = now + 0.2
				strikeAt = nil
				pend = nil
			end
			sentAt = nil
		end
		if strikeAt and now > strikeEnd then
			strikeAt = nil
		end
		if strikeAt or now < nextSwingAt or (not atkOnly and (Block.active() or Block.soon())) or not target.r.Parent then
			return
		end
		local _, h = char()
		if not h or (h.Position - target.r.Position).Magnitude > 45 then
			return
		end
		local combat = weaponCombat()
		local hits = math.max(1, combat and tonumber(combat.Hits) or 1)
		local idx = (now - lastSwingAt > 2.5) and 1 or (swingIdx % hits + 1)
		local cd = combat and type(combat.HitCooldown) == 'table' and tonumber(combat.HitCooldown[idx]) or 0.4
		local ht = combat and type(combat.HitboxTiming) == 'table' and tonumber(combat.HitboxTiming[idx]) or 0.27
		local hd = combat and type(combat.HitboxDuration) == 'table' and tonumber(combat.HitboxDuration[idx]) or 0.1
		-- (v318, the user: "this spear can swing really fast due to having picked attack speed cards, its
		-- only swinging mildly slowly". Measured: Status PercentageAttackHasteBoost 0.025 + the Abyss card's
		-- PercentageAttackHasteBoost_Abyss 1.15, and the swing animation played at speed 2.175 = 1 + both.
		-- The data's cooldown / hitbox times are for speed 1: all of them scale by 1 / speed.)
		local spd = 1
		pcall(function()
			local stH = h.Parent and h.Parent:FindFirstChild('Status')
			for _, x in ipairs(stH and stH:GetChildren() or {}) do
				if x:IsA('ValueBase') and string.sub(x.Name, 1, 26) == 'PercentageAttackHasteBoost' and tonumber(x.Value) then
					spd += x.Value
				end
			end
		end)
		spd = math.clamp(spd, 0.5, 4)
		G.FTAtkSpeed = spd
		cd, ht, hd = cd / spd, ht / spd, hd / spd
		-- (traced at ~300ms round trip: arriving 0.05s before the hitbox on a mob standing still missed
		-- 3 of 3, standing there from the start hit 8 of 8 - our hop reaches the server late. Leaving can
		-- be early for the same reason.)
		STRIKE_LEAD = ht >= 0.6 and 0.42 or 0.3
		local lag = 0 -- (tried staying 0.3s longer for server lag: no better, 16 hits of 31, and more damage taken)
		-- (several mobs winding up one after another around the target: some hit is always about to
		-- land, so the swing used to be held for as long as they kept attacking. After 2.5s of holding
		-- it goes out anyway: trading a hit beats not attacking at all.)
		local held = now - math.max(nextSwingAt, t0)
		G.FTHoldMax = math.max(G.FTHoldMax or 0, held)
		if hitRun and held < 2.5 and not (strikeSafe(reach, ht - STRIKE_LEAD) and strikeSafe(reach, ht - STRIKE_LEAD / 2) and strikeSafe(reach, ht) and strikeSafe(reach, ht + hd)
			and strikeSafe(reach, ht + lag / 2) and strikeSafe(reach, ht + lag) and strikeSafe(reach, ht + lag + hd)) then
			return -- this swing's hitbox would come out while a mob's hit is landing: hold it a moment
		end
		forcedStrike = hitRun and held >= 2.5
		if forcedStrike then
			G.FTForcedSwings = (G.FTForcedSwings or 0) + 1
		end
		if hitRun then
			-- Counter-attack instead of swinging on cooldown. Measured with a great sword (hitbox 0.9s
			-- after the press): 32 of 80 swings missed, every one with us standing 22-47 studs off when
			-- the hitbox came out - the mob was mid-attack right then, so we could not be next to it.
			-- So a swing is started so that its hitbox comes out just AFTER the attack near the target
			-- ends (the mob is recovering: we can stand on it), a follow-up is allowed right after an
			-- attack ended, and otherwise we wait for the next wind-up (1.5s at most: an idle or
			-- stunned mob gets hit anyway).
			local lateEnd, lastOff
			local rad = math.max(reach + 10, 22)
			local tp = target.r.Position
			for m, t in pairs(attackWarn) do
				local r = m.Parent and mobRoot(m)
				if r and (r.Position - tp).Magnitude <= rad then
					local e = Attack.ends(m, t)
					if e > now and (not lateEnd or e > lateEnd) then
						lateEnd = e
					end
				end
			end
			for m, off in pairs(Attack.off) do
				local r = m.Parent and mobRoot(m)
				if r and (r.Position - tp).Magnitude <= rad and (not lastOff or off > lastOff) then
					lastOff = off
				end
			end
			local waited = now - math.max(nextSwingAt, t0)
			local engaged = (h.Position - tp).Magnitude <= reach + 30
			G.FTSwingWhy = lateEnd and ('answer%+.2f'):format(now + ht - lateEnd) or (lastOff and now - lastOff < 0.6) and ('follow%.2f'):format(now - lastOff)
				or (not engaged and 'far') or 'blind'
			-- (an attack in progress whose hit-moment our swing clears - checked above - is answered now)
			if ht >= 0.6 and not lateEnd and engaged and not (lastOff and now - lastOff < 0.6) and waited < 1.5 then
				return -- nothing to answer yet: wait for its next wind-up
			end
		end
		swingIdx = idx
		swing(tool)
		Block.swingAt = now
		lastSwingAt, sentAt = now, now
		-- (a great axe's swing plays for 1.6s but its cooldown says 1.5: a press in between is dropped)
		local dur = (combat and type(combat.AttackDuration) == 'table' and tonumber(combat.AttackDuration[idx]) or 0) / spd
		nextSwingAt = now + math.max(cd, dur) + 0.05
		G.FTSwingDbg = { idx = idx, hits = hits, cd = cd, dur = dur, ht = ht, gap = now - (G.FTSwingDbgAt or now), n = ((G.FTSwingDbg and G.FTSwingDbg.n) or 0) + 1 }
		G.FTSwingDbgAt = now
		strikeAt, strikeEnd = now + ht, now + ht + lag + (ht >= 0.6 and hd + 0.22 or 0.06)
		track(true) -- (close the books on the previous swing)
		pend = { at = now + ht, lag = lag, hd = hd, ht = ht, idx = idx, reach = reach, hp = target.h.Health, why = hitRun and G.FTSwingWhy or 'n/a', tool = tool and tool.Parent and tool.Parent.ClassName or 'nil' }
	end
	local retargetAt, regroupAt = os.clock() + 1, 0
	while alive and allowed() and target.m.Parent and target.h.Health > 0 and os.clock() - t0 < 45 do
		if crowdCheck() ~= crowd0 and not strikeAt then
			return true -- (the crowd came or went: start over in the other style)
		end
		if kiteLow() then
			kiteHeal()
			return true
		elseif lowHp() then
			retreatAndHeal()
			return true
		end
		-- Several mobs: do not chase the one we started on while another is right on top of us.
		-- (only between swings, so a swing in flight still lands on what it was aimed at)
		if not forced and not strikeAt and os.clock() >= retargetAt then
			retargetAt = os.clock() + 0.5
			local _, h0 = char()
			if h0 and not mobTooBig(target.h) then
				-- a mini boss walked up to this fight: get out of its reach and pick another one
				local _, around = mobsNear(h0.Position, 38)
				local boss
				for _, e in ipairs(around) do
					if mobTooBig(e.h) and e.h.MaxHealth < 1e8 and Threat.is(e.m) then
						boss = e
						break
					end
				end
				if boss then
					setStatus(('%s too close — moving the fight elsewhere'):format((string.gsub(boss.m.Name, '%d+$', ''))))
					dodgeFrom(boss.r.Position, 48 - (boss.r.Position - h0.Position).Magnitude)
					break
				end
			end
			local near = mobList()[1]
			if h0 and near and near.m ~= target.m and near.d + 8 < (h0.Position - target.r.Position).Magnitude then
				target = near
				pend = nil
				setStatus(('fighting %s (%.0f studs) — it was closer'):format(target.m.Name, target.d))
			end
		end
		if forced then
			local _, _, fh = char()
			if not fh or fh.Health <= 0 or fh.Health / math.max(1, fh.MaxHealth) < 0.35 then
				break -- defending while mining and getting low: stop trading hits (MineHooks.defend retreats)
			end
		end
		local _, hrp = char()
		local reach = weaponReach()
		local threatPos, rem
		track()
		if hitRun then
			-- The game's own attack warning first, learned animation timing as a fallback.
			local wPos, wEnd = attackThreat(math.max(reach + 14, 24))
			if wPos then
				threatPos, rem = wPos, 0
				G.FTWarnEnd = wEnd
			else
				threatPos, rem = Block.threat(reach + 10)
				G.FTWarnEnd = nil
			end
			swingTick(reach)
		elseif combatStyle() == 'Block / parry' and settings.autoBlock then
			-- Hold block for the whole warned swing (halves the hit, parries it when the timing lines up).
			-- (v202, traced with two Onis: this hold and the shine presses fought over the block - 30
			-- press / release pairs in 3 s, none came up, and a block that IS held through a shine has
			-- no parry left when the hit lands. While mobs here are showing shines, the shine does it alone.)
			local wPos, wEnd = attackThreat(reach + 6)
			if wPos and os.clock() - (Block.anyShineAt or -1e9) > 30 then
				Block.hold(wEnd - os.clock())
			end
		end
		local now = os.clock()
		local kite = false
		if hitRun and target.r.Parent then
			-- only in a crowd: against one mob we stay in reach and dodge just its wind-ups
			-- (and only if one of them can actually hurt us: stepping away from harmless mobs that walk
			-- up was most of the "dodging" left once their attacks were being ignored)
			local nk, crowd = mobsNear(target.r.Position, 25)
			if nk >= 2 then
				for _, e in ipairs(crowd) do
					if Threat.is(e.m) then
						kite = true
						break
					end
				end
			end
		end
		local inRange = hrp and (hrp.Position - target.r.Position).Magnitude <= reach - 1 + math.max(target.r.Size.X, target.r.Size.Z) / 2
		-- (v317, seen live in the Abyss: a Chuthlu under a plank ramp, 8 studs straight below us, counted
		-- as "in range" for reach 11 - 80 swings into the planks, all missed, its health never moved.
		-- In range now also needs the mob at about our height and nothing solid between us.)
		if inRange and hrp then
			local dy = math.abs(hrp.Position.Y - target.r.Position.Y)
			local blocked = false
			if dy > 2.5 then
				pcall(function()
					local rpR = RaycastParams.new()
					rpR.FilterType = Enum.RaycastFilterType.Exclude
					rpR.RespectCanCollide = true
					rpR.FilterDescendantsInstances = { LocalPlayer.Character, workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
					blocked = workspace:Raycast(hrp.Position, target.r.Position - hrp.Position, rpR) ~= nil
				end)
			end
			if blocked or dy > 6 + target.r.Size.Y / 2 then
				inRange = false
				G.FTOutOfReachY = (G.FTOutOfReachY or 0) + 1
			end
		end
		-- (v319, seen live in the Abyss: an Abyssal Watcher at the edge of a plank, 9 studs off but at another
		-- height - "out of reach" by the check above, and every move to it ended on the same plank spot.
		-- Two hours of parrying it, not one hit, then the floor timer burned us down. Now: a mob within 30
		-- studs whose health has not moved for 10 s while out of reach gets us placed right beside it at its
		-- own height; one that still takes nothing for 45 s is left alone for 30 s.)
		if hrp and target.h and target.r.Parent then
			G.FTStallBy = G.FTStallBy or setmetatable({}, { __mode = 'k' })
			local sp = G.FTStallBy[target.m]
			if not sp or target.h.Health < sp.hp - 1 or now - sp.seen > 5 then
				sp = { hp = target.h.Health, at = now, hover = sp and now - sp.seen <= 5 and sp.hover or nil }
				G.FTStallBy[target.m] = sp
			end
			sp.seen = now
			local stall = now - sp.at
			if not inRange and (stall > 10 or sp.hover) and (hrp.Position - target.r.Position).Magnitude < 30 then
				local pS = target.r.Position
				local flatS = (hrp.Position - pS) * Vector3.new(1, 0, 1)
				flatS = flatS.Magnitude > 0.1 and flatS.Unit or Vector3.new(1, 0, 0)
				local posS = pS + flatS * (math.max(target.r.Size.X, target.r.Size.Z) / 2 + 2.5)
				hrp.CFrame = CFrame.lookAt(posS, Vector3.new(pS.X, posS.Y, pS.Z))
				hrp.AssemblyLinearVelocity = Vector3.zero
				inRange = true
				if not sp.hover then
					sp.hover = true
					G.FTStallHover = (G.FTStallHover or 0) + 1
					statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('no damage to %s in 10 s and out of reach - moved beside it at its height'):format(target.m.Name)
				end
			end
			if stall > 45 then
				mobNoRoute[target.m] = now + 30
				G.FTStallSkip = (G.FTStallSkip or 0) + 1
				statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('no damage to %s in 45 s - leaving it for 30 s'):format(target.m.Name)
				G.FTStallBy[target.m] = nil
				break
			end
		end
		local striking = hitRun and strikeAt and now >= strikeAt - STRIKE_LEAD and now <= strikeEnd
		if striking and hrp and (forcedStrike or ((strikeSafe(reach, 0) or (now <= strikeEnd - 0.05 and strikeSafe(reach, 0, 0.08))) and not (rem and rem > 0 and rem < 0.25))) then
			-- Our hitbox is (about to be) out and no hit is landing on us: be on the mob for it.
			G.FTStrikeUntil = strikeEnd -- (the strafe above leaves us alone while our own hitbox is out)
			-- (measured: standing still 2-5 studs off, every swing hit; with the mob lunging into / through
			-- us mid-swing - gap under 1 - 12 of 30 misses. So hold the gap for the whole strike.)
			local aim = target.r.Position + leadOffset()
			local gapNow = ((hrp.Position - aim) * Vector3.new(1, 0, 1)).Magnitude - math.max(target.r.Size.X, target.r.Size.Z) / 2
			if not inRange or gapNow < 1.2 or gapNow > 3.3 then
				hopIn(hrp, reach)
			else
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(aim.X, hrp.Position.Y, aim.Z))
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
			task.wait()
		elseif threatPos and rem and rem < 0.45 then
			-- A hit is about to land: get out of reach, wait for the swing to whiff, then go back in.
			setStatus(('dodging (%s)'):format(target.m.Name))
			dodgeFrom(threatPos, clearDist(threatPos))
			local untilT = G.FTWarnEnd or (os.clock() + math.max(0, rem) + 0.3)
			while alive and os.clock() < untilT do
				task.wait()
				track()
				if hitRun then
					swingTick(reach) -- keep the combo going from out here
					local n2 = os.clock()
					if strikeAt and n2 >= strikeAt - STRIKE_LEAD and n2 <= strikeEnd and (forcedStrike or strikeSafe(reach, 0)) then
						break -- our hitbox is due and their swing is over: go land it
					end
				end
				-- if something else winds up meanwhile, keep moving
				local w2, e2 = attackThreat(22)
				if w2 and e2 > untilT then
					dodgeFrom(w2, clearDist(w2))
					untilT = e2
				end
				-- (measured: a Diamond Spider runs after us for its whole 1.3s attack and lands the hit
				-- 4 studs away, 10 hits in 4 minutes - one step at the start is not enough for those)
				local w4 = attackThreat(14) or Attack.rangedThreat(24)
				if w4 and os.clock() - (G.FTRedodgeAt or 0) > 0.2 then
					G.FTRedodgeAt = os.clock()
					dodgeFrom(w4, clearDist(w4))
				end
				-- (one we already stepped clear of that is still mid-attack: stay out until it is done)
				local w3, e3 = attackThreat(50)
				if w3 and e3 > untilT then
					untilT = e3
				end
				local p2, r2 = Block.threat(8)
				if p2 and r2 and r2 < 0.3 then
					dodgeFrom(p2)
					untilT = math.max(untilT, os.clock() + math.max(0, r2) + 0.3)
				end
			end
		elseif kite and hrp and (hrp.Position - target.r.Position).Magnitude < 40 then
			-- Stand-off. Swings are started from out here; we are next to the mob only for the moment
			-- our hitbox is out (branch above). Anything that walks up to us gets stepped away from.
			local _, close = mobsNear(hrp.Position, 13)
			if close[1] then
				dodgeFrom(close[1].r.Position, 18)
			else
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(target.r.Position.X, hrp.Position.Y, target.r.Position.Z))
			end
			task.wait(0.05)
		elseif hrp and not inRange then
			if hitRun and (hrp.Position - target.r.Position).Magnitude < 30 then
				-- short hop straight back into range (faster than a tween) - but never into a swing
				-- that is already on its way (measured: 155 health gone 2s after arriving at a spider)
				if strikeSafe(reach, 0) and strikeSafe(reach, 0.3) then
					hopIn(hrp, reach)
				else
					task.wait()
				end
			else
				-- (hit & run: stop short of the mob; the hop above takes us in when it is safe)
				local okGo, whyGo = tweenTo(standFor(hitRun and 14 or math.clamp(reach - 3.5, 1.5, 4)), { abort = function()
					return not allowed() or not target.m.Parent or target.h.Health <= 0
				end })
				-- (measured: stood on one spot for 10+ minutes "fighting" mobs 140-820 studs away, every
				-- route coming back "no path" - the result of this move was never looked at. Same cure as
				-- for rocks: three failures from the same place = it is where we stand; go up and over.)
				local _, hs = char()
				if not okGo and hs then
					if target.r and (target.r.Position - hs.Position).Magnitude > 40 then
						-- (and its neighbours: no route to one of a pack is no route to the pack)
						local lvN = workspace:FindFirstChild('Living')
						for _, om in ipairs(lvN and lvN:GetChildren() or {}) do
							local orr = om:GetAttribute('IsNpc') and (om:FindFirstChild('HumanoidRootPart') or om.PrimaryPart)
							if orr and (orr.Position - target.r.Position).Magnitude <= 200 then
								mobNoRoute[om] = os.clock() + 20
							end
						end
						mobNoRoute[target.m] = os.clock() + 20
					end
					G.FTFightStrand = G.FTFightStrand or { n = 0 }
					local S = G.FTFightStrand
					if S.pos and (hs.Position - S.pos).Magnitude < 25 then
						S.n += 1
					else
						S.pos, S.n = hs.Position, 1
					end
					-- (v263, seen live on floor 65: a dodge put it on a ledge just outside the arena wall,
					-- 19 studs from the mobs - safe, but "no way out on foot ... and no clear way over", for
					-- good. An Abyss floor is one walled room: after two failed tries we go back in the way
					-- we came out - steps of at most 28 studs, straight to the mob's own floor.)
					if S.n >= 2 and workspace:GetAttribute('AbyssRun') == true and target.r and target.r.Parent
						and (target.r.Position - hs.Position).Magnitude < 400 and not kiteLow() then
						S.n = 0
						setStatus('abyss: outside the room — stepping back in')
						for _ = 1, 16 do
							local _, hb = char()
							if not hb or not target.r.Parent then
								break
							end
							local goal = target.r.Position + Vector3.new(0, 3, 0)
							local left = goal - hb.Position
							if left.Magnitude <= 6 then
								break
							end
							local nextPos = left.Magnitude <= 28 and (goal - left.Unit * 4) or (hb.Position + left.Unit * 28)
							hb.CFrame = hb.CFrame.Rotation + nextPos
							hb.AssemblyLinearVelocity = Vector3.zero
							task.wait(0.25)
						end
						G.FTAbyssStepIn = (G.FTAbyssStepIn or 0) + 1
						statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. 'abyss: was outside the room with no route — stepped back in to ' .. target.m.Name
						break
					end
					if S.n >= 3 then
						S.n = 0
						local out = Nav.escape()
						statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. (out and 'no route to any mob from here — moved up and over to a spot with routes'
							or ('no route to %s from here (%s) and no way out found yet'):format(target.m.Name, tostring(whyGo)))
						if not out then
							task.wait(2)
						end
						break
					end
					task.wait(0.3)
				elseif okGo and G.FTFightStrand then
					G.FTFightStrand.n = 0
				end
			end
			tool = equip('Weapon')
		else
			if hrp then
				local faceTank = settings.combatStyle == 'Face tank' and atkOnly
				if not hitRun and not faceTank and os.clock() >= regroupAt then
					regroupAt = os.clock() + 1.5
					if mobsNear(hrp.Position, 14) >= 3 then
						local cf = standFor(math.clamp(reach - 3.5, 1.5, 4))
						if (cf.Position - hrp.Position).Magnitude > 6 then
							hrp.CFrame = cf
							hrp.AssemblyLinearVelocity = Vector3.zero
						end
					end
				end
				-- (v250, asked for) Stay BEHIND the mob while hitting it, at a gap set by the weapon's range.
				-- Mobs turn to face us, so this is checked all the time: whenever we are not within the rear
				-- third of the mob, hop to the spot behind its back - unless that spot is a wall, a drop or
				-- lava, and never in the instant our own hitbox is coming out.
				if not hitRun and not faceTank and os.clock() >= (G.FTBehindAt or 0) and not (pend and math.abs(os.clock() - pend.at) < 0.15) then
					G.FTBehindAt = os.clock() + 0.1
					local tpB = target.r.Position
					local lookB = target.r.CFrame.LookVector * Vector3.new(1, 0, 1)
					local toUsB = (hrp.Position - tpB) * Vector3.new(1, 0, 1)
					if lookB.Magnitude > 0.1 and toUsB.Magnitude > 0.1 and lookB.Unit:Dot(toUsB.Unit) > -0.5 then
						G.FTBehindAt = os.clock() + 0.45
						local gapB = math.clamp(reach - 3.5, 1.5, 4)
						local spotB = tpB - lookB.Unit * (math.max(target.r.Size.X, target.r.Size.Z) / 2 + gapB)
						local rpB = RaycastParams.new()
						rpB.FilterType = Enum.RaycastFilterType.Exclude
						rpB.RespectCanCollide = true -- (hit effects were read as walls)
						rpB.FilterDescendantsInstances = { (char()), workspace:FindFirstChild('Living'), workspace:FindFirstChild('Debris') }
						local floorB = workspace:Raycast(spotB + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rpB)
						if floorB and math.abs(floorB.Position.Y + 3 - hrp.Position.Y) <= 10 and not Lava.at(floorB.Position + Vector3.new(0, 3, 0))
							and not workspace:Raycast(tpB, spotB - tpB, rpB) and (spotB - hrp.Position).Magnitude <= 30 then
							spotB = Vector3.new(spotB.X, floorB.Position.Y + 3, spotB.Z)
							hrp.CFrame = CFrame.lookAt(spotB, Vector3.new(tpB.X, spotB.Y, tpB.Z))
							hrp.AssemblyLinearVelocity = Vector3.zero
							G.FTBehindN = (G.FTBehindN or 0) + 1
						else
							G.FTBehindBlocked = (G.FTBehindBlocked or 0) + 1
							local wallB = floorB and workspace:Raycast(tpB, spotB - tpB, rpB)
							G.FTBehindWhy = G.FTBehindWhy or {}
							local whyB = (not floorB and 'nofloor') or (math.abs(floorB.Position.Y + 3 - hrp.Position.Y) > 10 and ('height %.0f'):format(floorB.Position.Y + 3 - hrp.Position.Y))
								or (Lava.at(floorB.Position + Vector3.new(0, 3, 0)) and 'lava') or (wallB and ('wall ' .. wallB.Instance:GetFullName():sub(1, 60))) or 'far'
							G.FTBehindWhy[whyB .. ' @' .. target.m.Name:gsub('%d+$', '')] = (G.FTBehindWhy[whyB .. ' @' .. target.m.Name:gsub('%d+$', '')] or 0) + 1
						end
					end
				end
				-- keep facing the mob every frame: the hitbox comes out in front of us a moment after the swing
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(target.r.Position.X, hrp.Position.Y, target.r.Position.Z))
			end
			if Block.active() and not atkOnly then
				task.wait(0.05) -- holding block through an incoming hit
			else
				if not hitRun then
					swingTick(reach)
				end
				task.wait()
			end
		end
	end
	if ownAtkConn then
		ownAtkConn:Disconnect()
	end
	if animConn then
		animConn:Disconnect()
	end
	if not target.m.Parent or target.h.Health <= 0 then
		stats.kills += 1
	end
	return true
end

-- Mining safety: clear the mobs standing around a rock before mining it.
local function mobFightable(e)
	local cap = mobCap(e.m)
	return (LocalPlayer.Backpack:FindFirstChild('Weapon') or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('Weapon')))
		and (cap <= 0 or e.h.MaxHealth <= cap)
		and e.h.MaxHealth < 1e8 and not e.m.Name:find('Dummy')
		and not Deadly.is(e.m)
		and not mobTooBig(e.h) -- (while mining: step away from a mini boss, do not start a duel with it)
end
MineHooks.clear = function(pos)
	local _, hrp = char()
	if not hrp or (hrp.Position - pos).Magnitude > 80 then
		return false -- far away: walk there first, deal with mobs when we actually meet them
	end
	if settings.ignoreMobs and not settings.autoMobs then
		return false -- (v291: "ignore mobs" - the rock is mined with them around)
	end
	local n, list = mobsNear(pos, 22)
	if n == 0 or not mobFightable(list[1]) then
		return false
	end
	setStatus(('clearing %d mob(s) near the rock first'):format(n))
	fightOnce(list[1])
	return true
end
-- A mob reached us while mining / walking to a rock.
MineHooks.defend = function(th)
	if Deadly.avoid(th.m) then
		-- This kind has killed us before: no fighting, no healing nearby - just get well clear.
		setStatus(('%s nearby (too dangerous to stand next to) — getting away'):format((string.gsub(th.m.Name, '%d+$', ''))))
		for _ = 1, 4 do
			local _, h0 = char()
			local d = h0 and Deadly.near(h0.Position, Deadly.RANGE + 10)
			if not d then
				break
			end
			if not dodgeFrom(d.r.Position) then
				break
			end
			task.wait(0.15)
		end
		return
	end
	local _, _, hum = char()
	local pct = hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth * 100 or 100
	if (tonumber(settings.retreatHp) or 0) > 0 and pct < math.max(40, tonumber(settings.retreatHp) or 0) then
		local spawn = workspace:FindFirstChild('SpawnLocation')
		setStatus(('low health while mining (%.0f%%) — keeping clear of mobs to heal'):format(pct))
		-- (Measured: planning the 370-stud route to spawn took ~3s standing next to the spider, and
		-- that killed us 3 times out of 3. Stay here, stay 30 studs from everything, let health tick.)
		local stuckN = 0
		local tk = os.clock()
		while alive and (settings.autoMine or G.FTQuestWantsOre) and os.clock() - tk < 90 and stuckN < 6 do
			local _, hk, humk = char()
			if not hk or not humk or humk.Health <= 0 then
				return
			end
			local pk = humk.MaxHealth > 0 and humk.Health / humk.MaxHealth * 100 or 100
			if pk >= math.min(60, math.clamp(tonumber(settings.healTo) or 60, 5, 100)) then
				return
			end
			local _, nearK = mobsNear(hk.Position, 30)
			local worst, worstD
			for _, e in ipairs(nearK) do
				local d = (e.r.Position - hk.Position).Magnitude
				if not worstD or d < worstD then
					worst, worstD = e, d
				end
			end
			if worst then
				if dodgeFrom(worst.r.Position, math.max(10, 36 - worstD)) then
					stuckN = 0
				else
					stuckN += 1
				end
			end
			setStatus(('healing (%.0f%%) — keeping clear of mobs'):format(pk))
			task.wait(0.15)
		end
		if stuckN < 6 then
			return
		end
		if spawn and spawn:IsA('BasePart') then
			tweenTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
		end
		local t0 = os.clock()
		while alive and (settings.autoMine or G.FTQuestWantsOre) and os.clock() - t0 < 120 do
			local _, _, h2 = char()
			if not h2 or h2.Health <= 0 then
				return
			end
			local p2 = h2.MaxHealth > 0 and h2.Health / h2.MaxHealth * 100 or 100
			if p2 >= math.clamp(tonumber(settings.healTo) or 60, 5, 100) then
				return
			end
			if mineThreat() and p2 < 40 then
				-- still being chased: keep moving rather than standing still
				local th2 = mineThreat()
				if th2 then
					pcall(dodgeFrom, th2.r.Position)
				end
			end
			setStatus(('healing (%.0f%%)'):format(p2))
			task.wait(1)
		end
		return
	end
	if mobFightable(th) then
		setStatus(('%s is on me — fighting back'):format(th.m.Name))
		fightOnce(th)
		-- (the fight hands back after a dodge, a retarget or 45s: while it is still alive and still
		-- around, it is not over - going back to the rock just brought it along)
		for _ = 1, 5 do
			local _, hf, humf = char()
			if not alive or not hf or not humf or humf.Health <= 0 or lowHp() or humf.Health < humf.MaxHealth * 0.55 or not th.m.Parent or th.h.Health <= 0
				or (th.r.Position - hf.Position).Magnitude > 45 or not mobFightable(th) then
				break
			end
			setStatus(('finishing %s before going back to the rock'):format(th.m.Name))
			fightOnce(th)
		end
	else
		-- Not one we fight (over the "max mob health" slider, no weapon, ...). Only a reason to move
		-- if it is also a threat; otherwise it is left to hit us and the mining goes on.
		local cap = tonumber(settings.maxMobHp) or 0
		local whyNot = (cap > 0 and th.h.MaxHealth > cap) and ('%d HP is over your max mob health of %d'):format(th.h.MaxHealth, cap)
			or Deadly.is(th.m) and 'on the killed-me list'
			or mobTooBig(th.h) and 'a big mob that is a threat'
			or 'no weapon found'
		if Threat.pressure or Deadly.is(th.m) then
			setStatus(('%s is too strong to fight (%s) — moving to another rock'):format(th.m.Name, whyNot))
			pcall(dodgeFrom, th.r.Position)
			task.wait(0.3)
		else
			MineHooks.shrug = MineHooks.shrug or setmetatable({}, { __mode = 'k' })
			MineHooks.shrug[th.m] = os.clock() + 60
			statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('not fighting %s (%s) and it is no threat — mining on'):format(th.m.Name, whyNot)
			G.FTShrugWhy = th.m.Name .. ': ' .. whyNot
		end
	end
end

---------------------------------------------------------------------------
-- Quests: accept from NPCs, work the objectives, turn in, claim quest-board rewards
---------------------------------------------------------------------------
local Quest = {}
do
	local QuestData, ShopData, DialogueNpcs, Functionals
	pcall(function()
		QuestData = require(RS.Shared.Data.Quests)
	end)
	pcall(function()
		local P = require(RS.Shared.Data.Proximities)
		ShopData, DialogueNpcs, Functionals = P.Shop, P.Dialogue, P.Functionals
	end)

	-- Which dialogue tree the server opened last (the game sends it on DialogueRemote).
	local lastTree
	pcall(function()
		if G.FTDialogueConn then
			G.FTDialogueConn:Disconnect()
		end
		G.FTDialogueConn = RS.DialogueEvents.DialogueRemote.OnClientEvent:Connect(function(tree)
			if typeof(tree) == 'Instance' then
				lastTree = tree
			end
		end)
	end)
	local function closeDialogue()
		pcall(function()
			getsenv(LocalPlayer.PlayerGui.DialogueUI.DialogueHandler).Close()
		end)
	end

	-- Commands a dialogue tree can send: give (accept a quest), check / finish (turn in).
	local cmdCache = setmetatable({}, { __mode = 'k' })
	local function treeCommands(tree)
		if cmdCache[tree] then
			return cmdCache[tree]
		end
		local out = { give = {}, check = {}, finish = {} }
		for _, node in ipairs(tree:GetDescendants()) do
			local typ = node:IsA('Configuration') and node:GetAttribute('Type')
			local ms = (typ == 'Command' or typ == 'Condition') and node:FindFirstChildWhichIsA('ModuleScript')
			if ms then
				local ok, mod = pcall(require, ms)
				local fn = ok and type(mod) == 'table' and mod.Run
				local okc, consts = false, nil
				if type(fn) == 'function' then
					okc, consts = pcall(debug.getconstants, fn)
				end
				for _, c in ipairs(okc and consts or {}) do
					if type(c) == 'string' and c ~= 'RunCommand' then
						if c:match('^Give') or c:match('^Accept') or c:match('^Start') then
							out.give[#out.give + 1] = { cmd = c, quest = node:GetAttribute('GivesQuest') }
						elseif c:match('^Check') then
							out.check[#out.check + 1] = c
						elseif c:match('^Finish') or c:match('^Complete') or c:match('^TurnIn') then
							out.finish[#out.finish + 1] = c
						end
					end
				end
			end
		end
		cmdCache[tree] = out
		return out
	end

	local function norm(s)
		return (string.lower(tostring(s)):gsub('[^%a]', ''))
	end
	local function npcModel(name)
		local prox = workspace:FindFirstChild('Proximity')
		if not prox or not name then
			return nil
		end
		local m = prox:FindFirstChild(name)
		if m then
			return m
		end
		-- "Sensei Moro 2" is a different NPC (Island 2) from "Sensei Moro": a name with a number
		-- only matches exactly, never the un-numbered NPC on this island.
		if tostring(name):match('%d') then
			return nil
		end
		local key = norm(name)
		for _, c in ipairs(prox:GetChildren()) do
			if norm(c.Name) == key then
				return c
			end
		end
		return nil
	end
	local function goTo(model)
		local ok, pos = pcall(function()
			return model:GetPivot().Position
		end)
		if not ok then
			return false
		end
		local _, hrp = char()
		if hrp and (hrp.Position - pos).Magnitude < 9 then
			return true
		end
		return tweenTo(CFrame.new(pos + Vector3.new(0, 1, 5)))
	end

	local function eligible(id)
		local d = data()
		local q = QuestData and QuestData[id]
		if not d or not q then
			return false
		end
		if (d.Quests or {})[id] then
			return false
		end
		-- (v288, the user: "those 2 dont have quests continue with the other quests instead". Fisher's
		-- and Henry's follow-up quests are in the game's data but the game does not hand them out;
		-- the bot stood at each for 25 s per visit trying. Left alone; G.FTSkipQuests[id] = false
		-- brings one back.)
		do
			local skip = type(G.FTSkipQuests) == 'table' and G.FTSkipQuests or {}
			local dflt = id == 'FisherQuest2' or id == 'FisherQuest3' or id == 'HenryQuest2' or id == 'HenryQuest3'
			if skip[id] == true or (dflt and skip[id] ~= false) then
				return false
			end
		end
		-- (v213, asked for: daily quests handed out by NPCs, e.g. Daily_Farmer, are not taken.
		-- settings.acceptDaily = true by hand brings them back.)
		if settings.acceptDaily ~= true and (string.find(tostring(id), 'Daily') ~= nil or q.Daily == true or q.Type == 'Daily') then
			return false
		end
		if (d.CompletedQuests or {})[id] and not q.Repeatable then
			return false
		end
		for k, v in pairs(d.CooldownQuests or {}) do
			if k == id or v == id then
				return false
			end
		end
		return true
	end
	local function questDone(qd)
		for _, p in ipairs(qd.Progress or {}) do
			if (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 1) then
				return false
			end
		end
		return true
	end

	local DS, PS = service('DialogueService'), service('ProximityService')
	-- Kept in getgenv so a reload doesn't send it on a full NPC tour again.
	G.FTQuestTreeOf = G.FTQuestTreeOf or {}
	G.FTQuestVisited = G.FTQuestVisited or {}
	local backoff = {} -- [npc|reason] = { n = useless visits, t = last }
	-- Fingerprint of all quest progress, to tell whether a visit did anything.
	local function questSig()
		local d = data()
		local parts = {}
		for id, qd in pairs(d and d.Quests or {}) do
			local p = {}
			for _, x in ipairs(type(qd) == 'table' and qd.Progress or {}) do
				p[#p + 1] = tostring(x.currentProgress)
			end
			parts[#parts + 1] = tostring(id) .. ':' .. table.concat(p, ',')
		end
		table.sort(parts)
		return table.concat(parts, ';')
	end
	local treeOf = G.FTQuestTreeOf -- [npc name] = last tree it opened
	local visited = G.FTQuestVisited -- [npc name] = os.clock() of last accept visit

	-- Walk to an NPC, open its dialogue and send the useful commands.
	local function visit(name, why)
		local npc = npcModel(name)
		if not npc then
			return false
		end
		-- Talked to them twice for this reason and nothing changed: leave them alone for 5 min.
		local bk = npc.Name .. '|' .. why
		local b = backoff[bk]
		if b and b.n >= 2 and os.clock() - b.t < 300 then
			return false
		end
		local before = questSig()
		setStatus(('quest: %s (%s)'):format(npc.Name, why))
		if not goTo(npc) then
			return false
		end
		-- (v285, measured at Fisher: the talk opened from 13 studs away, the game's own window sent
		-- "give quest 2", and no quest came - while by hand, standing next to him, it does. The bot
		-- now steps right up to the NPC (about 4 studs) before talking.)
		pcall(function()
			for _ = 1, 2 do
				local _, hN = char()
				local np = npc:GetPivot().Position
				local flat = hN and (hN.Position - np) * Vector3.new(1, 0, 1)
				if not hN or flat.Magnitude <= 5.5 then
					break
				end
				local spot = np + flat.Unit * 4
				tweenTo(CFrame.new(spot.X, hN.Position.Y, spot.Z))
				task.wait(0.2)
			end
			local _, hN = char()
			G.FTVisitDist = hN and (hN.Position - npc:GetPivot().Position).Magnitude or -1
		end)
		-- The game ignores a new dialogue while the last one is still closing.
		pcall(function()
			local ui = LocalPlayer.PlayerGui:FindFirstChild('DialogueUI')
			local t1 = os.clock()
			while ui and ui.Enabled and os.clock() - t1 < 2 do
				task.wait(0.1)
			end
		end)
		-- We arrive fast: the server has to see us standing at the NPC before it accepts the talk,
		-- and it drops a talk request now and then. Settle first, then ask up to 3 times.
		do
			local _, h0 = char()
			if h0 then
				h0.AssemblyLinearVelocity = Vector3.zero
			end
		end
		task.wait(0.35)
		lastTree = nil
		local ok, opened
		for attempt = 1, 3 do
			ok, opened = pcall(function()
				return PS:Dialogue(npc)
			end)
			local t0 = os.clock()
			while not lastTree and os.clock() - t0 < 1.2 do
				task.wait(0.05)
			end
			if lastTree then
				break
			end
			if attempt < 3 then
				closeDialogue()
				task.wait(0.4)
				goTo(npc) -- (pushed away / not quite there: step back in)
			end
		end
		local tree = lastTree
		visited[npc.Name] = os.clock()
		if not tree then
			closeDialogue()
			return ok and opened ~= false
		end
		treeOf[npc.Name] = tree
		local cmds = treeCommands(tree)
		task.wait(0.3)
		-- (v281: every command sent is written down with what the game answered, in G.FTVisitLog)
		-- (v284: the user gets Fisher's second quest by hand, while the bot - sending its own
		-- commands and then letting the window play - did not. So where a giver has a quest we do
		-- not have, the bot now sends nothing of its own for that visit: only the game's window
		-- talks, exactly as by hand. If that fails twice at a giver, the old way is used again.)
		local PFail = type(G.FTPassiveFail) == 'table' and G.FTPassiveFail or {}
		G.FTPassiveFail = PFail
		local passive = false
		if settings.autoAcceptQuests and (PFail[npc.Name] or 0) < 2 then
			for _, g in ipairs(cmds.give) do
				if g.quest and eligible(g.quest) and (settings.acceptDaily == true or not string.find(g.cmd, 'Daily', 1, true)) then
					passive = true
				end
			end
		end
		local function run(c)
			if passive then
				return nil
			end
			local res = 'no answer'
			local ans
			task.spawn(function()
				local okR, a, b2 = pcall(function()
					return DS:RunCommand(c):await()
				end)
				ans = b2
				res = tostring(okR) .. ' ' .. tostring(a) .. ' ' .. tostring(b2)
			end)
			local tR = os.clock()
			while res == 'no answer' and os.clock() - tR < 1.2 do
				task.wait(0.05)
			end
			local VL = type(G.FTVisitLog) == 'table' and G.FTVisitLog or {}
			G.FTVisitLog = VL
			VL[#VL + 1] = ('%s %s [%s] %s (%s) -> %s'):format(os.date('%H:%M:%S'), npc.Name, tree.Name, c, why, res)
			if #VL > 150 then
				table.remove(VL, 1)
			end
			return ans
		end
		-- (v282, reported: "some quests giver have more dialogue lines and the script is not going
		-- through all of them meaning its not getting the quests". Measured: Fisher and Henry answer
		-- the bare "give quest 2" with nothing. So the talk is now gone through the way the game's
		-- own dialogue window does it - from the first line, each check deciding the branch, each
		-- line's own commands sent as that line comes up, and the answer picked that leads to a quest
		-- we do not have. Only quest commands are sent (give / accept / start / check / finish /
		-- turn in / complete); an answer that leads to no quest is never picked, so nothing is
		-- bought and no travel is started by it.)
		local function nodesOf(node, dir)
			local list = {}
			for _, sv in ipairs(node:GetChildren()) do
				local f = sv:IsA('StringValue') and sv:FindFirstChild(dir)
				for _, ov in ipairs(f and f:GetChildren() or {}) do
					local tgt = ov:IsA('ObjectValue') and ov.Value and ov.Value.Parent
					if tgt and tgt:IsA('Configuration') then
						list[#list + 1] = tgt
					end
				end
			end
			return list
		end
		local function questCmds(node)
			local ms = node:FindFirstChildWhichIsA('ModuleScript')
			local list = {}
			if ms then
				local okM, mod = pcall(require, ms)
				local f = okM and type(mod) == 'table' and mod.Run
				local okc, consts = false, nil
				if type(f) == 'function' then
					okc, consts = pcall(debug.getconstants, f)
				end
				for _, c in ipairs(okc and consts or {}) do
					if type(c) == 'string' and c ~= 'RunCommand' and (c:match('^Give') or c:match('^Accept') or c:match('^Start') or c:match('^Check')
						or c:match('^Finish') or c:match('^Complete') or c:match('^TurnIn')) then
						list[#list + 1] = c
					end
				end
			end
			return list
		end
		local function wanted(node)
			local q = node:GetAttribute('GivesQuest')
			return q ~= nil and eligible(q)
		end
		local function runNode(node)
			local last
			local gq = node:GetAttribute('GivesQuest')
			if gq ~= nil and not (settings.autoAcceptQuests and eligible(gq)) then
				return nil
			end
			for _, c in ipairs(questCmds(node)) do
				if settings.acceptDaily == true or not string.find(c, 'Daily', 1, true) then
					last = run(c)
					task.wait(0.25)
				end
			end
			return last
		end
		-- the commands hanging on a line: sent when that line comes up (as the game's window does)
		local function lineCmds(node)
			for _, inp in ipairs(nodesOf(node, 'Inputs')) do
				if inp:GetAttribute('Type') ~= 'Condition' and inp:FindFirstChildWhichIsA('ModuleScript') and #nodesOf(inp, 'Inputs') == 0 then
					runNode(inp)
				end
			end
		end
		local function leads(node, depth)
			-- does going on from here reach a quest we can take?
			local seen, layer = { [node] = true }, { node }
			for _ = 1, depth do
				local nextLayer = {}
				for _, n in ipairs(layer) do
					if wanted(n) then
						return true
					end
					for _, inp in ipairs(nodesOf(n, 'Inputs')) do
						if wanted(inp) and #nodesOf(inp, 'Inputs') == 0 then
							return true
						end
					end
					for _, o in ipairs(nodesOf(n, 'Outputs')) do
						-- (v286: Henry's "You look worried" goes straight into the check that picks his quest line, so a
					-- check right behind the answer itself is followed; a check further on is not)
					if not seen[o] and o:GetAttribute('Type') ~= 'DialogueRoot' and (o:GetAttribute('Type') ~= 'Condition' or n == node) then
							seen[o] = true
							nextLayer[#nextLayer + 1] = o
						end
					end
				end
				layer = nextLayer
				if #layer == 0 then
					break
				end
			end
			return false
		end
		local okWalk, errWalk = pcall(function()
			local node
			for _, ch in ipairs(tree:GetChildren()) do
				if ch:GetAttribute('Type') == 'DialogueRoot' then
					node = ch
				end
			end
			local steps, been = 0, {}
			while node and steps < 40 do
				steps += 1
				been[node] = (been[node] or 0) + 1
				if been[node] > 2 then
					break
				end
				local typ = node:GetAttribute('Type')
				local outsN = nodesOf(node, 'Outputs')
				local nextNode
				if typ == 'Condition' then
					local r = runNode(node)
					for _, o in ipairs(outsN) do
						if r ~= nil and o:GetAttribute('Priority') == r then
							nextNode = o
						end
					end
				else
					if typ ~= 'DialogueRoot' then
						lineCmds(node)
						if typ ~= 'Prompt' and typ ~= 'Response' then
							runNode(node)
						end
						task.wait(0.45)
					end
					local responses, others = {}, {}
					for _, o in ipairs(outsN) do
						if o:GetAttribute('Type') == 'Response' then
							responses[#responses + 1] = o
						else
							others[#others + 1] = o
						end
					end
					local function byPri(a, b)
						return (tonumber(a:GetAttribute('Priority')) or 0) < (tonumber(b:GetAttribute('Priority')) or 0)
					end
					table.sort(responses, byPri)
					table.sort(others, byPri)
					if #responses > 0 then
						for _, rsp in ipairs(responses) do
							if not nextNode and settings.autoAcceptQuests and leads(rsp, 8) then
								nextNode = rsp
							end
						end
					else
						nextNode = others[1]
					end
				end
				node = nextNode
			end
			G.FTWalkSteps = (G.FTWalkSteps or 0) + steps
		end)
		if not okWalk then
			G.FTWalkErr = tostring(errWalk)
		end
		task.wait(0.3)
		for _, c in ipairs(cmds.check) do
			run(c)
			task.wait(0.2)
		end
		for _, c in ipairs(cmds.finish) do
			run(c)
			task.wait(0.2)
		end
		if settings.autoAcceptQuests then
			for _, g in ipairs(cmds.give) do
				if g.quest and eligible(g.quest) then
					run(g.cmd)
					setStatus('accepted quest ' .. tostring(g.quest))
					task.wait(0.3)
				elseif not g.quest and (settings.acceptDaily == true or not string.find(g.cmd, 'Daily', 1, true)) then
					-- (v281, reported: "some quests giver have more dialogue lines and the script is not going
					-- through all of them". A step that is not labelled with a quest - the Supplier's "Give
					-- Box" and "Give Next" - was never sent, so that chain stood still. Now sent too; the
					-- game decides whether it applies.)
					run(g.cmd)
					task.wait(0.3)
				end
			end
		end
		-- (v283: Fisher and Henry gave nothing for the accept command, sent the bot's way or line by
		-- line. The game's own window was being shut 1-2 s after it opened - before it had typed out
		-- the lines that come before the quest. So when a quest this giver has is still not ours, the
		-- window is left to play: it moves on by itself after each line, and where it offers answers
		-- the one that leads to the quest is clicked. Up to 25 s, and it stops the moment the quest
		-- is ours.)
		if settings.autoAcceptQuests then
			local function stillWanted()
				for _, g in ipairs(cmds.give) do
					if g.quest and eligible(g.quest) and (settings.acceptDaily == true or not string.find(g.cmd, 'Daily', 1, true)) then
						return g.quest
					end
				end
				return nil
			end
			task.wait(0.4)
			local wantQ = stillWanted(); G.FTLingerWhy = 'none'
			local ui = LocalPlayer.PlayerGui:FindFirstChild('DialogueUI')
			if wantQ and ui and ui.Enabled then
				G.FTLinger = (G.FTLinger or 0) + 1
				setStatus(('quest: %s — letting the talk play out for %s'):format(npc.Name, tostring(wantQ)))
				local t0 = os.clock()
				local clicked = {}
				while os.clock() - t0 < 25 and ui.Enabled and stillWanted() do
					-- answers on screen?
					local frames = {}
					for _, fr in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
						if fr.Name == 'Response' and fr:IsA('Frame') and fr.Visible and fr:FindFirstChild('Button') and fr:FindFirstChild('Order') and not clicked[fr]
							and not string.find(fr.Button.Text, 'This is a test answer', 1, true) and not fr:FindFirstAncestorWhichIsA('LuaSourceContainer') then -- (the game's own template answer is not one)
							frames[#frames + 1] = fr
						end
					end
					if #frames > 0 then
						task.wait(0.4) -- (they come up one by one)
						local pick, pickNode
						for _, node in ipairs(tree:GetDescendants()) do
							if not pick and node:IsA('Configuration') and node:GetAttribute('Type') == 'Response' and leads(node, 8) then
								local txt = node:FindFirstChild('Text')
								for _, fr in ipairs(frames) do
									if txt and txt:IsA('StringValue') and #txt.Value > 0 and fr.Parent and string.find(fr.Button.Text, txt.Value, 1, true) then
										pick = fr
										pickNode = node
									end
								end
							end
						end
						if not pick then
							local tx = {}
							for _, fr in ipairs(frames) do tx[#tx + 1] = string.sub(fr.Button.Text, 1, 40) end
							G.FTLingerWhy = 'answers with no quest: ' .. table.concat(tx, ' | ')
							break -- (no answer here leads to a quest: nothing is clicked)
						end
						clicked[pick] = true
						local VL = type(G.FTVisitLog) == 'table' and G.FTVisitLog or {}
						G.FTVisitLog = VL
						VL[#VL + 1] = ('%s %s [%s] clicked answer: %s'):format(os.date('%H:%M:%S'), npc.Name, tree.Name, string.sub(pick.Button.Text, 1, 60))
						-- (v287: firing the button's click did nothing - no command followed. The window's own
						-- "answer chosen" steps are called instead: the answer's commands, then the lines behind it.)
						local okC, errC = pcall(function()
							local env = getsenv(LocalPlayer.PlayerGui.DialogueUI.DialogueHandler)
							pcall(env.ClearResponses)
							env.CommonNodeFunctions(pickNode)
							env.LoadNodes(env.GetOutputNodes(pickNode), tree)
						end)
						if not okC then
							VL[#VL + 1] = 'answer step failed: ' .. tostring(errC)
							pcall(function()
								firesignal(pick.Button.MouseButton1Click)
							end)
						end
						task.wait(0.6)
					end
					task.wait(0.25)
				end
				local VL = type(G.FTVisitLog) == 'table' and G.FTVisitLog or {}
				G.FTVisitLog = VL
				VL[#VL + 1] = ('%s %s [%s] let it play %.1f s for %s -> %s'):format(os.date('%H:%M:%S'), npc.Name, tree.Name, os.clock() - t0, tostring(wantQ), (passive and 'window only: ' or '') .. (stillWanted() and 'still not ours' or 'GOT IT') .. ' / ' .. tostring(G.FTLingerWhy) .. ' / open at end: ' .. tostring(ui.Enabled))
				if not stillWanted() then
					G.FTLingerGot = (G.FTLingerGot or 0) + 1
					PFail[npc.Name] = nil
				elseif passive then
					PFail[npc.Name] = (PFail[npc.Name] or 0) + 1
				end
			end
		end
		task.wait(0.3)
		closeDialogue()
		task.wait(0.5)
		local changed = questSig() ~= before
		if not changed then
			backoff[bk] = { n = (b and b.n or 0) + 1, t = os.clock() }
		else
			backoff[bk] = nil
		end
		-- (v275, reported: "quests arent exactly chaining into each other". The talk that hands a
		-- quest in was opened before the hand-in, so it cannot offer the next quest of the chain, and
		-- the NPC was then left alone for 10 minutes. After a hand-in the NPC is asked again at once.)
		if changed and why == 'turn in' and settings.autoAcceptQuests then
			G.FTChainAsk = (G.FTChainAsk or 0) + 1
			local d0 = data()
			local n0 = 0
			for _ in pairs(d0 and d0.Quests or {}) do
				n0 += 1
			end
			task.wait(0.6)
			visit(name, 'next quest')
			local n1 = 0
			for _ in pairs(d0 and data().Quests or {}) do
				n1 += 1
			end
			if n1 > n0 then
				G.FTChainGot = (G.FTChainGot or 0) + 1
			end
		end
		return true
	end

	local function equipBestPickaxe()
		local d = data()
		local best, bestPrice
		for _, e in ipairs(d and d.Inventory and d.Inventory.Equipments or {}) do
			local name = type(e) == 'table' and (e.Name or e.Type)
			local shop = name and ShopData and ShopData[name]
			if shop and tostring(name):find('Pickaxe') and (not bestPrice or (shop.Price or 0) > bestPrice) then
				best, bestPrice = e, shop.Price or 0
			end
		end
		local cur = d and d.Equipped and d.Equipped.Pickaxe
		if best and not (type(cur) == 'table' and (cur.Name or cur.Type) == (best.Name or best.Type)) then
			pcall(function()
				service('CharacterService'):EquipItem(best)
			end)
			setStatus('equipped ' .. tostring(best.Name or best.Type))
		end
	end

	local function buy(item, qty)
		qty = math.max(1, tonumber(qty) or 1)
		local shop = ShopData and ShopData[item]
		local d = data()
		if not shop or not d or (d.Gold or 0) < (shop.Price or math.huge) * qty then
			setStatus(('quest: need %s gold for %s'):format(tostring(shop and shop.Price or '?'), item))
			return false
		end
		local stand = npcModel(item)
		if not stand or not goTo(stand) then
			return false
		end
		setStatus(('buying %d x %s (%s gold each)'):format(qty, item, tostring(shop.Price)))
		pcall(function()
			PS:Purchase(item, qty)
		end)
		task.wait(1)
		if item:find('Pickaxe') then
			equipBestPickaxe()
		end
		return true
	end

	-- Auto-buy the best pickaxe for the island you are on: the most expensive one whose stall
	-- is here, that you can afford and don't already own, skipping locked ones, then equip it.
	local function buyBestIslandPickaxe()
		local d = data()
		if not d then
			return false
		end
		local gold = tonumber(d.Gold) or 0
		local ownedBest, owned = 0, {}
		for _, e in ipairs(d.Inventory and d.Inventory.Equipments or {}) do
			local nm = type(e) == 'table' and (e.Name or e.Type)
			if nm then
				owned[nm] = true
				local sh = ShopData and ShopData[nm]
				if sh and tostring(nm):find('Pickaxe') then
					ownedBest = math.max(ownedBest, tonumber(sh.Price) or 0)
				end
			end
		end
		local prox = workspace:FindFirstChild('Proximity')
		local pick, pickPrice
		for _, c in ipairs(prox and prox:GetChildren() or {}) do
			local name = c.Name
			local sh = ShopData and ShopData[name]
			if sh and tostring(name):find('Pickaxe') and not owned[name] then
				local price = tonumber(sh.Price) or math.huge
				if price <= gold and price > ownedBest and (not pickPrice or price > pickPrice) then
					local unlocked = true
					if sh.Condition then
						local okc, res = pcall(sh.Condition)
						unlocked = okc and res and true or false
					elseif sh.LockedText then
						unlocked = false
					end
					if unlocked then
						pick, pickPrice = name, price
					end
				end
			end
		end
		if not pick then
			return false
		end
		setStatus(('auto pickaxe: buying %s (%s gold)'):format(pick, tostring(pickPrice)))
		return buy(pick)
	end
	Quest.buyBestPickaxe = buyBestIslandPickaxe

	-- (v241, asked for) Pickaxe plan, one-shot: G.FTPickPlan = { item = 'Yin-Yang Pickaxe',
	-- sell = 'Oni Pickaxe', race = 'Goblin' }. Waits until gold + what the old pickaxe sells for
	-- (75% of its shop price, read from the game's own sell code) covers the new one at the
	-- race's shop discount. Then: switch to that race, MEASURE the discount on the cheapest stall
	-- item here (nothing is sold on an assumed discount), sell the old pickaxe at Marbles (the
	-- game hides a worn item from the sell list, so the spare one is worn first), buy, equip,
	-- switch the race back, and mine the rocks only the new pickaxe can break. Every step is
	-- checked; anything unexpected stops the plan and puts the race / pickaxe back.
	local function planLog(msg)
		local line = os.date('%H:%M:%S ') .. 'pickaxe plan: ' .. msg
		statusLog[#statusLog + 1] = line
		setStatus('pickaxe plan: ' .. msg)
		G.FTPickPlanLog = G.FTPickPlanLog or {}
		table.insert(G.FTPickPlanLog, line)
		pcall(function()
			local wf = isfile('PlayerTools/forgetools_pickplan.txt') and appendfile or writefile
			wf('PlayerTools/forgetools_pickplan.txt', line .. '\n')
		end)
	end
	local function gold()
		local d = data()
		return d and tonumber(d.Gold) or 0
	end
	local function ownsItem(name)
		local d = data()
		for _, e in ipairs(d and d.Inventory and d.Inventory.Equipments or {}) do
			if type(e) == 'table' and (e.Name or e.Type) == name then
				return e
			end
		end
		return nil
	end
	local function wornPick()
		local d = data()
		local cur = d and d.Equipped and d.Equipped.Pickaxe
		return type(cur) == 'table' and (cur.Name or cur.Type) or nil
	end
	local function wear(name)
		local e = ownsItem(name)
		if not e then
			return false
		end
		pcall(function()
			service('CharacterService'):EquipItem(e)
		end)
		local t0 = os.clock()
		while os.clock() - t0 < 5 and wornPick() ~= name do
			task.wait(0.25)
		end
		return wornPick() == name
	end
	local function setRace(name)
		local d = data()
		if not d or d.Race == name then
			return d ~= nil
		end
		local idx
		for i, n in pairs(type(d.RaceSlots) == 'table' and d.RaceSlots or {}) do
			if n == name then
				idx = i
			end
		end
		if not idx then
			return false
		end
		-- (v243) the switch has a cooldown: a second one a few seconds after the first is refused
		-- (measured: back to Angel 8 s after going Goblin did nothing, 2 minutes later it went at once)
		for _ = 1, 6 do
			pcall(function()
				service('RaceService'):SwitchSlot(idx):await()
			end)
			local t0 = os.clock()
			while os.clock() - t0 < 6 and data().Race ~= name do
				task.wait(0.25)
			end
			if data().Race == name then
				return true
			end
			task.wait(10)
		end
		return data().Race == name
	end
	Quest.pickPlan = function()
		local plan = G.FTPickPlan
		if type(plan) ~= 'table' or type(plan.item) ~= 'string' then
			return false
		end
		if G.FTBossFight or os.clock() < (plan.nextAt or 0) then
			return false
		end
		local shop, old = ShopData and ShopData[plan.item], ShopData and ShopData[plan.sell]
		local d = data()
		if not shop or not old or not d then
			return false
		end
		if ownsItem(plan.item) then
			G.FTPickPlan = nil
			return false
		end
		local price, sellFor = tonumber(shop.Price) or math.huge, 0.75 * (tonumber(old.Price) or 0)
		local disc = tonumber(plan.disc) or 0.88
		plan.need = price * disc - sellFor + 2000
		if gold() < plan.need then
			return false
		end
		do
			-- (v243: it started inside the Asura arena, 5,000 studs from every stall)
			local st0 = npcModel(plan.item)
			local _, h0 = char()
			local okp, p0 = pcall(function()
				return st0:IsA('BasePart') and st0.Position or st0:GetPivot().Position
			end)
			if not (st0 and h0 and okp) or (p0 - h0.Position).Magnitude > 3000 then
				plan.nextAt = os.clock() + 15
				return false
			end
		end
		plan.nextAt = os.clock() + 60
		if not ownsItem(plan.sell) and not plan.sold then
			planLog(('no %s to sell - plan stopped'):format(plan.sell))
			G.FTPickPlan = nil
			return true
		end
		if shop.Condition then
			local okc, res = pcall(shop.Condition)
			if not (okc and res) then
				planLog(('the stall will not sell %s yet (%s) - waiting'):format(plan.item, tostring(res)))
				plan.nextAt = os.clock() + 300
				return true
			end
		end
		local race0 = d.Race
		planLog(('gold %.0f covers %s at x%.2f after selling %s for %.0f - starting'):format(gold(), plan.item, disc, plan.sell, sellFor))
		if not setRace(plan.race) then
			planLog(('could not switch to %s - plan stopped'):format(tostring(plan.race)))
			G.FTPickPlan = nil
			return true
		end
		local function back(why, stop)
			planLog(why)
			if type(race0) == 'string' and not setRace(race0) then
				planLog(('could not switch back to %s'):format(race0))
			end
			if stop then
				G.FTPickPlan = nil
			end
			return true
		end
		if not plan.disc and not plan.sold then
			-- measure the discount on the cheapest thing a stall here sells
			-- (v242: the first try went through the quest "buy" helper and nothing was bought. Now the
			-- way the potion top-up does it, which is known to work: stand at the stall, Purchase, await.)
			local prox = workspace:FindFirstChild('Proximity')
			local _, hp = char()
			local function ownedQty(name)
				for _, it in pairs(data().Inventory.Misc or {}) do
					if type(it) == 'table' and it.Name == name then
						return tonumber(it.Quantity) or 0
					end
				end
				return 0
			end
			local cheap, cheapPrice, cheapPos
			for _, c in ipairs(prox and prox:GetChildren() or {}) do
				local sh = ShopData and ShopData[c.Name]
				local pr = sh and tonumber(sh.Price)
				local okp, pos = pcall(function()
					return c:IsA('BasePart') and c.Position or c:GetPivot().Position
				end)
				if pr and okp and hp and pr >= 50 and pr <= 20000 and not sh.Condition and not sh.LockedText and not string.find(c.Name, 'Pickaxe', 1, true)
					and ownedQty(c.Name) < (tonumber(sh.MaxPurchaseLimit) or 1e9) and (pos - hp.Position).Magnitude < 3000 then
					if not cheapPrice or pr < cheapPrice or (pr == cheapPrice and (pos - hp.Position).Magnitude < (cheapPos - hp.Position).Magnitude) then
						cheap, cheapPrice, cheapPos = c.Name, pr, pos
					end
				end
			end
			if not cheap then
				return back('no cheap stall item here to measure the discount on - plan stopped', true)
			end
			if (hp.Position - cheapPos).Magnitude > 9 and not tweenTo(CFrame.new(cheapPos + Vector3.new(0, 1, 5))) then
				plan.nextAt = os.clock() + 120
				return back(('could not get to the %s stall - trying again later'):format(cheap), false)
			end
			task.wait(0.3)
			local g0 = gold()
			pcall(function()
				PS:Purchase(cheap, 1):await()
			end)
			local tb = os.clock()
			while os.clock() - tb < 4 and gold() == g0 do
				task.wait(0.1)
			end
			task.wait(0.5)

			local ratio = (g0 - gold()) / cheapPrice
			planLog(('bought 1 %s listed at %d as %s: paid %.0f (x%.3f)'):format(cheap, cheapPrice, tostring(plan.race), g0 - gold(), ratio))
			if ratio > 0.5 and ratio < 0.965 then
				plan.disc = ratio
			elseif ratio >= 0.965 and ratio < 1.05 then
				plan.disc = 1
			else
				return back('that purchase did not go through as expected - plan stopped', true)
			end
			disc = plan.disc
			plan.need = price * disc - sellFor + 2000
			if gold() < plan.need then
				plan.nextAt = 0
				return back(('the real discount is x%.3f: %.0f gold needed, have %.0f - waiting on'):format(disc, plan.need, gold()), false)
			end
		end
		if not plan.sold then
		-- sell the old pickaxe (a spare one is worn meanwhile: a worn item is not sellable)
		local spare
		for _, e in ipairs(data().Inventory.Equipments or {}) do
			local nm = type(e) == 'table' and (e.Name or e.Type)
			if nm and nm ~= plan.sell and string.find(tostring(nm), 'Pickaxe', 1, true) then
				spare = nm
			end
		end
		if not spare then
			return back('no second pickaxe to hold while selling (the game keeps one) - plan stopped', true)
		end
		local npc = npcModel('Marbles')
		if not npc or not goTo(npc) then
			plan.nextAt = os.clock() + 120
			return back('could not get to Marbles - trying again later', false)
		end
		if not wear(spare) then
			return back(('could not put on %s - plan stopped'):format(spare), true)
		end
		local g1 = gold()
		pcall(function()
			PS:ForceDialogue(npc, 'SellConfirm')
		end)
		task.wait(0.6)
		pcall(function()
			DS:RunCommand('SellConfirm', { Basket = { [plan.sell] = true } })
		end)
		local t0 = os.clock()
		while os.clock() - t0 < 8 and ownsItem(plan.sell) do
			task.wait(0.3)
		end
		task.wait(0.5)
		closeDialogue()
		planLog(('sold %s: gold %.0f -> %.0f, still owned %s'):format(plan.sell, g1, gold(), tostring(ownsItem(plan.sell) ~= nil)))
		if ownsItem(plan.sell) then
			wear(plan.sell)
			return back('the sale did not go through - old pickaxe back on, plan stopped', true)
		end
		plan.sold = true
		end
		if gold() < price * disc - 1 then
			return back(('SOLD, but gold %.0f is short of %.0f - not buying. Plan stopped: tell Claude.'):format(gold(), price * disc), true)
		end
		local stand = npcModel(plan.item)
		local okSp, standPos = pcall(function()
			return stand:IsA('BasePart') and stand.Position or stand:GetPivot().Position
		end)
		local _, hb = char()
		-- (v244: the first purchase did not land after the quest-style walk; now right at the stall,
		-- like the potion top-up, and what the game answers is written down)
		if not (stand and okSp and hb) or ((hb.Position - standPos).Magnitude > 8 and not tweenTo(CFrame.new(standPos + Vector3.new(0, 1, 4)))) then
			return back(('SOLD, but could not get to the %s stall. Plan stopped: tell Claude.'):format(plan.item), true)
		end
		task.wait(0.5)
		local g2 = gold()
		local _, hb2 = char()
		local okB, a1, a2 = pcall(function()
			return PS:Purchase(plan.item, 1):await()
		end)
		planLog(('purchase asked as %s, %.0f studs from the stall, gold %.0f: %s %s %s'):format(tostring(data().Race), hb2 and (hb2.Position - standPos).Magnitude or -1, g2, tostring(okB), tostring(a1), tostring(a2)))
		local t1 = os.clock()
		while os.clock() - t1 < 10 and not ownsItem(plan.item) do
			task.wait(0.3)
		end
		if not ownsItem(plan.item) then
			return back(('SOLD, but the purchase of %s did not land (gold %.0f). Plan stopped: tell Claude.'):format(plan.item, gold()), true)
		end
		wear(plan.item)
		planLog(('bought %s for %.0f, wearing %s'):format(plan.item, g2 - gold(), tostring(wornPick())))
		if type(plan.rocks) == 'table' then
			G.FTCraftRocks = plan.rocks
			G.FTCraftNeed = plan.oreNeed
		end
		return back('done', true)
	end

	local function sellSpare(target)
		local d = data()
		local okMod, Equip = pcall(function()
			return require(RS.Shared.Data.Equipments)
		end)
		if not d or not okMod then
			return false
		end
		local equippedGuid = {}
		for _, e in pairs(d.Equipped or {}) do
			if type(e) == 'table' and e.GUID then
				equippedGuid[e.GUID] = true
			end
		end
		local worst
		for _, e in ipairs(d.Inventory.Equipments or {}) do
			if type(e) == 'table' and e.GUID and not equippedGuid[e.GUID] and not e.Favorite and not e.Favorited then
				local okT, slot = pcall(Equip.GetItemType, Equip, e.Type or e.Name)
				if okT and slot ~= 'Pickaxe' and (target == 'Any' or target == 'Equipment' or slot == target) then
					if not worst or itemScore(e) < itemScore(worst) then
						worst = e
					end
				end
			end
		end
		if not worst then
			return false
		end
		local npc = npcModel('Marbles')
		if not npc or not goTo(npc) then
			return false
		end
		setStatus(('quest: selling spare %s'):format(tostring(worst.Type)))
		pcall(function()
			PS:ForceDialogue(npc, 'SellConfirm')
		end)
		task.wait(0.5)
		pcall(function()
			DS:RunCommand('SellConfirm', { Basket = { [worst.GUID] = true } })
		end)
		task.wait(0.8)
		closeDialogue()
		return true
	end

	-- Auto sell gear: weapons / armor that are not worn and are not the best of their slot
	-- (weapon, helmet, chestplate, leggings) go to Marbles. Favorited items and pickaxes stay.
	local function gearToSell()
		local d = data()
		local okMod, Equip = pcall(function()
			return require(RS.Shared.Data.Equipments)
		end)
		if not d or not d.Inventory or not okMod or not Equip then
			return {}
		end
		local function slotKey(e)
			local ok, t = pcall(Equip.GetItemType, Equip, e.Type or e.Name)
			if not ok then
				return nil
			end
			if t == 'Weapon' then
				return t
			elseif t ~= 'Armor' then
				return nil -- pickaxes, runes, anything unknown: never sold
			end
			local okB, base = pcall(Equip.GetItemBaseType, Equip, e.Type or e.Name)
			base = tostring(okB and base or e.Type)
			for _, piece in ipairs({ 'Helmet', 'Chestplate', 'Leggings' }) do
				if base:find(piece) or tostring(e.Type):find(piece) then
					return piece
				end
			end
			return nil
		end
		local worn, best = {}, {}
		for _, w in pairs(d.Equipped or {}) do
			if type(w) == 'table' and w.GUID then
				worn[w.GUID] = true
				local key = slotKey(w)
				if key and itemScore(w) > (best[key] or -1) then
					best[key] = itemScore(w)
				end
			end
		end
		local keepGuid = {}
		for _, e in ipairs(d.Inventory.Equipments or {}) do
			if type(e) == 'table' and e.GUID and e.Type then
				local key = slotKey(e)
				if key and itemScore(e) > (best[key] or -1) + 0.01 then
					best[key] = itemScore(e)
					keepGuid[key] = e.GUID -- better than what is worn / seen so far: keep it
				end
			end
		end
		local out = {}
		for _, e in ipairs(d.Inventory.Equipments or {}) do
			if type(e) == 'table' and e.GUID and e.Type and not worn[e.GUID] and not e.Favorite and not e.Favorited then
				local key = slotKey(e)
				if key and keepGuid[key] ~= e.GUID and itemScore(e) > 0 then
					out[#out + 1] = e
				end
			end
		end
		return out
	end
	local gearSellAt = 0
	function Quest.gearSellNeeded()
		if not settings.autoSellGear or os.clock() < gearSellAt then
			return false
		end
		return #gearToSell() >= 3 -- (a few at a time: no walk to the shop for every single item)
	end
	function Quest.sellGear()
		local list = gearToSell()
		if #list == 0 then
			return false
		end
		gearSellAt = os.clock() + 120
		local npc = npcModel('Marbles')
		if not npc then
			setStatus('auto sell gear: Marbles not found')
			return false
		end
		local names
		local function sale()
			local now = gearToSell()
			if #now == 0 then
				return 0, 0
			end
			local basket = {}
			names = {}
			for _, e in ipairs(now) do
				basket[e.GUID] = true
				names[#names + 1] = tostring(e.Type)
			end
			local goldBefore = (data() or {}).Gold or 0
			local before = #(data().Inventory.Equipments or {})
			setStatus(('selling %d spare gear'):format(#now))
			pcall(function()
				PS:ForceDialogue(npc, 'SellConfirm')
			end)
			task.wait(0.4)
			pcall(function()
				DS:RunCommand('SellConfirm', { Basket = basket })
			end)
			local tg = os.clock()
			while os.clock() - tg < 3 and #(data().Inventory.Equipments or {}) == before do
				task.wait(0.1)
			end
			task.wait(0.3)
			closeDialogue()
			return before - #(data().Inventory.Equipments or {}), ((data() or {}).Gold or 0) - goldBefore
		end
		-- from wherever we are first; standing at the shop only if that did not go through
		local sold, gold = sale()
		if sold <= 0 and goTo(npc) then
			sold, gold = sale()
		end
		if sold > 0 then
			gearSellAt = 0
			setStatus(('sold %d spare gear for %s gold (%s)'):format(sold, tostring(math.floor(gold)), table.concat(names or {}, ', '):sub(1, 80)))
		else
			setStatus('auto sell gear: the shop did not take the items — trying again in 2 min')
		end
		return sold > 0
	end

	-- Auto recycle (v326, asked for: "if ur auto forging, go recycle the shit that was forged"):
	-- spare gear goes back into ores instead of being sold. Same picks as auto sell gear (never
	-- worn, the best of each slot, favorites, pickaxes). The game charges gold equal to the items'
	-- sell price and gives back half the ores (InventoryService.RecycleBasket, the Recycle screen).
	local recycleAt = 0
	function Quest.recycleNeeded()
		if not settings.autoRecycle or os.clock() < recycleAt then
			return false
		end
		return #gearToSell() >= 1
	end
	function Quest.recycleGear()
		if #gearToSell() == 0 then
			return false
		end
		recycleAt = os.clock() + 120
		local IS = service('InventoryService')
		local okE, Equip = pcall(function()
			return require(RS.Shared.Data.Equipments)
		end)
		if not IS or not okE or not Equip then
			setStatus("auto recycle: the game's inventory service was not found")
			return false
		end
		local names, short = {}, 0
		local function run()
			local now = gearToSell()
			table.sort(now, function(a, b)
				return itemScore(a) < itemScore(b)
			end)
			local gold = tonumber((data() or {}).Gold) or 0
			local basket, cost = {}, 0
			names, short = {}, 0
			for _, e in ipairs(now) do
				local okP, p = pcall(Equip.CalculatePrice, Equip, e)
				p = okP and tonumber(p) or 0
				if cost + p <= gold then
					basket[e.GUID] = true
					cost += p
					names[#names + 1] = tostring(e.Type)
				else
					short += 1
				end
			end
			if #names == 0 then
				return 0, 0
			end
			local before = #(data().Inventory.Equipments or {})
			setStatus(('recycling %d spare gear (%s gold)'):format(#names, tostring(math.floor(cost))))
			pcall(function()
				IS:RecycleBasket(basket)
			end)
			local t0 = os.clock()
			while os.clock() - t0 < 3 and #(data().Inventory.Equipments or {}) == before do
				task.wait(0.1)
			end
			return before - #(data().Inventory.Equipments or {}), cost
		end
		-- from wherever we are first; at Marbles (who has the Recycle screen) only if that did not go through
		local done, cost = run()
		if done <= 0 and #names > 0 then
			local npc = npcModel('Marbles')
			if npc and goTo(npc) then
				done, cost = run()
				closeDialogue()
			end
		end
		if done > 0 then
			recycleAt = 0
			setStatus(('recycled %d spare gear for %s gold (%s)'):format(done, tostring(math.floor(cost)), table.concat(names, ', '):sub(1, 80)))
		elseif #names == 0 and short > 0 then
			setStatus(('auto recycle: not enough gold for %d spare item(s) - trying again in 2 min'):format(short))
		else
			setStatus('auto recycle: the game did not take the items - trying again in 2 min')
		end
		return done > 0
	end

	-- "Bring X to NPC" quests (Lost Guitar, Lost Cat): pick up the NPC's item (a Functionals prop
	-- named NPC..Item, e.g. BardGuitar) and then talk to the NPC.
	local extraAt = {}
	local function extraFetch(npcName)
		if os.clock() - (extraAt[npcName] or 0) < 45 then
			return false
		end
		extraAt[npcName] = os.clock()
		local d = data()
		local misc = d and d.MiscDialogues or {}
		local prox = workspace:FindFirstChild('Proximity')
		local key = norm(npcName)
		local found = false
		for name in pairs(Functionals or {}) do
			if norm(name):sub(1, #key) == key and norm(name) ~= key then
				if misc['Took' .. name] then
					found = true
				else
					local inst = prox and prox:FindFirstChild(name)
					if inst and goTo(inst) then
						setStatus('quest: picking up ' .. name)
						pcall(function()
							PS:Functionals(inst)
						end)
						task.wait(1.2)
						found = true
					end
				end
			end
		end
		if not found then
			-- No item to pick up (e.g. "deliver the supplies to Gurak"): just talk to them.
			if npcModel(npcName) then
				return visit(npcName, 'deliver')
			end
			return false -- NPC / item isn't on this island
		end
		return visit(npcName, 'deliver')
	end

	-- "Enhance any item to +N": enhance the equipped weapon at the Enhancer.
	local enhanceAt = 0
	local function enhanceTo(level)
		if os.clock() - enhanceAt < 60 then
			return false
		end
		enhanceAt = os.clock()
		local d = data()
		local w = d and d.Equipped and d.Equipped.Weapon
		if type(w) ~= 'table' or not w.GUID or (tonumber(w.Upgrade) or 0) >= level then
			return false
		end
		local npc = npcModel('Enhancer')
		if not npc or not goTo(npc) then
			return false
		end
		local ES = service('EnhanceService')
		local function have(name)
			local inv = data().Inventory
			if type(inv[name]) == 'number' then
				return inv[name]
			end
			for _, it in ipairs(inv.Misc or {}) do
				if it.Name == name then
					return tonumber(it.Quantity) or 0
				end
			end
			return 0
		end
		for _ = 1, 15 do
			local cur
			for _, e in ipairs(data().Inventory.Equipments or {}) do
				if type(e) == 'table' and e.GUID == w.GUID then
					cur = e
				end
			end
			cur = cur or w
			if (tonumber(cur.Upgrade) or 0) >= level then
				break
			end
			local okr, req = pcall(function()
				return select(2, ES:GetUpgradeRequirements(cur):await())
			end)
			if okr and type(req) == 'table' and type(req.materials) == 'table' then
				for _, v in pairs(req.materials) do
					local mname = type(v.material) == 'table' and v.material.Name or tostring(v.material)
					if have(mname) < (tonumber(v.quantity) or 0) then
						setStatus(('quest: need %s x%s to enhance'):format(mname, tostring(v.quantity)))
						return true
					end
				end
			end
			pcall(function()
				ES:EnhanceEquipment(cur.GUID):await()
			end)
			setStatus(('enhancing %s (now +%s, want +%d)'):format(tostring(cur.Type), tostring(cur.Upgrade or 0), level))
			task.wait(1.2)
		end
		return true
	end


	-- "Attach a rune": put one of your runes on an equipped item at the Runemaker (costs gold).
	local runeAt = 0
	local function attachRune()
		if os.clock() - runeAt < 60 then
			return false
		end
		runeAt = os.clock()
		local d = data()
		local okR, Runes = pcall(function()
			return require(RS.Shared.Data.Runes)
		end)
		local okE, Equip = pcall(function()
			return require(RS.Shared.Data.Equipments)
		end)
		if not (d and okR and okE) then
			return false
		end
		local equipped = {}
		for _, e in pairs(d.Equipped or {}) do
			if type(e) == 'table' then
				equipped[#equipped + 1] = e
			end
		end
		local pickItem, pickRune
		for _, it in ipairs(d.Inventory.Misc or {}) do
			local info = it.GUID and it.Id and Runes.Runes and Runes.Runes[it.Id]
			if info then
				for _, e in ipairs(equipped) do
					local okT, slot = pcall(Equip.GetItemType, Equip, e.Type or e.Name)
					-- Only items with a GUID can take runes (pickaxes are stored by name).
					if e.GUID and okT and table.find(info.WhitelistedTypes or {}, slot) and #(e.Runes or {}) == 0 then
						pickItem, pickRune = e, it
						break
					end
				end
			end
			if pickItem then
				break
			end
		end
		if not pickItem then
			setStatus('quest: no rune that fits your gear')
			return false
		end
		local npc = npcModel('Runemaker')
		if not npc or not goTo(npc) then
			return false
		end
		setStatus(('quest: attaching %s to %s'):format(tostring(pickRune.Id), tostring(pickItem.Type or pickItem.Name)))
		pcall(function()
			service('RuneService'):PurchaseAttach(pickItem.GUID or pickItem.Name, pickRune.GUID):await()
		end)
		task.wait(1)
		return true
	end


	-- "Bring 1 'Health Potion' to Isaac" / "Bring Monke 30 bananite" / "Bring 3 Fireite to Line".
	local function parseBring(desc)
		desc = tostring(desc or '')
		local n, item = desc:match("[Bb]ring%s+(%d+)%s+'([^']+)'")
		if not n then
			n, item = desc:match('[Bb]ring%s+(%d+)%s+(.-)%s+to%s')
		end
		if not n then
			local _
			_, n, item = desc:match('[Bb]ring%s+(%a+)%s+(%d+)%s+([%a%s]+)')
		end
		if not n then
			-- "Bring 30 Epic Essence." (Captain Rowan Final): no "to NPC" part, no quotes.
			n, item = desc:match('[Bb]ring%s+(%d+)%s+(.-)%.?%s*$')
		end
		if n and item and item ~= '' then
			return tonumber(n), (item:gsub('%s+$', ''))
		end
		return nil
	end
	local function itemCount(item)
		local d = data()
		local key = norm(item)
		local n = 0
		for k, v in pairs(d and d.Inventory or {}) do
			if type(v) == 'number' and norm(k) == key then
				n += v
			end
		end
		for _, it in ipairs(d and d.Inventory and d.Inventory.Misc or {}) do
			local nk = norm(it.Name)
			if nk == key or (nk:sub(1, #key) == key and nk:sub(#key + 1):match('^%d*$')) then
				n += tonumber(it.Quantity) or 1
			end
		end
		return n
	end
	local function oreKey(item)
		local key = norm(item)
		for name in pairs(ORE_NAMES) do
			if norm(name) == key then
				return name
			end
		end
		return nil
	end
	local function shopKey(item)
		local key = norm(item)
		local best, bestPrice
		for name, info in pairs(ShopData or {}) do
			local nk = norm(name)
			if nk == key or (nk:sub(1, #key) == key and nk:sub(#key + 1):match('^%d*$')) then
				if not bestPrice or (info.Price or 0) < bestPrice then
					best, bestPrice = name, info.Price or 0
				end
			end
		end
		return best
	end
	-- Returns true if it did something.
	local function deliverItem(questId, q, desc)
		local n, item = parseBring(desc)
		if not n then
			return false
		end
		local ore = oreKey(item)
		if ore then
			G.FTReserve[ore] = math.max(G.FTReserve[ore] or 0, n)
		end
		if itemCount(item) >= n then
			-- (v290: "Line's Needs" names its NPC "Link" but the NPC is "Line": fall back to the
			-- name after "to" in the objective text.)
			local who = q.Npc
			local toName = tostring(desc):match("%s[Tt]o%s+([%w%s'%-]-)%.?%s*$")
			if (not who or not npcModel(who)) and toName and npcModel(toName) then
				who = toName
			end
			return who and visit(who, 'deliver') or false
		end
		local sk = shopKey(item)
		if sk and settings.questBuy then
			return buy(sk, n - itemCount(item))
		end
		if ore then
			QS.wantMine = true -- keep mining; this ore may only drop on another island
		end
		return false
	end

	local function claimBoard()
		local d = data()
		local qb = d and d.QuestBoard
		if type(qb) ~= 'table' then
			return
		end
		local QBS = service('QuestBoardService')
		for _, tier in ipairs({ 'Daily', 'Weekly', 'Monthly' }) do
			for i, q in ipairs(type(qb[tier]) == 'table' and qb[tier].Quests or {}) do
				if not q.Claimed and (tonumber(q.Progress) or 0) >= (tonumber(q.Goal) or math.huge) then
					pcall(function()
						QBS:ClaimQuest(tier, i)
					end)
					setStatus(('claimed %s quest %s'):format(tier, tostring(q.Id)))
					task.wait(0.5)
				end
			end
		end
	end

	local skipped = {}
	local turnInAt = {}
	local lastAcceptScan, lastBoard = 0, 0
	-- What a quest objective needs, and whether that is on THIS island. (Measured: it locked onto a
	-- quest for Elite Orcs - another island's mob - and spent its 6 minutes killing whatever ape was
	-- nearest "for the quest"; and for "collect Water Stone" it mined any rock at all, though only
	-- the bamboo rocks give that ore.)
	local Here = { rockSeen = {}, rockAt = -1e9, src = {} }
	function Here.rocks()
		if os.clock() - Here.rockAt > 15 then
			Here.rockAt = os.clock()
			local rocks = workspace:FindFirstChild('Rocks')
			for _, zone in ipairs(rocks and rocks:GetChildren() or {}) do
				for _, sp in ipairs(zone:GetChildren()) do
					local m = sp:FindFirstChildWhichIsA('Model')
					if m then
						Here.rockSeen[m.Name] = os.clock()
					end
				end
			end
		end
		return Here.rockSeen
	end
	function Here.rock(name)
		local t = Here.rocks()[name]
		return t ~= nil and os.clock() - t < 900
	end
	-- rocks whose drop list (the game's Rock data) has this ore
	function Here.sources(ore)
		if Here.src[ore] == nil then
			local out = {}
			pcall(function()
				for name, def in pairs(require(RS.Shared.Data.Rock)) do
					if type(def) == 'table' and type(def.Ores) == 'table' and table.find(def.Ores, ore) then
						out[name] = true
					end
				end
			end)
			Here.src[ore] = out
		end
		return Here.src[ore]
	end
	function Here.mob(target)
		local lv = workspace:FindFirstChild('Living')
		for _, m in ipairs(lv and lv:GetChildren() or {}) do
			if m:GetAttribute('IsNpc') and (mobNoRoute[m] or 0) < os.clock() and not mobIgnored(m)
				and (target == nil or mobMatches((string.gsub(m.Name, '%d+$', '')), target)) then
				return true
			end
		end
		return false
	end
	function Here.specificMob(target)
		return target ~= 'Any' and target ~= 'Mob' and target ~= 'AnyBoss' and string.sub(target, 1, 9) ~= 'Mutation:'
	end
	-- can this objective be worked on from here?
	function Here.can(p)
		local t, target = p.questType, tostring(p.target)
		if t == 'Kill' then
			return Here.mob(Here.specificMob(target) and target or nil)
		elseif t == 'Mine' then
			-- (a rock the pickaxe cannot hurt - Hana Pebble needs 777 base damage - is not work we can do)
			return target == 'Any' or target == 'Rock' or (Here.rock(target) and not tooStrong[target])
		elseif t == 'Collect' and target ~= 'Ore' and not (ShopData and ShopData[target]) then
			local src = Here.sources(target)
			if next(src) == nil then
				return true -- (no rock lists it: unknown, the old behaviour)
			end
			for name in pairs(src) do
				if Here.rock(name) and not tooStrong[name] then
					return true
				end
			end
			return false
		end
		return true
	end
	function Here.quest(qd)
		if type(qd) ~= 'table' then
			return false
		end
		for _, p in ipairs(qd.Progress or {}) do
			if (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 1) and Here.can(p) then
				return true
			end
		end
		return false
	end
	-- One quest at a time: the bot locks onto a quest and works only on that one until it is
	-- finished and turned in. It lets go only when the quest gives it nothing to do, or when
	-- 6 minutes pass without any progress on it (then that quest rests for 10 minutes).
	local lockId, lockAt, lockSig
	local stalled = {}
	local function progSig(qd)
		local p = {}
		for _, x in ipairs(type(qd) == 'table' and qd.Progress or {}) do
			p[#p + 1] = tostring(x.currentProgress)
		end
		return table.concat(p, ',')
	end

	-- One quest action per call. Returns true if it did something.
	function Quest.step()
		QS.wantMobs, QS.wantMine, QS.mobTarget = false, false, nil
		QS.storyMobs, QS.storyMine = false, false
		G.FTQuestRock = nil
		G.FTQuestRocks = nil
		G.FTCamp = nil
		-- (v245) a drop still wanted (G.FTDropNeed) whose mob is dead right now: wait where it lives,
		-- like a quest kill - it used to wander off to whatever else was alive (the apes)
		do
			local dn, d0 = G.FTDropNeed, data()
			local inv0 = d0 and d0.Inventory or {}
			local lv0 = workspace:FindFirstChild('Living')
			for _, e in ipairs(type(dn) == 'table' and dn or {}) do
				if type(e) == 'table' and type(e.mob) == 'string' and (tonumber(inv0[e.ore]) or 0) < (tonumber(e.n) or 0) then
					local up = false
					for _, m in ipairs(lv0 and lv0:GetChildren() or {}) do
						if m:GetAttribute('IsNpc') and string.sub(m.Name, 1, #e.mob) == e.mob then
							local h = m:FindFirstChildOfClass('Humanoid')
							local r0 = mobRoot(m)
							if h and h.Health > 0 and r0 then
								up = true
								G.FTMobSeen = G.FTMobSeen or {}
								G.FTMobSeen[e.mob] = r0.Position
							end
						end
					end
					local at = (G.FTMobSeen and G.FTMobSeen[e.mob]) or e.at
					if not up and typeof(at) == 'Vector3' then
						G.FTCamp = at
						G.FTCampFor = e.mob
					end
					if up then
						-- (v272: a wanted drop's mob is alive - fight it, also with "Auto mobs" off)
						QS.wantMobs = true
						QS.mobTarget = e.mob
						G.FTDropFight = (G.FTDropFight or 0) + 1
						return false
					end
					break
				end
			end
		end
		G.FTReserve = {}
		local d = data()
		if not d then
			return false
		end
		if settings.claimBoard and os.clock() - lastBoard > 30 then
			lastBoard = os.clock()
			claimBoard()
		end
		if settings.autoCompleteQuests then
			-- One-time (story / NPC) quests first, repeatable ones last.
			local order = {}
			for id in pairs(d.Quests or {}) do
				order[#order + 1] = id
			end
			-- The focused quest was handed in and the same NPC gave the next one of the chain
			-- (ShogunQuest4 -> ShogunQuest5): the focus moves along with it. (measured: focus stayed on
			-- the finished quest = Auto, which went mining for another quest instead of the new one)
			if settings.focusQuest ~= 'Auto' and d.Quests[settings.focusQuest] == nil then
				local stem, num = string.match(settings.focusQuest, '^(.-)(%d+)$')
				local nextId, nextNum
				for id in pairs(d.Quests) do
					local s2, n2 = string.match(id, '^(.-)(%d+)$')
					if stem and s2 == stem and tonumber(n2) > tonumber(num) and (not nextNum or tonumber(n2) < nextNum) then
						nextId, nextNum = id, tonumber(n2)
					end
				end
				if nextId then
					statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('focus quest moved on: %s -> %s'):format(settings.focusQuest, nextId)
					settings.focusQuest = nextId
					pcall(save)
				end
			end
			local focusId = settings.focusQuest ~= 'Auto' and d.Quests[settings.focusQuest] ~= nil and settings.focusQuest or nil
			-- (a rock kind a quest has already counted as mined is one the pickaxe can break)
			for _, qd0 in pairs(d.Quests) do
				for _, p in ipairs(type(qd0) == 'table' and qd0.Progress or {}) do
					if p.questType == 'Mine' and (tonumber(p.currentProgress) or 0) > 0 then
						canBreak[tostring(p.target)] = true
						tooStrong[tostring(p.target)] = nil
					end
				end
			end
			local hereQ, fracQ, mineQ = {}, {}, {}
			for _, id in ipairs(order) do
				hereQ[id] = Here.quest(d.Quests[id])
				mineQ[id] = false
				for _, p in ipairs(type(d.Quests[id]) == 'table' and d.Quests[id].Progress or {}) do
					if (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 1)
						and (p.questType == 'Mine' or (p.questType == 'Collect' and not (ShopData and ShopData[tostring(p.target)]))) and Here.can(p) then
						mineQ[id] = true
					end
				end
				local sum, n = 0, 0
				for _, p in ipairs(type(d.Quests[id]) == 'table' and d.Quests[id].Progress or {}) do
					n += 1
					sum += math.clamp((tonumber(p.currentProgress) or 0) / math.max(tonumber(p.requiredAmount) or 1, 1), 0, 1)
				end
				fracQ[id] = n > 0 and math.floor(sum / n * 1000 + 0.5) or 0
			end
			table.sort(order, function(a, b)
				-- The quest you picked in "Focus quest" goes first.
				if focusId and (a == focusId) ~= (b == focusId) then
					return a == focusId
				end
				-- finished ones next: just a turn-in
				local da = type(d.Quests[a]) == 'table' and questDone(d.Quests[a])
				local db = type(d.Quests[b]) == 'table' and questDone(d.Quests[b])
				if da ~= db then
					return da
				end
				-- then the ones with something to do on this island
				local ha, hb = hereQ[a], hereQ[b]
				if ha ~= hb then
					return ha
				end
				-- NPC / story quests before the daily and weekly board ones
				local ba = string.find(tostring(a), '^Daily') ~= nil or string.find(tostring(a), '^Weekly') ~= nil
				local bb = string.find(tostring(b), '^Daily') ~= nil or string.find(tostring(b), '^Weekly') ~= nil
				if ba ~= bb then
					return bb
				end
				local ra = QuestData and QuestData[a] and QuestData[a].Repeatable and 1 or 0
				local rb = QuestData and QuestData[b] and QuestData[b].Repeatable and 1 or 0
				if ra ~= rb then
					return ra < rb
				end
				-- mining ones before fighting ones (rocks are always reachable; mob packs often are not)
				if mineQ[a] ~= mineQ[b] then
					return mineQ[a]
				end
				-- the one closest to finished first
				if fracQ[a] ~= fracQ[b] then
					return fracQ[a] > fracQ[b]
				end
				return tostring(a) < tostring(b)
			end)
			local nowQ = os.clock()
			-- (v290, asked: where do Warrior Skulls come from. SilasIsland3Quest1 wants 2 glowing skulls
			-- lying in Frostspire Expanse on Island 3 - pickups, not drops - and the bot sat on it for half
			-- an hour on Island 2 mining Basalt. A quest whose unfinished objective is ground pickups that
			-- are not in this server is set aside for 10 minutes so the next one is worked on.)
			do
				local PK = G.FTPickupGone
				if type(PK) ~= 'table' or nowQ - PK.at > 30 then
					PK = { at = nowQ, gone = {} }
					G.FTPickupGone = PK
					for id, qd in pairs(d.Quests) do
						local def = QuestData and QuestData[id]
						for i, ob in ipairs(type(def) == 'table' and type(def.Objectives) == 'table' and def.Objectives or {}) do
							local pr = type(qd) == 'table' and type(qd.Progress) == 'table' and qd.Progress[i]
							local left = not pr or (tonumber(pr.currentProgress) or 0) < (tonumber(pr.requiredAmount) or 1)
							if left and type(ob) == 'table' and type(ob.Pickups) == 'table' and #ob.Pickups > 0 then
								local here = false
								for _, pk in ipairs(ob.Pickups) do
									if type(pk) == 'table' and pk.Name and workspace:FindFirstChild(pk.Name, true) then
										here = true
									end
								end
								if not here then
									PK.gone[id] = tostring(ob.Area or ('island ' .. tostring(ob.Island)))
								end
							end
						end
					end
				end
				for id, area in pairs(PK.gone) do
					if (stalled[id] or 0) < nowQ then
						stalled[id] = nowQ + 600
						if lockId == id then
							setStatus(('quest %s: its items lie in %s, not here — doing another one'):format(tostring(id), area))
							lockId = nil
						end
					end
				end
			end
			if lockId and d.Quests[lockId] == nil then
				setStatus('quest finished: ' .. tostring(lockId))
				lockId = nil
			end
			if lockId and focusId and lockId ~= focusId and (stalled[focusId] or 0) < nowQ then
				lockId = nil -- you picked another quest in "Focus quest"
			end
			if lockId then
				local sig = progSig(d.Quests[lockId])
				if sig ~= lockSig then
					lockSig, lockAt = sig, nowQ
				else
					-- (measured: the quest picked under "Focus quest" - 3 Fruite, a rare drop from Hana
					-- Pebbles - was dropped after 6 minutes without one, for a kill quest. The focused
					-- quest is never dropped for slow progress, and one waiting on an ore drop gets
					-- 30 minutes.)
					local waitsOnOre = false
					for _, p in ipairs(type(d.Quests[lockId]) == 'table' and d.Quests[lockId].Progress or {}) do
						if p.questType == 'Collect' and (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 1) then
							waitsOnOre = true
						end
					end
					if lockId ~= focusId and nowQ - lockAt > (waitsOnOre and 1800 or 360) then
						stalled[lockId] = nowQ + 600
						setStatus(('quest %s: no progress for %d min — trying another one for a while'):format(tostring(lockId), waitsOnOre and 30 or 6))
						lockId = nil
					end
				end
			end
			-- (a quest with nothing to do right now is set aside and the next one tried in the same
			-- pass: one per pass, with a walk to a quest giver in between each, took minutes to get
			-- through a full quest log)
			for _ = 1, math.max(1, #order) do
			if not lockId then
				for _, id in ipairs(order) do
					if (stalled[id] or 0) < nowQ then
						lockId, lockAt, lockSig = id, nowQ, progSig(d.Quests[id])
						setStatus('working on quest: ' .. tostring(id))
						break
					end
				end
			end
			G.FTQuestLock = lockId
			if not lockId then
				break
			end
			local engaged = false
			for _, id in ipairs(order) do
				if id ~= lockId then
					continue
				end
				local qd = d.Quests[id]
				local q = QuestData and QuestData[id] or {}
				if type(qd) == 'table' and questDone(qd) then
					engaged = true -- waiting for its turn-in
				end
				-- Priority quest: the focused one, or (no focus) any one-time quest.
				local pri = (focusId ~= nil and id == focusId) or (focusId == nil and not q.Repeatable)
				if type(qd) == 'table' and questDone(qd) and q.AutoComplete ~= true
					and os.clock() - (turnInAt[id] or 0) > 30 then
					turnInAt[id] = os.clock()
					if visit(q.Npc or id, 'turn in') then
						return true
					end
				end
				for pi, p in ipairs(type(qd) == 'table' and qd.Progress or {}) do
					local cur, req = tonumber(p.currentProgress) or 0, tonumber(p.requiredAmount) or 1
					if cur < req then
						local t, target = p.questType, tostring(p.target)
						if (t == 'Kill' or t == 'Mine' or t == 'Collect') and not Here.can(p) then
							-- (its mob / rock is not on this island: nothing to do for it from here)
							-- ...unless it is the focused quest and we know where its mobs live: wait there,
							-- mining what is around, and they are picked up the moment they respawn.
							local isFocusKill = t == 'Kill' and settings.focusQuest ~= 'Auto' and lockId == settings.focusQuest
							local seenAt = isFocusKill and G.FTMobSeen and G.FTMobSeen[target] or nil
							if isFocusKill and not seenAt then
								-- never seen alive this session: its relatives (same last word: "... Oni") show the area
								local fam = string.match(target, '(%a+)$')
								local lv0 = workspace:FindFirstChild('Living')
								local sum, n = Vector3.zero, 0
								for _, m in ipairs(fam and lv0 and lv0:GetChildren() or {}) do
									if m:GetAttribute('IsNpc') and string.match((string.gsub(m.Name, '%d+$', '')), '(%a+)$') == fam then
										local r0 = mobRoot(m)
										if r0 then
											sum += r0.Position
											n += 1
										end
									end
								end
								if n > 0 then
									seenAt = sum / n
								end
							end
							if seenAt and not G.FTCamp then
								G.FTCamp = seenAt
								G.FTCampFor = target
								engaged = true
								-- (v186, a test the user asked for: no Frostburn Oni anywhere for 10+ minutes while
								-- 11 Brute Onis stood there. If the kinds share spawn places, killing the quest's
								-- other, already finished, mob makes room. So: fight that one while waiting.)
								local kin
								for _, p2 in ipairs(qd.Progress) do
									local t2 = tostring(p2.target)
									if p2 ~= p and p2.questType == 'Kill' and Here.specificMob(t2) and Here.mob(t2) then
										kin = t2
										break
									end
								end
								G.FTCampKill = kin
								if kin and not QS.mobTarget then
									QS.wantMobs = true
									QS.mobTarget = kin
								else
									QS.wantMine = true
								end
							end
						elseif t == 'Kill' then
							QS.wantMobs = true
							engaged = true
							-- (remember where this kind lives, for the wait while they are all dead)
							if Here.specificMob(target) then
								local lv0 = workspace:FindFirstChild('Living')
								for _, m in ipairs(lv0 and lv0:GetChildren() or {}) do
									if m:GetAttribute('IsNpc') and mobMatches((string.gsub(m.Name, '%d+$', '')), target) then
										local r0 = mobRoot(m)
										if r0 then
											G.FTMobSeen = G.FTMobSeen or {}
											G.FTMobSeen[target] = r0.Position
											break
										end
									end
								end
							end
							if pri then
								QS.storyMobs = true
							end
							-- Only aim at a specific mob if one with that name is actually around.
							if not QS.mobTarget and target ~= 'Any' and target ~= 'Mob' then
								local lv = workspace:FindFirstChild('Living')
								for _, m in ipairs(lv and lv:GetChildren() or {}) do
									if m:GetAttribute('IsNpc') and mobMatches((string.gsub(m.Name, '%d+$', '')), target) then
										QS.mobTarget = target
										break
									end
								end
							end
						elseif t == 'Mine' or (t == 'Collect' and (target == 'Ore' or not (ShopData and ShopData[target]))) then
							-- (v280, reported with a screenshot: "mining the wrong rocks". The quest it had picked
							-- wanted Light Crystal, whose only rock here is in the shut Goblin Cave - so no rock of
							-- that kind was on the list and it mined whatever was nearest instead. A part whose rock
							-- is not standing anywhere the bot may go is now "nothing to do right now": the quest
							-- is set aside for a few minutes and the next one is worked on.)
							local kinds
							if t == 'Mine' and target ~= 'Any' and target ~= 'Rock' then
								kinds = { [target] = true }
							elseif t == 'Collect' and target ~= 'Ore' and next(Here.sources(target)) then
								kinds = Here.sources(target)
							end
							local standing = true
							if kinds then
								local RA = G.FTRockAvail
								if type(RA) ~= 'table' or os.clock() - RA.at > 3 then
									RA = { at = os.clock(), has = {} }
									G.FTRockAvail = RA
									local rocksF = workspace:FindFirstChild('Rocks')
									for _, zone in ipairs(rocksF and rocksF:GetChildren() or {}) do
										local shut = (zone.Name == 'Island2GoblinCave' or string.find(zone.Name, 'Closed', 1, true) ~= nil) and not (type(G.FTZoneOpen) == 'table' and G.FTZoneOpen[zone.Name]) and settings.mineZone ~= zone.Name
										if not shut then
											for _, dsc in ipairs(zone:GetDescendants()) do
												if dsc:IsA('Model') and (tonumber(dsc:GetAttribute('Health')) or 0) > 0 then
													RA.has[dsc.Name] = true
												end
											end
										end
									end
								end
								standing = false
								for name in pairs(kinds) do
									if RA.has[name] and not tooStrong[name] then
										standing = true
									end
								end
							end
							if standing then
							QS.wantMine = true
							engaged = true
							if t == 'Mine' and target ~= 'Any' and target ~= 'Rock' then
								G.FTQuestRock = G.FTQuestRock or target
							elseif t == 'Collect' and target ~= 'Ore' and next(Here.sources(target)) then
								-- an ore: mine the rocks that drop it
								G.FTQuestRocks = G.FTQuestRocks or {}
								for name in pairs(Here.sources(target)) do
									G.FTQuestRocks[name] = true
								end
							end
							if pri then
								QS.storyMine = true
							end
							else
								G.FTRockNone = (G.FTRockNone or 0) + 1
							end
						elseif t == 'Collect' and ShopData and ShopData[target] then
							if settings.questBuy and buy(target) then
								return true
							end
						elseif t == 'Talk' then
							if visit(target, 'talk') then
								return true
							end
						elseif t == 'Sell' then
							if target == 'Ore' or target == 'Ores' then
								if sellOres() then
									return true
								end
							elseif sellSpare(target) then
								return true
							end
						elseif t == 'Equip' or t == 'EquipWeapon' then
							if target == 'Pickaxe' then
								equipBestPickaxe()
							else
								autoEquipBest(true)
							end
						elseif t == 'Extra' then
							local desc = q.Objectives and q.Objectives[pi] and q.Objectives[pi].Description
							-- (v265, asked for: "Breaking the Spirit Seals - 3". Each seal is a model in workspace named
							-- like the step's target (SpiritSeal1..3), with a rock-style health bar and no prompt: it is
							-- hit until it breaks. Go stand beside it and swing - pickaxe first, weapon if the bar does
							-- not move - and write down what the bar did.)
							local sealM = type(target) == 'string' and string.match(target, '^SpiritSeal%d+$') and workspace:FindFirstChild(target)
							local sealP = sealM and (sealM:FindFirstChild('Spirit Seal') or sealM:FindFirstChildWhichIsA('BasePart', true))
							if sealP then
								local function barText()
									local l = sealP:FindFirstChild('rockHP', true)
									return l and l:IsA('TextLabel') and l.Text or '?'
								end
								local function stepDone()
									local p2 = qd.Progress and qd.Progress[pi]
									return (p2 and (tonumber(p2.currentProgress) or 0) >= (tonumber(p2.requiredAmount) or 1)) or not sealP.Parent
								end
								G.FTSealLog = G.FTSealLog or {}
								local function note(msg)
									local line = os.date('%H:%M:%S ') .. target .. ': ' .. msg
									statusLog[#statusLog + 1] = line
									if #G.FTSealLog < 60 then
										G.FTSealLog[#G.FTSealLog + 1] = line
									end
								end
								local _, hS = char()
								if not hS then
									return true
								end
								local base = Vector3.new(sealP.Position.X, sealP.Position.Y - sealP.Size.Y / 2 + 3, sealP.Position.Z)
							-- (v266, seen live: the pickaxe took Seal I from 60,000 to 29,749 in 34 s, then a Spirit Golem
							-- guarding it shot us off the spot every few seconds and nothing more landed. Whatever is
							-- within 80 studs of the seal is killed first.)
							local function guard()
								local nG, lG = mobsNear(base, 80)
								return nG > 0 and lG[1] or nil
							end
							local gd = (hS.Position - base).Magnitude < 150 and guard()
							if gd then
								setStatus(('clearing %s away from %s'):format(gd.m.Name, target))
								fightOnce(gd)
								return true
							end
								if (hS.Position - base).Magnitude > 9 then
									setStatus('going to ' .. target)
									local dir = (hS.Position - base) * Vector3.new(1, 0, 1)
									dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
									if not tweenTo(CFrame.new(base + dir * 5)) then
										note('could not get there')
										task.wait(3)
										return true
									end
								end
								for _, toolName in ipairs({ 'Pickaxe', 'Weapon' }) do
									local tool = equip(toolName)
									local b0, t0, moved = barText(), os.clock(), false
									while alive and tool and not stepDone() and os.clock() - t0 < (moved and 90 or 10) do
										local _, hh = char()
										if not hh then
											break
										end
										if (hh.Position - base).Magnitude > 9 or guard() then
											break
										end
										hh.CFrame = CFrame.lookAt(hh.Position, Vector3.new(sealP.Position.X, hh.Position.Y, sealP.Position.Z))
										setStatus(('breaking %s with the %s (%s)'):format(target, toolName, barText()))
										swing(tool)
										task.wait(0.35)
										if barText() ~= b0 then
											moved = true
										end
									end
									note(('%s: bar %s -> %s, step done %s'):format(toolName, b0, barText(), tostring(stepDone())))
									if stepDone() or moved then
										break
									end
								end
								task.wait(0.5)
								return true
							end
							-- (v229, measured on "Cleansing the Holy Tree - 1": its last step "Return to the Shogun's
							-- Spirit" is marked TurnInOnly. The bot walked to him for it while the kills were still
							-- short, got nothing, and was then backing off when the kills were finally done.
							-- Such a step is only tried once every other step is complete.)
							local odef = q.Objectives and q.Objectives[pi]
							local handIn = type(odef) == 'table' and odef.TurnInOnly == true
							local restDone = true
							for pj, p2 in ipairs(qd.Progress or {}) do
								if pj ~= pi and (tonumber(p2.currentProgress) or 0) < (tonumber(p2.requiredAmount) or 1) then
									restDone = false
								end
							end
							local bring = type(odef) == "table" and type(odef.Bring) == "table" and odef.Bring or nil
							if bring then
								-- (v247: "Bring 12 Oni Mask and 5 Yin-Yang to the Shogun's Spirit" - two items in one
								-- sentence was read as one item named "Oni Mask and 5 Yin-Yang", so it never went.
								-- The step carries the list itself: go once everything on it is held.)
								local have = true
								for item, n in pairs(bring) do
									local ore = oreKey(item)
									if ore then
										G.FTReserve[ore] = math.max(G.FTReserve[ore] or 0, tonumber(n) or 0)
									end
									if itemCount(item) < (tonumber(n) or 1) then
										have = false
									end
								end
								if have and restDone and os.clock() - (turnInAt[id] or 0) > 30 then
									turnInAt[id] = os.clock()
									if visit(target, "deliver") then
										return true
									end
								end
							elseif handIn then
								if restDone and os.clock() - (turnInAt[id] or 0) > 30 then
									turnInAt[id] = os.clock()
									if visit(target, 'hand in') then
										return true
									end
								end
							elseif target == 'None' or parseBring(desc) then
								if deliverItem(id, q, desc) then
									return true
								end
							elseif extraFetch(target) then
								return true
							end
						elseif t == 'UI' then
							-- "Open the map" style steps: tell the server, in order.
							pcall(function()
								service('QuestService'):ProgressUIQuest(id, pi)
							end)
							task.wait(0.3)
						elseif t == 'Enhance' then
							local lvl = 3
							pcall(function()
								for _, o in ipairs(q.Objectives or {}) do
									if o.Type == 'Enhance' then
										lvl = tonumber(tostring(o.Description):match('%+(%d+)')) or lvl
									end
								end
							end)
							if enhanceTo(lvl) then
								return true
							end
						elseif t == 'RuneAttach' then
							if attachRune() then
								return true
							end
						elseif t == 'Forge' then
							engaged = true -- (auto forge makes it)
						elseif not skipped[t] then
							skipped[t] = true
							warn(('[ForgeTools] quest objective "%s" (%s) is not automated yet'):format(t, target))
						end
					end
				end
			end
			if lockId and not engaged then
				-- nothing the bot can do for this one right now: next quest, come back in 5 min
				-- (the quest the user focused is only waiting for its mobs to respawn: look again in 15 s)
				stalled[lockId] = os.clock() + ((settings.focusQuest ~= 'Auto' and lockId == settings.focusQuest) and 15 or 300)
				lockId = nil
			end
			if lockId then
				break
			end
			end
			G.FTQuestLock = lockId
		end
		-- A quest that needs ore: don't sit on a 10,000 HP Lucky Block.
		G.FTQuestWantsOre = QS.wantMine or craftWant()
		-- (new quests are only looked for when there is no quest left to work on)
		-- (v215: with quests still to work on, an NPC is visited all the same when the game's quest
		-- data says it hands out a quest we do not have yet - e.g. Hayato = "Shogun'sGuard" - but each
		-- such NPC only once every 10 minutes.)
		local busy = lockId ~= nil
		local givers = {}
		if busy and settings.autoAcceptQuests and os.clock() - lastAcceptScan > 20 then
			for qid, q in pairs(QuestData or {}) do
				if type(q) == 'table' and type(q.Npc) == 'string' and eligible(qid) then
					givers[q.Npc] = true
				end
			end
		end
		if settings.autoAcceptQuests and os.clock() - lastAcceptScan > 20 then
			lastAcceptScan = os.clock()
			local prox = workspace:FindFirstChild('Proximity')
			-- (v228, the user at Shogun's Spirit: "it keeps coming here to talk to this ... even though i
			-- have his quest already". A quest giver that handed over nothing on two visits in a row is
			-- left alone until some quest gets completed (which is what can unlock a new one).
			local fruit = type(G.FTFruitless) == 'table' and G.FTFruitless or {}
			G.FTFruitless = fruit
			local function tally(t)
				local n = 0
				for _ in pairs(type(t) == 'table' and t or {}) do
					n += 1
				end
				return n
			end
			do
				local d0 = data()
				local cq = tally(d0 and d0.CompletedQuests)
				if G.FTFruitCQ ~= cq then
					G.FTFruitCQ = cq
					table.clear(fruit)
				end
			end
			for _, npc in ipairs(prox and prox:GetChildren() or {}) do
				local isTalker = DialogueNpcs and (DialogueNpcs[npc.Name] or false)
				-- Only scout NPCs reasonably close (some sit thousands of studs away in side areas).
				local near = false
				pcall(function()
					local _, hrp = char()
					near = hrp and (npc:GetPivot().Position - hrp.Position).Magnitude <= (tonumber(settings.questRange) or 1000)
				end)
				if busy and not (givers[npc.Name] and (not visited[npc.Name] or os.clock() - visited[npc.Name] > 600)) then
					near = false
				end
				if isTalker and near and npc:IsA('Model') then
					local tree = treeOf[npc.Name]
					local want = false
					if busy then
						want = true
					elseif not tree then
						want = not visited[npc.Name] or os.clock() - visited[npc.Name] > 900
					else
						for _, g in ipairs(treeCommands(tree).give) do
							if g.quest and eligible(g.quest) then
								want = true
							end
						end
						want = want and (not visited[npc.Name] or os.clock() - visited[npc.Name] > 60)
					end
					if want and not craftWant() and (fruit[npc.Name] or 0) < 2 then -- (v224: ores for a craft first, quest givers after)
						local d1 = data()
						local had = tally(d1 and d1.Quests)
						if visit(npc.Name, 'looking for quests') then
							task.wait(1)
							local d2 = data()
							if tally(d2 and d2.Quests) > had then
								fruit[npc.Name] = 0
							else
								fruit[npc.Name] = (fruit[npc.Name] or 0) + 1
								if fruit[npc.Name] == 2 then
									statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('quest giver %s gave nothing twice — leaving it alone until a quest is completed'):format(npc.Name)
								end
							end
							return true
						end
					end
				end
			end
		end
		return false
	end
end

---------------------------------------------------------------------------
-- Rewards: mail, codes, daily login, level + index rewards
---------------------------------------------------------------------------
local Rewards = {}
do
	-- Known working codes (Nov 2026). Add more in PlayerTools/forgecodes.txt, one per line.
	local CODES = { 'AIDASAYSSORRY', 'SORRYFORSHUTDOWNN!', 'TWILIGHTWAR', 'FORGECOMEBACK', 'CRIMSONSAKURA' }
	local triedPath = 'PlayerTools/forgecodes_tried_' .. string.lower(LocalPlayer.Name):gsub('[^%w_]', '') .. '.txt'
	local tried = {} -- [code] = os.time() of the last attempt (0 = from before times were kept)
	pcall(function()
		if isfile(triedPath) then
			for line in readfile(triedPath):gmatch('[^\r\n]+') do
				local c, t = line:match('^(.-)\t(%d+)$')
				tried[c or line] = tonumber(t) or 0
			end
		end
	end)
	-- The game does not tell the client which codes exist, so the working ones are read from a
	-- tracker page every 15 minutes (each is shown there in a <code> tag). A tracker can be hours
	-- behind the game's Discord: brand new codes still go in forgecodes.txt by hand.
	local online, onlineAt = {}, -1e9
	local ONLINE_URL = 'https://www.theforge.gg/codes'
	local function fetchOnline()
		if os.clock() - onlineAt < 900 then
			return
		end
		onlineAt = os.clock()
		local okh, body = pcall(function()
			return game:HttpGet(ONLINE_URL)
		end)
		if not okh or type(body) ~= 'string' then
			G.FTCodesOnline = 'fetch failed: ' .. tostring(body):sub(1, 80)
			return
		end
		local found, n = {}, 0
		for c in body:gmatch('<code[^>]*>([^<]+)</code>') do
			c = c:gsub('&amp;', '&'):gsub('^%s+', ''):gsub('%s+$', '')
			if #c >= 4 and #c <= 32 and c:match('^[%w!_%-%.]+$') and c:match('%u') and not found[c] then
				found[c] = true
				n += 1
			end
		end
		if n > 0 then
			online = found
		end
		local names = {}
		for c in pairs(online) do
			names[#names + 1] = c
		end
		table.sort(names)
		G.FTCodesOnline = ('%d listed: %s'):format(n, table.concat(names, ', '))
	end
	local function codeList()
		local list, seen = {}, {}
		local function add(c)
			c = tostring(c):gsub('^%s+', ''):gsub('%s+$', '')
			if c ~= '' and not seen[c] then
				seen[c] = true
				list[#list + 1] = c
			end
		end
		for _, c in ipairs(CODES) do
			add(c)
		end
		for c in pairs(online) do
			add(c)
		end
		pcall(function()
			if isfile('PlayerTools/forgecodes.txt') then
				for line in readfile('PlayerTools/forgecodes.txt'):gmatch('[^\r\n]+') do
					if not line:match('^%s*%-%-') then
						add(line)
					end
				end
			end
		end)
		return list
	end

	local last = 0
	function Rewards.step()
		if os.clock() - last < 60 then
			return
		end
		last = os.clock()
		local d = data()
		if not d then
			return
		end
		if settings.autoMail then
			pcall(function()
				local ok, res = service('MailService'):ClaimAll():await()
				if ok and type(res) == 'table' and (res.Success or res.Claimed) then
					setStatus('claimed mail')
				end
			end)
			pcall(function()
				service('LevelRewardsService'):ClaimAll()
			end)
			pcall(function()
				service('CodexService'):ClaimAll()
			end)
			-- Seasonal event (Twilight War etc.): free quest / milestone / free-step rewards and the altar daily.
			for _, call in ipairs({
				{ 'SeasonalEventService', 'ClaimAll' },
				{ 'SeasonalEventService', 'ClaimAllMilestones' },
				{ 'SeasonalEventService', 'ClaimFreeStep' },
			}) do
				pcall(function()
					local svc = service(call[1])
					if svc and svc[call[2]] then
						svc[call[2]](svc)
					end
				end)
			end
		end
		-- Twilight altar: free daily gifts, then offer shards (x10 while possible, then x1).
		pcall(function()
			local Altar = require(RS.Shared.Data.TwilightAltar)
			local svc = service('TwilightAltarService')
			if settings.autoMail then
				for _, gift in ipairs(Altar.Daily and Altar.Daily.Order or {}) do
					pcall(function()
						svc:ClaimDaily(gift)
					end)
				end
			end
			if not settings.autoOffer then
				return
			end
			local tw = d.Events and d.Events.TwilightWar
			local pledge = tw and tw.Pledge
			if type(pledge) ~= 'string' or pledge == '' then
				return
			end
			local function shards()
				for _, it in ipairs(d.Inventory and d.Inventory.Misc or {}) do
					local n = tostring(it.Name)
					if n:find('Shard') and n:lower():find(pledge:lower(), 1, true) then
						return tonumber(it.Quantity) or 0
					end
				end
				return 0
			end
			local cost = tonumber(Altar.OfferCost) or 100
			local offers = Altar.Offers or { 1, 10 }
			local big, small = offers[2] or 10, offers[1] or 1
			for _ = 1, 50 do
				local have = shards()
				local n = (have >= cost * big and big) or (have >= cost * small and small) or nil
				if not n then
					break
				end
				local ok, res = pcall(function()
					return select(2, svc:Offer(n):await())
				end)
				setStatus(('offered %d at the altar (%d shards left)'):format(n, shards()))
				if not ok or not res then
					break
				end
				task.wait(1.5)
			end
		end)
		if settings.autoDaily then
			pcall(function()
				local Util = require(RS.Shared.Utils.DailyLoginUtil)
				for day = 1, 31 do
					local okc, can = pcall(Util.CanClaimReward, d.DailyLogin, day)
					if okc and can then
						service('DailyLoginService'):Claim(day)
						setStatus('claimed daily login day ' .. day)
						task.wait(0.5)
					end
				end
			end)
		end
		if settings.autoCodes then
			local redeemed = {}
			for k, v in pairs(d.RedeemedCodes or {}) do
				redeemed[type(k) == 'string' and k or tostring(v)] = true
			end
			pcall(fetchOnline)
			for _, code in ipairs(codeList()) do
				-- a code the tracker lists as working gets another go every 6 hours (a first try can
				-- fail on a rate limit or before the code is live)
				local again = online[code] and tried[code] and os.time() - tried[code] > 21600
				if (not tried[code] or again) and not redeemed[code] and not redeemed[code:upper()] then
					tried[code] = os.time()
					local okr, res = pcall(function()
						return select(2, service('CodeService'):RedeemCode(code):await())
					end)
					local msg = okr and type(res) == 'table' and tostring(res.Message or res.Success) or tostring(res)
					setStatus(('code %s: %s'):format(code, msg))
					print(('[ForgeTools] code %s -> %s'):format(code, msg))
					if msg:lower():find('too many') or msg:lower():find('wait') then
						tried[code] = nil -- rate limited: try again next round
						break
					end
					pcall(function()
						local lines = {}
						for c, t in pairs(tried) do
							lines[#lines + 1] = c .. '\t' .. tostring(tonumber(t) or 0)
						end
						writefile(triedPath, table.concat(lines, '\n') .. '\n')
					end)
					task.wait(3)
				end
			end
		end
	end
end


---------------------------------------------------------------------------
-- Abyss: walk into the Abyss cage, start the run, auto-pick cards and fight inside.
---------------------------------------------------------------------------
local Abyss = {}
do
	local A
	pcall(function()
		A = require(RS.Shared.Data.Abyss)
	end)
	-- Inside a run the place has no Abyss cage and the Abyss mode is on.
	-- In a run = not on any of the normal island places.
	local islandPlaces = {}
	pcall(function()
		for _, isl in ipairs(require(RS.Shared.Data.Islands).Data) do
			islandPlaces[isl.PlaceId] = true
		end
	end)
	function Abyss.inRun()
		if workspace:GetAttribute('AbyssRun') == true then
			return true
		end
		return next(islandPlaces) ~= nil and not islandPlaces[game.PlaceId]
	end

	-- Cards: score every offered card and pick the best one (12s to choose in game).
	--   Best overall: rarest, then damage. Damage / Survival: that kind first. Loot: reward cards.
	--   Cursed cards (Greed, Glass Cannon...) are skipped unless "Allow cursed cards" is on.
	local RANK = { Abyssal = 60, Fusion = 50, Epic = 40, Rare = 30, Common = 10, Cursed = 35 }
	local CURSE_RANK = {
		TunnelVision = 60, -- +15% crit chance, -15% move speed (barely matters standing in a fight)
		GlassCannon = 50, -- +50% damage, -25% max health
		DeepPact = 40, -- +80% damage, enemies 30% stronger
		Berserker = 30, -- +40% damage, -50% healing (halves the regen the armour is built on)
		Bloodlust = 20, -- +30% attack speed, take 15% more damage
		FragileFortune = 10, -- +60% crit damage, take 20% more damage
	}
	local function cardScore(card)
		if type(card) ~= 'table' then
			return -1
		end
		local text = string.lower(tostring(card.Text or ''))
		-- Never take a card with a downside (all Cursed cards, Deep Pact, anything with a Cost or
		-- that makes enemies stronger / you take more damage / lowers a stat).
		-- (v255, the user: Greed - enemies 30% stronger, floor rewards x2 - counts as a good card)
		-- (v257, the user: "take beneficial ones that arent fully maxed out". The game sends the deck
		-- with every pick; a card already held as many times as it allows is passed over.)
		local deck = G.FTAbyssDeck
		if type(deck) == 'table' and tonumber(card.Max) and (tonumber(deck[card.Id]) or 0) >= tonumber(card.Max) then
			return -900
		end
		local greed = card.Id == 'Greed'
		if greed then
			text = 'floor rewards x2'
		end
		if not greed and (card.Cost ~= nil or card.Enemy ~= nil or card.Rarity == 'Cursed'
			or text:find('more damage') or text:find('stronger') or text:find('%-%d')) then
			-- (v315, the user: "if theres 3 curses pick the least bad option, the one that doesnt reduce
			-- damage preferably". None of the game's downside cards lowers our damage; ranked by what the
			-- cost does to a bot that stands and fights on a regen build. Still below every good card.)
			return -1000 + (CURSE_RANK[card.Id] or 0)
		end
		local score = RANK[tostring(card.Rarity)] or 5
		if greed then
			return 1000 -- (v256, the user: "if the card is seen pick it")
		end
		local focus = settings.cardFocus
		local dmg = text:find('damage') and not text:find('less damage') and not text:find('more damage')
		local surv = text:find('health') or text:find('less damage') or text:find('heal') or text:find('survive')
		local loot = card.Loot ~= nil or text:find('reward')
		if focus == 'Damage' then
			score += dmg and 100 or 0
		elseif focus == 'Survival' then
			score += surv and 100 or 0
		elseif focus == 'Loot' then
			score += loot and 100 or 0
		else
			score += dmg and 5 or (surv and 4 or 0)
		end
		return score
	end
	Abyss.cardScore = cardScore
	local function pickFrom(offer)
		local best, bestScore
		for _, id in ipairs(offer.Cards) do
			local card = A and A.GetCard and A.GetCard(id)
			local sc = cardScore(card)
			if not bestScore or sc > bestScore then
				best, bestScore = id, sc
			end
		end
		return best, bestScore
	end
	local lastPicked
	pcall(function()
		if G.FTAbyssCardConn then
			G.FTAbyssCardConn:Disconnect()
		end
		if G.FTAbyssPickedConn then
			G.FTAbyssPickedConn:Disconnect()
		end
		local AS = service('AbyssService')
		G.FTAbyssPickedConn = AS.CardPicked:Connect(function(_, _, deck)
			lastPicked = os.clock()
			if type(deck) == 'table' then
				G.FTAbyssDeck = deck
			end
		end)
		-- (v314, a friend's report: "If there's 3 curses the script skips it too much, then proceed to go to
		-- the other floor without properly waiting for it, causing the lag". Before: every offer event ran
		-- its own handler at once (a reroll can send a fresh offer, so handlers stacked and rerolled /
		-- skipped over each other), every bad slot was rerolled even when a good card was already there,
		-- and the bot ran on to the next floor while the menu was still open. Now: one offer at a time,
		-- reroll only while there is nothing worth taking, wait for each answer, and the fight loop holds
		-- (G.FTAbyssCardBusy) until the pick or skip has gone through.)
		local busy, latest = false, nil
		local function handle(offer)
			local offeredAt = os.clock()
			G.FTAbyssCardBusy = offeredAt
			task.wait(1)
			if latest and latest ~= offer and type(latest.Cards) == 'table' then
				offer = latest -- (a newer offer came in while we waited: use that one)
			end
			local cards = table.clone(offer.Cards)
			local function scoreOf(id)
				return cardScore(A and A.GetCard and A.GetCard(id))
			end
			local best, bestScore = pickFrom({ Cards = cards })
			-- Reroll only while nothing is worth taking: the worst slot first, one call at a time.
			local rerolls = 0
			while best ~= nil and bestScore <= -800 and rerolls < 9 and os.clock() - offeredAt < 8 do
				local worst, ws
				for slot = 1, #cards do
					local sc = scoreOf(cards[slot])
					if (G.FTCardRerollsLeft and G.FTCardRerollsLeft[slot] == 0) then
						sc = 1e9 -- (this slot is out of rerolls)
					end
					if not ws or sc < ws then
						worst, ws = slot, sc
					end
				end
				if not worst or ws >= 1e9 then
					break
				end
				local ok, r1, r2, r3 = pcall(function()
					return AS:RerollCards(worst):await()
				end)
				local newId = ok and r1 and r2 and r3 or nil
				rerolls += 1
				if newId == nil then
					G.FTCardRerollsLeft = G.FTCardRerollsLeft or {}
					G.FTCardRerollsLeft[worst] = 0
				else
					cards[worst] = newId
				end
				best, bestScore = pickFrom({ Cards = cards })
				task.wait(0.4)
			end
			G.FTCardRerollsLeft = nil
			if best == nil then
				return
			end
			if bestScore <= -1000 and not (A and A.GetCard and A.GetCard(best) and CURSE_RANK[A.GetCard(best).Id]) then
				setStatus('abyss: only cards with downsides - skipping')
				local okS = pcall(function()
					AS:SkipCards():await()
				end)
				G.FTAbyssSkips = (G.FTAbyssSkips or 0) + 1
				-- (wait for the menu to really close before moving on: a skip answer can take a while
				-- on a slow connection)
				local ping = 0.2
				pcall(function()
					ping = LocalPlayer:GetNetworkPing()
				end)
				task.wait(math.clamp(1 + ping * 3, 1, 4))
				setStatus(okS and 'abyss: only cards with downsides - skipped' or 'abyss: skip failed')
				return
			end
			local card = A and A.GetCard and A.GetCard(best)
			-- Retry a few times in case the first call lands before the menu is ready.
			for _ = 1, 4 do
				pcall(function()
					AS:PickCard(best)
				end)
				local t1 = os.clock()
				while os.clock() - t1 < 1.5 and not (lastPicked and lastPicked >= offeredAt) do
					task.wait(0.1)
				end
				if lastPicked and lastPicked >= offeredAt then
					break
				end
			end
			setStatus('abyss: took ' .. tostring(card and card.Name or best))
		end
		G.FTAbyssCardConn = AS.CardOffer:Connect(function(offer)
			if not (settings.autoCards or settings.autoAbyss) or type(offer) ~= 'table' or type(offer.Cards) ~= 'table' then
				return
			end
			latest = offer
			if busy then
				return -- (one handler at a time; it picks up the newest offer)
			end
			busy = true
			task.spawn(function()
				pcall(handle, offer)
				busy = false
				G.FTAbyssCardBusy = nil
			end)
		end)
	end)

	local lastTry = 0
	-- Outside a run: go to the cage, open the lobby (makes your party) and start it.
	function Abyss.step()
		if not settings.autoAbyss or Abyss.inRun() or os.clock() - lastTry < 15 then
			return false
		end
		local prox = workspace:FindFirstChild('Proximity')
		local cage = prox and prox:FindFirstChild('AbyssCreateParty')
		if not cage then
			-- (v248: after dying in a run the game drops you on an island with no cage - seen on
			-- Island 1 - and the bot sat idle. The Events page "Abyss" button works from anywhere.)
			if os.clock() - lastTry < 40 then
				return false
			end
			lastTry = os.clock()
			setStatus('abyss: no cage here - teleporting to the Abyss lobby')
			local okE, rE, vE = pcall(function()
				return service('AbyssService'):Enter():await()
			end)
			G.FTAbyssEnter = { ok = okE, res = tostring(rE) .. ' ' .. tostring(vE), at = os.time() }
			if not (okE and rE and vE ~= false) then
				-- (v249, measured on Island 1: Enter answers false there - the Abyss opens from Island 2.
				-- Back to the furthest island that is unlocked, and in from there.)
				local dest
				pcall(function()
					local IM = require(RS.Shared.Data.Islands)
					for _, isl in ipairs(IM.Data or {}) do
						local okS, st = pcall(IM.GetRequirementStatus, isl.Name, data())
						if okS and type(st) == 'table' and st.AllMet then
							dest = isl.Name
						end
					end
				end)
				local d0 = data()
				if dest and d0 and d0.CurrentIsland ~= dest then
					setStatus('abyss: not open from this island - travelling to ' .. dest)
					local okT, aT, bT = pcall(function()
						return service('PortalService'):TeleportToIsland(dest):await()
					end)
					G.FTAbyssEnter.travel = dest .. ': ' .. tostring(okT) .. ' ' .. tostring(aT) .. ' ' .. tostring(bT)
				end
			end
			task.wait(8)
			return true
		end
		lastTry = os.clock()
		local ok, pos = pcall(function()
			return cage:GetPivot().Position
		end)
		if not ok then
			return false
		end
		local _, hrp = char()
		if hrp and (hrp.Position - pos).Magnitude > 250 then
			-- The cage is in the Abyss lobby far off the map: use the game's own teleport there
			-- (same as the Events page "Abyss" button), not a long walk.
			-- (v312, the user: "auto abyss still flying me over there, instead of using the teleport, it
			-- needs multiple checks in case i was in combat and got back out of it". Enter was asked once;
			-- when the game said no (in combat) it fell through to a 12,856 stud glide. Now it asks again
			-- every few seconds for up to 45 s and never glides out there: if it is still refused, it
			-- tries again on the next round.)
			local arrived, tries = false, 0
			local t0 = os.clock()
			local from = hrp.Position
			while settings.autoAbyss and alive and os.clock() - t0 < 45 and not Abyss.inRun() do
				tries += 1
				setStatus(('abyss: teleporting to the Abyss lobby (try %d)'):format(tries))
				local okE, rE, vE = pcall(function()
					return service('AbyssService'):Enter():await()
				end)
				G.FTAbyssEnter = { ok = okE, res = tostring(rE) .. ' ' .. tostring(vE), at = os.time(), tries = tries }
				local t1 = os.clock()
				while os.clock() - t1 < 4 do
					task.wait(0.25)
					local _, h2 = char()
					-- (v313, seen live: the lobby drop point is 313 studs from the cage, so "within 250" never
					-- came true and it kept asking. Arrived = jumped a long way, or the cage is close.)
					if h2 and ((h2.Position - pos).Magnitude < 700 or (h2.Position - from).Magnitude > 1000) then
						arrived = true
						break
					end
				end
				if arrived then
					break
				end
				setStatus(('abyss: teleport refused (in combat?) - asking again (try %d)'):format(tries))
				task.wait(1)
			end
			if not arrived then
				lastTry = os.clock() - 10 -- (next round in ~5 s, not 15)
				return true
			end
			task.wait(1)
		end
		setStatus('abyss: walking to the cage')
		if not tweenTo(CFrame.new(pos + Vector3.new(0, 2, 4))) then
			return true
		end
		-- Same as pressing E on the purple circle: make an Abyss party, then start it.
		setStatus('abyss: making the party')
		local partyType = 'Abyss'
		pcall(function()
			local pr = cage:FindFirstChildWhichIsA('ProximityPrompt', true)
			partyType = pr and pr:GetAttribute('PartyType') or partyType
		end)
		pcall(function()
			local pc = controller('PartyController')
			if not (pc and pc.CurrentParty) then
				service('PartyService'):CreateParty(partyType):await()
			end
		end)
		task.wait(1.5)
		setStatus('abyss: starting the run')
		pcall(function()
			service('PartyService'):Activate():await()
		end)
		task.wait(8) -- teleporting into the run
		return true
	end
end

---------------------------------------------------------------------------
-- World boss (v181, written from the game's data, NOT yet tried live).
-- Read from the game: each island's boss (Island 4: Asura's Incarnate) is entered through the
-- party gate workspace.Proximity.CreateParty (its prompt carries PartyType = the boss name).
-- Pressing it = PartyService:CreateParty(type); the leader then starts it with
-- PartyService:Activate() once the lobby is open. The menu text says boss lobbies are free and a
-- new one opens every 5-10 minutes (Raids are the ones that take a Raid Ticket: never touched here).
-- The gate shows a countdown; whether it counts to "opens" or "closes" is not known, so a start is
-- tried once right away and after that only around the moment the countdown runs out.
---------------------------------------------------------------------------
local Boss = { lastTry = -1e9, fails = 0, pauseUntil = os.clock() + math.max(0, (tonumber(G.FTBossPauseT) or 0) - os.time()), first = true } -- (v244: a reload no longer forgets that the boss was just killed)
do
	-- (v208: the boss's change into its second form plays a cutscene with a Skip button - the game
	-- puts a "BossCutscene" screen with a button named Skip in front of us. It is pressed for you.)
	pcall(function()
		if G.FTCutsceneConn then
			G.FTCutsceneConn:Disconnect()
		end
		local pg = LocalPlayer:FindFirstChildOfClass('PlayerGui')
		-- (v325, reported "skip cutscene broke": the game's Skip button (ReplicatedStorage.Assets.Effects.
		-- AsuraMorph.Assets.BossCutscene.Frame.Skip) starts hidden and is shown a moment later. The old code
		-- pressed it for 3.5 s from when it was added, so a late-shown button got every press while hidden -
		-- the 11:40 fight played the whole cutscene. Now the screen is watched for as long as it is up and
		-- the button pressed whenever it is showing.)
		local watching = setmetatable({}, { __mode = 'k' })
		local function watchCutscene(gui)
			if watching[gui] then
				return
			end
			watching[gui] = true
			task.spawn(function()
				local t0, presses, wasShown = os.clock(), 0, false
				while alive and gui.Parent and os.clock() - t0 < 60 do
					local btn = gui:FindFirstChild('Skip', true)
					local shown = btn ~= nil and btn:IsA('GuiButton') and btn.Visible
					if shown then
						local q = btn.Parent
						while q and q ~= gui do
							if q:IsA('GuiObject') and not q.Visible then
								shown = false
								break
							end
							q = q.Parent
						end
					end
					if shown and (not gui:IsA('ScreenGui') or gui.Enabled) then
						wasShown = true
						presses += 1
						pcall(function()
							firesignal(btn.Activated)
						end)
						pcall(function()
							firesignal(btn.MouseButton1Click)
						end)
						task.wait(0.4)
					else
						task.wait(0.15)
					end
				end
				watching[gui] = nil
				G.FTCutsceneSkips = (G.FTCutsceneSkips or 0) + 1
				statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('boss: cutscene %s after %.0f s (%d skip presses%s)'):format(
					gui.Parent and 'still up' or 'gone', os.clock() - t0, presses, wasShown and '' or ', Skip button never showed')
			end)
		end
		G.FTCutsceneConn = pg and pg.DescendantAdded:Connect(function(d)
			if not alive then
				return
			end
			local gui = d.Name == 'BossCutscene' and d or d:FindFirstAncestor('BossCutscene')
			if gui then
				watchCutscene(gui)
			end
		end)
		local now0 = pg and pg:FindFirstChild('BossCutscene')
		if now0 then
			watchCutscene(now0)
		end
	end)
	function Boss.gate()
		local prox = workspace:FindFirstChild('Proximity')
		local gate = prox and prox:FindFirstChild('CreateParty')
		local pr = gate and gate:FindFirstChildWhichIsA('ProximityPrompt', true)
		local kind = pr and pr:GetAttribute('PartyType')
		if not gate or type(kind) ~= 'string' then
			return nil
		end
		local okp, pos = pcall(function()
			return gate:IsA('BasePart') and gate.Position or gate:GetPivot().Position
		end)
		if not okp then
			return nil
		end
		-- the countdown on the gate, in seconds (nil = none shown)
		local secs
		for _, d in ipairs(gate:GetDescendants()) do
			if d:IsA('TextLabel') then
				local m, sc = string.match(d.Text, '^(%d+):(%d+)$')
				if m then
					secs = tonumber(m) * 60 + tonumber(sc)
				elseif string.match(d.Text, '^%d+$') then
					secs = tonumber(d.Text)
				end
			end
		end
		return gate, kind, pos, secs
	end
	-- the boss itself, alive and on our side of the map (= we are in its arena)
	function Boss.target(kind)
		local living = workspace:FindFirstChild('Living')
		local _, hrp = char()
		if not living or not hrp or type(kind) ~= 'string' then
			return nil
		end
		for _, m in ipairs(living:GetChildren()) do
			if m:GetAttribute('IsNpc') and string.sub(m.Name, 1, #kind) == kind then
				local h = m:FindFirstChildOfClass('Humanoid')
				local r = mobRoot(m)
				if h and r and h.Health > 0 then
					local d = (r.Position - hrp.Position).Magnitude
					if d < 400 then
						return { m = m, h = h, r = r, d = d, big = false }
					end
				end
			end
		end
		return nil
	end
	-- (v214) a quest that asks for this island's boss ("The Asura Threat: Defeat Asura's Incarnate")
	-- runs the boss too, with Auto boss off, while "Do quests" is on
	local qwAt, qwVal = -1e9, false
	function Boss.questWants()
		if os.clock() - qwAt < 3 then
			return qwVal
		end
		qwAt, qwVal = os.clock(), false
		local d = data()
		if not settings.doQuests or not d or type(d.Quests) ~= 'table' then
			return false
		end
		local _, kind = Boss.gate()
		if type(kind) ~= 'string' then
			return false
		end
		for _, qd in pairs(d.Quests) do
			for _, p in ipairs(type(qd) == 'table' and qd.Progress or {}) do
				if p.questType == 'Kill' and tostring(p.target) == kind and (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 1) then
					qwVal = true
				end
			end
		end
		return qwVal
	end
	function Boss.on()
		return settings.autoBoss or G.FTBossOnce == true or Boss.questWants() -- (v221: G.FTBossOnce = one kill asked for by hand)
			or (settings.autoRaid and settings.raidFarming) -- (v297: out of Raid Tickets - Asura gives one per kill)
	end
	function Boss.step()
		if not Boss.on() then
			Boss.first = true -- (so switching it on again tries straight away)
			return false
		end
		if Abyss.inRun() then
			return false
		end
		local gate, kind, pos, secs = Boss.gate()
		if not gate then
			return false
		end
		local t = Boss.target(kind)
		if t then
			Boss.fails = 0
			if not Boss.fought then
				statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('boss: fight with %s started (%d HP)'):format(kind, t.h.MaxHealth)
			end
			Boss.fought = true
			G.FTBossSeen = { name = t.m.Name, hp = t.h.Health, max = t.h.MaxHealth, at = os.time() }
			setStatus(('boss: fighting %s (%d / %d HP)'):format(kind, t.h.Health, t.h.MaxHealth))
			G.FTBossFight = true
			local okF, errF = pcall(fightOnce, t)
			G.FTBossFight = false
			if not okF then
				error(errF, 0)
			end
			return true
		end
		local now = os.clock()
		if Boss.fought then
			-- (v207: the fight is over - won, or we died and are back outside. Read from the game's party
			-- menu: a lobby window runs 10 minutes and the next opens as it closes, and the gate's clock
			-- counts down to that. So the next start waits for the next window.)
			Boss.fought = false
			-- (v208: the first kill ended with the bot setting off on a 5,158-stud trip out of the arena
			-- before the game had sent us back. Stay put until we have been moved, 20 s at most.)
			do
				local _, h0 = char()
				local p0 = h0 and h0.Position
				setStatus('boss: fight over — waiting to be sent back')
				local tw = os.clock()
				while alive and p0 and os.clock() - tw < 20 do
					local _, h1 = char()
					if not h1 or (h1.Position - p0).Magnitude > 1000 then
						break
					end
					task.wait(0.5)
				end
				now = os.clock()
			end
			Boss.pauseUntil = now + (secs or 600) + 8
			G.FTBossPauseT = os.time() + (secs or 600) + 8
			statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('boss: fight over, next start in %ds'):format((secs or 600) + 8)
			G.FTBossOnce = nil
		end
		if now < Boss.pauseUntil then
			return false
		end
		-- (v207: the lobby is open the whole window, so a start is tried whenever none is pending)
		if now - Boss.lastTry < 25 then
			return false
		end
		local _, hrp = char()
		if not hrp then
			return false
		end
		if (hrp.Position - pos).Magnitude > 12 then
			setStatus(('boss: going to the %s gate'):format(kind))
			if not tweenTo(CFrame.new(pos + Vector3.new(0, 2, 4))) then
				Boss.lastTry = os.clock()
				return true
			end
		end
		Boss.first = false
		Boss.lastTry = os.clock()
		setStatus(('boss: opening a %s party'):format(kind))
		local made, why
		pcall(function()
			local pc = controller('PartyController')
			local cur = pc and pc.CurrentParty
			if cur and cur.Type ~= kind then
				why = 'you are in a ' .. tostring(cur.Type) .. ' party'
			elseif not cur then
				service('PartyService'):CreateParty(kind):await()
			end
			made = why == nil
		end)
		if not made then
			setStatus('boss: could not open the party' .. (why and (' — ' .. why) or ''))
			Boss.pauseUntil = os.clock() + 300
			return true
		end
		task.wait(1.5)
		setStatus(('boss: starting %s'):format(kind))
		local okA, a, b = pcall(function()
			return service('PartyService'):Activate():await()
		end)
		G.FTBossStart = ('%s ok=%s %s %s'):format(os.date('%H:%M:%S'), tostring(okA), tostring(a), tostring(b))
		-- in the arena = the boss shows up next to us
		local t0 = os.clock()
		while alive and Boss.on() and os.clock() - t0 < 25 do
			if Boss.target(kind) then
				statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('boss: in the arena with %s'):format(kind)
				return true
			end
			task.wait(0.5)
		end
		Boss.fails += 1
		statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('boss: the start did not go through (%s), try %d'):format(tostring(G.FTBossStart), Boss.fails)
		if Boss.fails >= 3 then
			-- (a lobby that never opens for us - e.g. already beaten today: stop walking over)
			Boss.fails = 0
			Boss.pauseUntil = os.clock() + 1800
			setStatus(('boss: %s would not start 3 times in a row — trying again in 30 minutes'):format(kind))
		else
			setStatus(('boss: %s did not start — next try when the gate countdown runs out'):format(kind))
		end
		return true
	end
end

---------------------------------------------------------------------------
-- Weapon DPS test (v209). Asked for with G.FTDpsTest = true or the button: goes to the nearest
-- DPS dummy, equips every weapon in the bag in turn, swings for Dps.secs seconds each and adds
-- up what the dummy lost. Puts the old weapon back. Uses nothing up.
---------------------------------------------------------------------------
local Dps = { secs = 20 }
do
	function Dps.step()
		if not G.FTDpsTest then
			return false
		end
		G.FTDpsTest = nil
		local raw, rows = {}, {}
		G.FTDpsRaw, G.FTDpsRows = raw, rows
		local function note(s)
			raw[#raw + 1] = s
			pcall(writefile, 'PlayerTools/forgetools_dps.txt', table.concat(raw, '\n'))
		end
		local c, hrp, hum = char()
		local d = data()
		local living = workspace:FindFirstChild('Living')
		if not (c and hrp and hum and d and living) then
			note('not ready')
			note('done')
			return true
		end
		local dummy, dd
		for _, m in ipairs(living:GetChildren()) do
			if m:GetAttribute('DpsDummy') then
				local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
				if r then
					local dist = (r.Position - hrp.Position).Magnitude
					if not dd or dist < dd then
						dummy, dd = m, dist
					end
				end
			end
		end
		if not dummy or dd > 1500 then
			note('no DPS dummy within reach')
			note('done')
			return true
		end
		local dr = dummy:FindFirstChild('HumanoidRootPart') or dummy.PrimaryPart
		local dh = dummy:FindFirstChildOfClass('Humanoid')
		local function flat()
			return ((dr.Position - hrp.Position) * Vector3.new(1, 0, 1)).Magnitude
		end
		local function spot()
			local dir = (hrp.Position - dr.Position) * Vector3.new(1, 0, 1)
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
			return dr.Position + dir * 3.5
		end
		setStatus(('dps test: going to the dummy (%d studs)'):format(dd))
		if flat() > 5 then
			tweenTo(CFrame.new(spot() + Vector3.new(0, 2, 0)))
		end
		note(('at the dummy: %.1f studs'):format(flat()))
		if flat() > 8 then
			note('could not get to the dummy')
			note('done')
			return true
		end
		local CS = service('CharacterService')
		local list = {}
		for _, it in pairs(d.Inventory.Equipments) do
			if type(it) == 'table' and it.GUID and type(it.Type) == 'string'
				and not (string.find(it.Type, 'Leggings') or string.find(it.Type, 'Helmet') or string.find(it.Type, 'Chestplate')) then
				list[#list + 1] = it
			end
		end
		table.sort(list, function(a, b)
			return a.Type .. tostring(a.Ore) < b.Type .. tostring(b.Ore)
		end)
		local orig = d.Equipped.Weapon and d.Equipped.Weapon.GUID
		local function worn(guid)
			return d.Equipped.Weapon ~= nil and d.Equipped.Weapon.GUID == guid
		end
		local function label()
			local bb = dummy:FindFirstChild('BB', true)
			local a = bb and bb:FindFirstChild('rockHP')
			return a and a.Text or '?'
		end
		for i, it in ipairs(list) do
			if not alive or hum.Health / hum.MaxHealth < 0.5 then
				note('stopped early (health low or unloaded)')
				break
			end
			local name = ('%s | %s | Q%.0f +%d'):format(it.Type, tostring(it.Ore), it.Quality or 0, it.Upgrade or 0)
			setStatus(('dps test %d/%d: %s'):format(i, #list, name))
			pcall(function()
				return CS:EquipItem(it)
			end)
			local te = os.clock()
			while os.clock() - te < 4 and not worn(it.GUID) do
				task.wait(0.1)
			end
			task.wait(1.2)
			if not worn(it.GUID) then
				note(name .. ' | could not equip')
			else
				local hits, sum, last, drops, nums, big = 0, 0, dh.Health, {}, {}, 0
				local conn = dh.HealthChanged:Connect(function(h)
					if h < last then
						hits += 1
						sum += last - h
						if #drops < 6 then
							drops[#drops + 1] = ('%.0f'):format(last - h)
						end
					end
					last = h
				end)
				local conn2 = workspace.DescendantAdded:Connect(function(x)
					if x:IsA('TextLabel') then
						task.defer(function()
							pcall(function()
								local v = tonumber(x.Text)
								if v and (x.AbsolutePosition.Magnitude >= 0) then
									hits += 1
									sum += v
									if v > big then
										big = v
									end
									if #nums < 8 then
										nums[#nums + 1] = x.Text
									end
								end
							end)
						end)
					end
				end)
				local ts, labMax = os.clock(), 0
				while alive and os.clock() - ts < Dps.secs do
					local tool = equip('Weapon')
					if tool then
						swing(tool)
					end
					if flat() > 5 then
						hum:MoveTo(spot())
					end
					hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(dr.Position.X, hrp.Position.Y, dr.Position.Z))
					local n = tonumber((string.gsub(label(), '[^%d%.]', '')))
					if n and n > labMax then
						labMax = n
					end
					task.wait(0.05)
				end
				task.wait(0.8)
				conn:Disconnect()
				conn2:Disconnect()
				local span = os.clock() - ts
				rows[#rows + 1] = { name = name, hits = hits, sum = sum, dps = sum / span, big = big }
				note(('%s | numbers %d | total %.0f | dps %.0f | biggest %.0f | first %s'):format(name, hits, sum, sum / span, big, table.concat(nums, ';')))
			end
		end
		if orig then
			for _, it in pairs(d.Inventory.Equipments) do
				if type(it) == 'table' and it.GUID == orig then
					pcall(function()
						return CS:EquipItem(it)
					end)
				end
			end
			task.wait(1.5)
			note('old weapon back on: ' .. tostring(worn(orig)))
		end
		table.sort(rows, function(a, b)
			return a.dps > b.dps
		end)
		if rows[1] then
			statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('dps test: best is %s (%.0f dps)'):format(rows[1].name, rows[1].dps)
		end
		note('done')
		return true
	end
end

---------------------------------------------------------------------------
-- Quest pickups (v213). A "Collect X" quest whose X lies on the map as workspace.Proximity.X1,
-- X2 ... with a prompt (Buried Remains: Skull1-3): go to each and press it.
---------------------------------------------------------------------------
local Pickup = { tried = {} }
do
	function Pickup.step()
		if not settings.doQuests then
			return false
		end
		local d = data()
		local prox = workspace:FindFirstChild('Proximity')
		local _, hrp = char()
		if not (d and prox and hrp and type(d.Quests) == 'table') then
			return false
		end
		for id, qd in pairs(d.Quests) do
			for _, p in ipairs(type(qd) == 'table' and qd.Progress or {}) do
				local target = tostring(p.target)
				if p.questType == 'Collect' and #target >= 3 and (tonumber(p.currentProgress) or 0) < (tonumber(p.requiredAmount) or 1) then
					local best, bd
					for _, m in ipairs(prox:GetChildren()) do
						if string.match(m.Name, '^' .. string.gsub(target, '%p', '%%%0') .. '%s?%d*$') and os.clock() - (Pickup.tried[m] or -1e9) > 180 then
							local pr = m:FindFirstChildWhichIsA('ProximityPrompt', true)
							local okp, pos = pcall(function()
								return m:IsA('BasePart') and m.Position or m:GetPivot().Position
							end)
							if pr and okp then
								local dist = (pos - hrp.Position).Magnitude
								if dist <= math.max(tonumber(settings.questRange) or 1000, 1000) and (not bd or dist < bd) then
									best, bd = { m = m, pr = pr, pos = pos }, dist
								end
							end
						end
					end
					if best then
						Pickup.tried[best.m] = os.clock()
						setStatus(('quest: picking up %s (%d studs)'):format(best.m.Name, bd))
						if tweenTo(CFrame.new(best.pos + Vector3.new(0, 3, 3))) then
							local before = tonumber(p.currentProgress) or 0
							for _ = 1, 3 do
								pcall(function()
									fireproximityprompt(best.pr)
								end)
								task.wait(0.6)
								if (tonumber(p.currentProgress) or 0) > before or not best.m.Parent then
									break
								end
							end
							statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('quest pickup %s: %s %d -> %d'):format(best.m.Name, target, before, tonumber(p.currentProgress) or 0)
						end
						return true
					end
				end
			end
		end
		return false
	end
end

---------------------------------------------------------------------------
-- Raid start (v216). ONE raid per press of the button (or G.FTRaidStart = { tier = n }): goes to
-- the raid gate, opens a Tower of Hell party, sets the tier and starts it. A start spends one
-- Raid Ticket, so nothing here ever starts a raid on its own.
---------------------------------------------------------------------------
local Raid = {}
do
	function Raid.tickets()
		local d = data()
		for _, it in pairs(d and d.Inventory and type(d.Inventory.Misc) == 'table' and d.Inventory.Misc or {}) do
			if type(it) == 'table' and it.Name == 'RaidTicket' then
				return tonumber(it.Quantity) or 0
			end
		end
		return 0
	end
	pcall(function()
		local pc = controller('PartyController')
		Raid.party = pc.CurrentParty
		pc.PartyJoined:Connect(function(pt)
			Raid.party = pt
		end)
		pc.PartyLeft:Connect(function()
			Raid.party = nil
		end)
	end)
	-- (v217) the Retry button on the raid result screen, while "Raid retries left" is above 0.
	-- Each press starts another raid = one more Raid Ticket; the count goes down by one per press.
	task.spawn(function()
		local pressed = false
		while alive do
			task.wait(1)
			local g = LocalPlayer.PlayerGui:FindFirstChild('RaidRewards')
			local left = math.floor(tonumber(settings.raidRetries) or 0)
			local autoR = settings.autoRaid and not settings.raidFarming -- (v297: Auto raid retries while tickets last)
			if g and g.Enabled and not pressed and (left > 0 or autoR) and Raid.tickets() >= 1 then
				local b = g:FindFirstChild('Retry', true)
				if b and b:IsA('GuiButton') then
					task.wait(5) -- (let the rewards show first)
					pressed = true
					if not autoR then
						settings.raidRetries = left - 1
					end
					save()
					statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('raid: pressing Retry (%d retries left after this, %d tickets)'):format(left - 1, Raid.tickets())
					for _ = 1, 3 do
						pcall(function()
							firesignal(b.Activated)
						end)
						pcall(function()
							firesignal(b.MouseButton1Click)
						end)
						task.wait(1)
						if not (g.Parent and g.Enabled) then
							break
						end
					end
				end
			elseif g and g.Enabled and not pressed and settings.autoRaid and (settings.raidFarming or Raid.tickets() < 1) then
				-- (v298) out of tickets with Auto raid on: leave the raid for the island (Asura farm)
				local b
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA('GuiButton') and (string.find(string.lower(d.Name), 'island', 1, true)
						or (d:IsA('TextButton') and string.find(string.lower(d.Text), 'island', 1, true))) then
						b = d
						break
					end
					if d:IsA('TextLabel') and string.find(string.lower(d.Text), 'go to island', 1, true) then
						local pb = d:FindFirstAncestorWhichIsA('GuiButton')
						if pb then
							b = pb
							break
						end
					end
				end
				if b then
					task.wait(5)
					pressed = true
					statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. 'raid: out of tickets — going back to the island'
					for _ = 1, 3 do
						pcall(function()
							firesignal(b.Activated)
						end)
						pcall(function()
							firesignal(b.MouseButton1Click)
						end)
						task.wait(1)
						if not (g.Parent and g.Enabled) then
							break
						end
					end
				end
			elseif not (g and g.Enabled) then
				pressed = false
			end
		end
	end)
	-- (v297, asked for: "for auto raid, make it so, if tickets ran out farm asura until max tickets
	-- again, make sure to do something on the side while waiting for asura spawns, then go back to
	-- raids, once tickets max". Auto raid starts a raid at the gate whenever a ticket is left (and the
	-- result screen's Retry is pressed while tickets last). At 0 tickets it farms Asura's Incarnate -
	-- one ticket per kill - and mines between spawns (Auto mine is switched on for that if neither
	-- mining nor mobs is on, and off again after). Back to raids at "Raid tickets to farm back to".)
	task.spawn(function()
		local lastStart = -1e9
		while alive do
			task.wait(2)
			if not settings.autoRaid then
				if settings.raidSideMine then
					settings.autoMine, settings.raidSideMine = false, false
					save()
				end
				continue
			end
			local t = Raid.tickets()
			local maxT = math.max(1, math.floor(tonumber(settings.raidTicketMax) or 5))
			if settings.raidFarming and t >= maxT then
				settings.raidFarming = false
				if settings.raidSideMine then
					settings.autoMine, settings.raidSideMine = false, false
				end
				save()
				statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('raid: tickets back to %d — back to raids'):format(t)
			elseif not settings.raidFarming and t < 1 then
				settings.raidFarming = true
				save()
				statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('raid: out of tickets — farming Asura until %d'):format(maxT)
			end
			if settings.raidFarming then
				if not settings.autoMine and not settings.autoMobs then
					settings.autoMine, settings.raidSideMine = true, true -- (something to do between spawns)
					save()
				end
				if not G.FTBossFight then
					G.FTRaidWhy = ('out of tickets (%d/%d): farming Asura, mining in between'):format(t, maxT)
				end
			elseif t >= 1 and type(G.FTRaidStart) ~= 'table' and not G.FTBossFight and os.clock() - lastStart > 90
				and not (LocalPlayer.PlayerGui:FindFirstChild('RaidRewards') and LocalPlayer.PlayerGui.RaidRewards.Enabled) then
				local prox = workspace:FindFirstChild('Proximity')
				if prox and prox:FindFirstChild('RaidCreateParty') then
					lastStart = os.clock()
					G.FTRaidStart = { tier = tonumber(settings.raidTier) or 1 }
				end
			end
		end
	end)
	function Raid.step()
		local req = G.FTRaidStart
		if type(req) ~= 'table' then
			return false
		end
		G.FTRaidStart = nil
		local function say(sx)
			setStatus(sx)
			statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. sx
			G.FTRaidLog = G.FTRaidLog or {}
			table.insert(G.FTRaidLog, os.date('%H:%M:%S ') .. sx)
		end
		local prox = workspace:FindFirstChild('Proximity')
		local gate = prox and prox:FindFirstChild('RaidCreateParty')
		local pr = gate and gate:FindFirstChildWhichIsA('ProximityPrompt', true)
		local kind = pr and pr:GetAttribute('PartyType')
		if not gate or type(kind) ~= 'string' then
			say('raid: no raid gate on this island')
			return true
		end
		local before = Raid.tickets()
		if before < 1 then
			say('raid: no Raid Ticket')
			return true
		end
		local tier = math.max(1, math.floor(tonumber(req.tier) or 1))
		local pos = gate:IsA('BasePart') and gate.Position or gate:GetPivot().Position
		local _, hrp = char()
		if hrp and (hrp.Position - pos).Magnitude > 8 then
			say(('raid: going to the %s gate'):format(kind))
			if not tweenTo(CFrame.new(pos + Vector3.new(0, 2, 3))) then
				say('raid: could not get to the gate')
				return true
			end
		end
		task.wait(1)
		local PS = service('PartyService')
		local okC, c1 = pcall(function()
			return PS:CreateParty(kind):await()
		end)
		task.wait(1.5)
		-- (v217: the party object, to read back which tier it is really on)
		local party = Raid.party
		local function partyTier()
			local okp, v = pcall(function()
				return party.Replica.Data.Tier
			end)
			return okp and tonumber(v) or nil
		end
		local okT, t1, t2
		for _ = 1, 6 do
			if (partyTier() or 1) == tier then
				break
			end
			okT, t1, t2 = pcall(function()
				return PS:SetTier(tier):await()
			end)
			task.wait(1)
			party = Raid.party
		end
		local got = partyTier()
		if tier ~= 1 and got ~= tier then
			say(('raid: could not set tier %d (party is on %s, answer %s %s %s) — NOT started, no ticket spent'):format(tier, tostring(got), tostring(okT), tostring(t1), tostring(t2)))
			pcall(function()
				PS:Leave()
			end)
			return true
		end
		say(('raid: party %s, party tier %s (asked %d) — starting (tickets %d)'):format(tostring(okC and c1), tostring(got), tier, before))
		local okA, a1, a2 = pcall(function()
			return PS:Activate():await()
		end)
		task.wait(3)
		say(('raid: start answered %s %s %s, tickets %d -> %d'):format(tostring(okA), tostring(a1), tostring(a2), before, Raid.tickets()))
		return true
	end
end

---------------------------------------------------------------------------
-- Ore crafting at a craft station (v219). One-shot: G.FTCraft = { ore = 'Lgarite', n = 3 }.
-- Crafting from afar is answered "ok" by the game but does nothing without the Craft Anywhere
-- pass (measured), so this walks to the nearest craft station first. Spends the recipe's gold
-- and ores, so nothing here ever starts by itself.
---------------------------------------------------------------------------
local Craft = {}
do
	local function say(sx)
		setStatus(sx)
		statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. sx
		G.FTCraftLog = G.FTCraftLog or {}
		table.insert(G.FTCraftLog, os.date('%H:%M:%S ') .. sx)
	end
	local function have(ore)
		local d = data()
		return d and d.Inventory and tonumber(d.Inventory[ore]) or 0
	end
	function Craft.step()
		local req = G.FTCraft
		if type(req) ~= 'table' or type(req.ore) ~= 'string' then
			return false
		end
		G.FTCraft = nil
		local n = math.max(1, math.floor(tonumber(req.n) or 1))
		local _, hrp = char()
		local prox = workspace:FindFirstChild('Proximity')
		local best, bestD, bestPos
		for _, m in ipairs(prox and prox:GetChildren() or {}) do
			if hrp and string.find(m.Name, 'Craft Station', 1, true) then
				local pos = m:IsA('BasePart') and m.Position or m:GetPivot().Position
				local dd = (pos - hrp.Position).Magnitude
				if not bestD or dd < bestD then
					best, bestD, bestPos = m, dd, pos
				end
			end
		end
		if not best then
			say('craft: no craft station on this island')
			return true
		end
		if bestD > 9 then
			say(('craft: going to %s (%d studs)'):format(best.Name, bestD))
			if not tweenTo(CFrame.new(bestPos + Vector3.new(0, 2, 5))) then
				say('craft: could not get to the station')
				return true
			end
		end
		task.wait(0.8)
		local d = data()
		local OS = service('OreCraftService')
		local before, gold0 = have(req.ore), d and tonumber(d.Gold) or 0
		local okS, s1 = pcall(function()
			return OS:StartCrafting(best.Name):await()
		end)
		task.wait(0.5)
		local okR, r1, r2 = pcall(function()
			return OS:CraftRequest(req.ore, n):await()
		end)
		say(('craft: %d x %s at %s — open %s %s, request %s %s %s'):format(n, req.ore, best.Name, tostring(okS), tostring(s1), tostring(okR), tostring(r1), tostring(r2)))
		local t0 = os.clock()
		while alive and os.clock() - t0 < (tonumber(req.wait) or 300) and have(req.ore) < before + n do
			task.wait(3)
			pcall(function()
				OS:CheckCraftCompletions()
			end)
			setStatus(('craft: waiting for %s (%d of %d, %.0fs)'):format(req.ore, have(req.ore) - before, n, os.clock() - t0))
			if os.clock() - t0 > 20 and have(req.ore) == before and (tonumber(data().Gold) or 0) >= gold0 and not req.long then
				break -- (nothing was taken and nothing came: the request was refused)
			end
		end
		say(('craft: %s %d -> %d, gold %.0f -> %.0f, %.0fs'):format(req.ore, before, have(req.ore), gold0, tonumber(data().Gold) or 0, os.clock() - t0))
		return true
	end
end

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
local Library
do
	G.Library = nil
	Library = assert(compile(readfile('PlayerTools/AtaraxiaLibrary.lua'), 'AtaraxiaLibrary.lua'), 'AtaraxiaLibrary.lua failed')()
	Library.Animations = type(Library.Animations) == 'table' and Library.Animations or {}
	Library.Animations.TabSwitch = false
	Library.Animations.Dropdown = false
	G.SB2ForgeToolsLibrary = Library
end
local Window = Library:CreateWindow({
	Title = 'Forge Tools',
	Footer = BUILD .. '  ·  ' .. LocalPlayer.Name,
	Folder = 'ForgeTools',
	Size = UDim2.fromOffset(640, 460),
	MinSize = Vector2.new(560, 380),
	Resizable = true,
	OnUnload = function()
		if type(G.SB2ForgeToolsUnload) == 'function' then
			pcall(G.SB2ForgeToolsUnload, true)
		end
	end,
})
-- (v326, asked for: options split over tabs instead of one long Main page; every box starts folded)
local UI = {}
do
	local home = Window:AddTab('Home', 'home')
	UI.status = home:AddLeftGroupbox('Status')
	UI.travel = home:AddLeftGroupbox('Travel')
	UI.move = home:AddRightGroupbox('Movement')
	UI.menus = home:AddRightGroupbox('Game menus')
	UI.script = home:AddRightGroupbox('Script')
	local mine = Window:AddTab('Mining', 'pickaxe')
	UI.mine = mine:AddLeftGroupbox('Mining')
	UI.potions = mine:AddLeftGroupbox('Potions')
	UI.rocks = mine:AddRightGroupbox('Which rocks')
	local sell = Window:AddTab('Selling', 'coins')
	UI.sellOres = sell:AddLeftGroupbox('Ores')
	UI.sellGear = sell:AddLeftGroupbox('Gear')
	UI.sellRunes = sell:AddRightGroupbox('Runes')
	local forge = Window:AddTab('Forge', 'anvil')
	UI.forge = forge:AddLeftGroupbox('Forging')
	UI.recycle = forge:AddLeftGroupbox('Recycle')
	UI.forgeOres = forge:AddRightGroupbox('Ores and targets')
	UI.enhance = forge:AddRightGroupbox('Enhance & equip')
	local combat = Window:AddTab('Combat', 'sword')
	UI.mobs = combat:AddLeftGroupbox('Mobs')
	UI.health = combat:AddLeftGroupbox('Health')
	UI.defense = combat:AddRightGroupbox('Block & dodge')
	UI.combatMisc = combat:AddRightGroupbox('Tools')
	local abyss = Window:AddTab('Abyss & raids', 'skull')
	UI.abyss = abyss:AddLeftGroupbox('Abyss')
	UI.boss = abyss:AddLeftGroupbox('Boss')
	UI.raids = abyss:AddRightGroupbox('Raids')
	local quests = Window:AddTab('Quests', 'scroll')
	UI.quests = quests:AddLeftGroupbox('Quests')
	UI.rewards = quests:AddRightGroupbox('Rewards')
	UI.shop = quests:AddRightGroupbox('Shop')
	local race = Window:AddTab('Race & runes', 'dna')
	UI.race = race:AddLeftGroupbox('Race reroll')
	UI.swap = race:AddLeftGroupbox('Race swap')
	UI.runes = race:AddRightGroupbox('Runes')
	task.defer(function()
		pcall(function()
			home:Show()
		end)
	end)
end

-- Every feature toggle starts OFF each time the script loads (sliders / dropdowns keep their values)
-- EXCEPT right after a teleport (Abyss in/out, island travel): then they carry over.
local sessionPath = 'PlayerTools/forgetools_session_' .. string.lower(LocalPlayer.Name):gsub('[^%w_]', '') .. '.json'
local resume = {}
pcall(function()
	if isfile(sessionPath) then
		local sess = HttpService:JSONDecode(readfile(sessionPath))
		if type(sess) == 'table' and type(sess.t) == 'number' and os.time() - sess.t < 150 and type(sess.on) == 'table' then
			resume = sess.on
		end
		writefile(sessionPath, '{}') -- one use only
	end
end)
local toggleKeys = {}
pcall(function()
	if G.FTTeleportConn then
		G.FTTeleportConn:Disconnect()
	end
	G.FTTeleportConn = LocalPlayer.OnTeleport:Connect(function(state)
		if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
			local on = {}
			for key in pairs(toggleKeys) do
				on[key] = settings[key] == true
			end
			pcall(writefile, sessionPath, HttpService:JSONEncode({ t = os.time(), on = on }))
		end
	end)
end)
local function bindToggle(box, idx, key, text, tip)
	toggleKeys[key] = true
	settings[key] = resume[key] == true
	box:AddToggle(idx, { Text = text, Default = settings[key], Tooltip = tip }):OnChanged(function(v)
		settings[key] = v == true
		save()
		if not v then
			stopTween()
		end
	end)
end
local function bindDropdown(box, idx, key, text, values, tip)
	local dd = box:AddDropdown(idx, { Text = text, Values = values, Default = settings[key], AllowNull = false, Tooltip = tip })
	dd:OnChanged(function(v)
		if type(v) == 'table' then
			v = next(v)
		end
		if v ~= nil then
			settings[key] = v
			save()
		end
	end)
	return dd
end
local function bindSlider(box, idx, key, text, min, max, tip)
	box:AddSlider(idx, { Text = text, Min = min, Max = max, Rounding = 0, Default = tonumber(settings[key]) or min, Tooltip = tip }):OnChanged(function(v)
		settings[key] = tonumber(v) or settings[key]
		save()
	end)
end

local function zoneNames()
	local out = { 'Any' }
	local rocks = workspace:FindFirstChild('Rocks')
	for _, z in ipairs(rocks and rocks:GetChildren() or {}) do
		if z.Name ~= 'Roof' then
			out[#out + 1] = z.Name
		end
	end
	return out
end
local function mobNames()
	local set, out = {}, { 'Any' }
	for _, m in ipairs(workspace:FindFirstChild('Living') and workspace.Living:GetChildren() or {}) do
		if m:GetAttribute('IsNpc') then
			local b = baseName(m.Name)
			if not set[b] then
				set[b] = true
				out[#out + 1] = b
			end
		end
	end
	return out
end

bindToggle(UI.mine, 'FTAutoMine', 'autoMine', 'Auto mine', 'Tweens to the nearest rock and mines it. Rock types your pickaxe cannot damage are skipped.')
bindToggle(UI.rocks, 'FTMineOnlyPicked', 'mineOnlyPicked', 'Mine only the picked rocks', 'With rocks picked under "Mine these rocks first", nothing else is mined while none of them is standing.')
bindToggle(UI.mine, 'FTIgnoreMobs', 'ignoreMobs', 'Ignore mobs while mining', 'Keeps mining when a mob comes up instead of fighting it. Attack markers are still dodged; low health and mobs that have killed you still pull it away.')
bindToggle(UI.mine, 'FTMineMeteors', 'mineMeteors', 'Break event meteors', 'When an event drops meteors (Inferno, Prismatic, Fichillium, comet rocks) the bot goes to each one and breaks it with the pickaxe before anything else. They only last 90 seconds.')
local zoneDD = bindDropdown(UI.rocks, 'FTMineZone', 'mineZone', 'Mine in', zoneNames())
local function rockNames()
	local hp, out = {}, {}
	local rocks = workspace:FindFirstChild('Rocks')
	for _, zone in ipairs(rocks and rocks:GetChildren() or {}) do
		for _, sp in ipairs(zone:GetChildren()) do
			local m = sp:FindFirstChildWhichIsA('Model')
			if m and m:FindFirstChild('Hitbox') and not hp[m.Name] then
				hp[m.Name] = tonumber(m:GetAttribute('MaxHealth')) or 0
				out[#out + 1] = m.Name
			end
		end
	end
	for name in pairs(type(settings.mineRocks) == 'table' and settings.mineRocks or {}) do
		if not hp[name] then
			hp[name] = 0
			out[#out + 1] = name
		end
	end
	table.sort(out, function(a, b)
		return hp[a] > hp[b]
	end)
	return out
end
local rockDD
pcall(function()
	pcall(function()
		local labels, idOf, labelOf = {}, {}, {}
		pcall(function()
			for id, def in pairs(require(RS.Shared.Data.RockMutations).Mutations) do
				local label = type(def) == 'table' and tostring(def.DisplayName or id) or tostring(id)
				labels[#labels + 1] = label
				idOf[label], labelOf[id] = id, label
			end
		end)
		if #labels == 0 then
			for id, label in pairs({ Galaxy = 'Galactic', Blessed = 'Blessed', Prismatic = 'Prismatic', Moss = 'Mossy', Corrupted = 'Corrupted', Molten = 'Molten' }) do
				labels[#labels + 1] = label
				idOf[label], labelOf[id] = id, label
			end
		end
		table.sort(labels)
		if type(settings.mineMutations) ~= 'table' then
			settings.mineMutations = {}
		end
		local def = {}
		for id, on in pairs(settings.mineMutations) do
			if on == true and labelOf[id] then
				def[#def + 1] = labelOf[id]
			end
		end
		UI.rocks:AddDropdown('FTMineMutations', { Text = 'Marked rocks first', Values = labels, Multi = true, Default = def, AllowNull = true,
			Tooltip = 'Rocks carrying one of these marks (Galactic, Blessed, Prismatic...) are mined before anything else, whatever kind of rock they are and wherever they are on the map. Nothing picked = off.' }):OnChanged(function(v)
			local out = {}
			for label, on in pairs(type(v) == 'table' and v or {}) do
				if on and idOf[label] then
					out[idOf[label]] = true
				end
			end
			settings.mineMutations = out
			save()
		end)
	end)
	rockDD = UI.rocks:AddDropdown('FTMineRocks', { Text = 'Mine these rocks first', Values = rockNames(), Multi = true, Default = settings.mineRocks, AllowNull = true,
		Tooltip = 'Works with Auto mine. Picked rocks are mined before anything else, however far. When none of them is up, it takes the next best kind: the one with the most health below your pick (huge > large > medium > small). Nothing picked = nearest rock, as before. Listed from most health to least.' })
	rockDD:OnChanged(function(v)
		local out = {}
		for k, on in pairs(type(v) == 'table' and v or {}) do
			if on then
				out[k] = true
			end
		end
		settings.mineRocks = out
		MineHooks.selRef = nil
		save()
	end)
end)
bindToggle(UI.rocks, 'FTSkipLucky', 'skipLucky', 'Skip Lucky Blocks', 'Lucky Blocks have 10,000 HP.')
bindToggle(UI.sellRunes, 'FTAutoSellRunes', 'autoSellRunes', 'Auto sell runes', 'Sells runes from wherever you are (raids too), as they come in. Only Common, Uncommon and Rare runes up to the tier below, and never a kind picked under "Runes to keep", an Epic or rarer rune, or a favorited one.')
bindToggle(UI.sellRunes, 'FTRuneSellEpic', 'runeSellEpic', 'Also sell Epic and rarer runes', 'Off: only Common, Uncommon and Rare runes are sold. On: Epic and rarer runes are sold too, unless their kind is picked under "Runes to keep". Starts off every time the script loads.')
bindSlider(UI.sellRunes, 'FTRuneKeepTier', 'runeKeepTier', 'Keep those kinds from tier', 1, 3, 'The kinds picked under "Runes to keep" are only kept at this tier or higher: at 3, their tier I and II copies are sold like any other rune.')
bindSlider(UI.sellRunes, 'FTRuneSellTier', 'runeSellTier', 'Sell runes up to tier', 1, 5, 'Tier 1 = Frost Speck, Rage Mark, Ward Patch and the like. Runes of a higher tier than this are kept.')
pcall(function()
	local names, seen = {}, {}
	pcall(function()
		for id, def in pairs(require(RS.Shared.Data.Runes).Runes) do
			if type(def) == 'table' then
				local k = (string.gsub(tostring(def.Name or id), '%s+[IVX]+$', ''))
				if not seen[k] then
					seen[k] = true
					names[#names + 1] = k
				end
			end
		end
	end)
	for k in pairs(type(settings.runeKeep) == 'table' and settings.runeKeep or {}) do
		if not seen[k] then
			seen[k] = true
			names[#names + 1] = k
		end
	end
	table.sort(names)
	local dd = UI.sellRunes:AddDropdown('FTRuneKeep', { Text = 'Runes to keep', Values = names, Multi = true, Default = settings.runeKeep, AllowNull = true,
		Tooltip = 'These kinds are never sold, whatever their tier. Every other rune below Epic (and within the tier above) is sold - all copies of it.' })
	dd:OnChanged(function(v)
		local out = {}
		for k, on in pairs(type(v) == 'table' and v or {}) do
			if on then
				out[k] = true
			end
		end
		settings.runeKeep = out
		save()
	end)
end)
bindToggle(UI.potions, 'FTAutoLuckPotion', 'autoLuckPotion', 'Auto luck potions (buy + drink)', 'Keeps a Luck Potion running: drinks them up to the 1 hour cap (never past it). Only buys more (10, the most the shop lets you hold) once you have none of that potion left.')
bindToggle(UI.potions, 'FTAutoMinerPotion', 'autoMinerPotion', 'Auto miner potions (buy + drink)', 'Keeps a Miner Potion running: drinks them up to the 15 minute cap (3 potions - more would be wasted). Only buys more (10, the most the shop lets you hold) once you have none of that potion left.')
bindToggle(UI.sellOres, 'FTAutoSell', 'autoSell', 'Auto sell ores', 'Sells your ores at Greedy Cey when the bag reaches the % below.')
bindSlider(UI.sellOres, 'FTSellAt', 'sellAt', 'Sell when bag is % full', 20, 100)
bindToggle(UI.sellGear, 'FTAutoSellGear', 'autoSellGear', 'Auto sell spare gear', 'Sells weapons and armor at Marbles once 3+ spares pile up. Never sells what you are wearing, the best item of each slot (weapon / helmet / chestplate / leggings), favorited items or pickaxes.')
UI.sellOres:AddButton('Sell ores now', function()
	sellOres()
end)
-- The ore craft menu, from anywhere (the game has an "Anywhere" station of its own: opening
-- with no station uses it). The game's code must run at its own thread identity - at ours it
-- stops half way ("Cannot require a non-RobloxScript module") with the player left frozen.
UI.menus:AddButton('Open / close craft menu', function()
	task.spawn(function()
		pcall(function()
			local setid = setthreadidentity or setidentity
			if setid then
				setid(2)
			end
			local UI = controller('UIController')
			local gui = LocalPlayer.PlayerGui:FindFirstChild('Craft')
			if gui and gui.Enabled then
				UI:Close('OreCraft')
				pcall(function()
					controller('OreCraftController'):EndCrafting()
				end)
				return
			end
			UI:Open('OreCraft')
			-- (the game roots you to the spot while this is open: fine at a station, not in a raid)
			task.wait(0.5)
			local _, _, hum = char()
			local st = hum and hum.Parent:FindFirstChild('Status')
			local tag = st and st:FindFirstChild('NoMovement')
			if tag then
				tag:Destroy()
			end
		end)
	end)
end)
-- The bag: the game's own opener does nothing in a raid (the window stays parked below the
-- screen), so if it has not come up we put it there ourselves.
local function menuTab(tab)
	task.spawn(function()
		pcall(function()
			-- (the game's own code has to run at its thread identity, or its requires fail)
			local setid = setthreadidentity or setidentity
			if setid then
				setid(2)
			end
			local gui = LocalPlayer.PlayerGui:FindFirstChild('Menu')
			local inner = gui and gui:FindFirstChild('Frame') and gui.Frame:FindFirstChild('Frame')
			local UI = controller('UIController')
			local M = UI and UI.Modules and UI.Modules.Menu
			if not inner or not M then
				return
			end
			local menus
			for _, c in ipairs(inner:GetDescendants()) do
				if c.Name == 'Menus' then
					menus = c
					break
				end
			end
			local function shown()
				return inner.Visible and inner.Position.Y.Scale < 1
			end
			local page = menus and menus:FindFirstChild(tab)
			if shown() and page and page.Visible then
				-- already showing this tab: the button closes it
				pcall(function()
					UI:Close('Menu')
				end)
				task.wait(0.6)
				if shown() then
					inner.Position = UDim2.new(0.5, 0, 1.5, 0)
					inner.Visible = false
					M.IsOpen = false
				end
				return
			end
			if not shown() then
				pcall(function()
					M:Open()
				end)
				task.wait(0.7)
				if not shown() then
					gui.Enabled = true
					inner.Visible = true
					inner.Position = UDim2.new(0.5, 0, 0.5, 0)
					M.IsOpen = true
				end
			end
			-- OpenTab switches pages the game's way (so its own tab buttons keep working after);
			-- if it was already on this tab it does nothing, so its contents are rebuilt by hand.
			local before = page and page.Visible
			pcall(function()
				M:OpenTab(tab)
			end)
			task.wait(0.2)
			if before or (page and not page.Visible) then
				pcall(function()
					M:OpenModule(tab, true)
				end)
			end
		end)
	end)
end
UI.menus:AddButton('Open / close bag', function()
	menuTab('Stash')
end)
UI.menus:AddButton('Open / close equipment', function()
	menuTab('Tools')
end)

bindToggle(UI.forge, 'FTAutoForge', 'autoForge', 'Auto forge', 'When you have enough ores: tweens to the forge, puts them in and plays every minigame perfectly.')
bindToggle(UI.forge, 'FTForgeWhenFull', 'forgeWhenFull', 'Only forge when the stash is full', 'With Auto forge on: keeps mining until the stash is full, then forges until the stash is used up before mining again.')
-- The Forge box, kept short: what to make, how to pick the ores, which ores, how many.
do
	local MODES = { 'Traits (30% each)', 'Best stats', 'Most plentiful' }
	if type(settings.forgeWhat) ~= 'string' then
		settings.forgeWhat = settings.forgeType == 'Armor' and 'Armor' or 'Weapon'
	end
	if type(settings.forgeMode) ~= 'string' or not table.find(MODES, settings.forgeMode) then
		settings.forgeMode = MODES[1]
	end
	local function applyForge()
		settings.forgeAlternate = settings.forgeWhat == 'Alternate'
		if settings.forgeWhat ~= 'Alternate' then
			settings.forgeType = settings.forgeWhat
		elseif settings.forgeType ~= 'Armor' then
			settings.forgeType = 'Weapon'
		end
		settings.forgeTraits = settings.forgeMode == MODES[1]
		settings.forgeBest = settings.forgeMode ~= MODES[3]
	end
	applyForge()
	UI.forge:AddDropdown('FTForgeWhat', { Text = 'Make', Values = { 'Weapon', 'Armor', 'Alternate' }, Default = settings.forgeWhat, AllowNull = false,
		Tooltip = 'Alternate = a weapon, then an armor piece, and so on.' }):OnChanged(function(v)
		if type(v) == 'string' then
			settings.forgeWhat = v
			applyForge()
			save()
		end
	end)
	UI.forgeOres:AddDropdown('FTForgeMode', { Text = 'Ore pick', Values = MODES, Default = settings.forgeMode, AllowNull = false,
		Tooltip = 'Traits: up to three trait ores at 30% or more each, so the item gets all their traits at full strength (an ore gives traits from 10% of the mix, full at 30%). Best stats: your strongest ores and the ore count with the best expected item. Most plentiful: uses up whatever you have most of.' }):OnChanged(function(v)
		if type(v) == 'string' then
			settings.forgeMode = v
			applyForge()
			save()
		end
	end)
	if type(settings.forgeOnlyOres) ~= 'table' then
		settings.forgeOnlyOres = type(settings.forgeTraitOres) == 'table' and settings.forgeTraitOres or {}
	end
	local function oreChoices()
		-- what you hold now (trait ores marked), plus anything already picked
		local names, seen = {}, {}
		local d = data()
		for k, v in pairs(d and type(d.Inventory) == 'table' and d.Inventory or {}) do
			if ORE_NAMES[k] and type(v) == 'number' and v > 0 then
				seen[k] = true
				names[#names + 1] = k
			end
		end
		for k in pairs(settings.forgeOnlyOres) do
			if not seen[k] then
				names[#names + 1] = k
			end
		end
		table.sort(names)
		return names
	end
	local onlyDD = UI.forgeOres:AddDropdown('FTForgeOnly', { Text = 'Ores to use', Values = oreChoices(), Multi = true, Default = settings.forgeOnlyOres, AllowNull = true,
		Tooltip = 'Pick ores and the forge uses only those. Nothing picked = any ore you have. The list is the ores in your stash; press "Refresh ore list" after mining new kinds.' })
	onlyDD:OnChanged(function(v)
		local out = {}
		for k, on in pairs(type(v) == 'table' and v or {}) do
			if on then
				out[k] = true
			end
		end
		settings.forgeOnlyOres = out
		save()
	end)
	UI.forgeOres:AddButton('Refresh ore list', function()
		pcall(function()
			onlyDD:SetValues(oreChoices())
		end)
	end)
end
-- Piece target: how many ores go in decides WHICH piece comes out (few = helmets and daggers,
-- many = the heavy pieces). Picking a piece here makes every forge use the ore count with the best
-- odds for it (the game's own odds table), and forges that item's type.
do
	local labels, byLabel, labelOf = { 'Any' }, {}, {}
	pcall(function()
		local rows = {}
		for _, name in ipairs(Piece.names()) do
			local ty = name ~= 'Any' and Piece.typeOf(name)
			if ty then
				local okc, n, ch = pcall(Piece.count, ty, name)
				rows[#rows + 1] = { name = name, ty = ty, n = okc and n or nil, ch = okc and ch or nil }
			end
		end
		table.sort(rows, function(x, y)
			if x.ty ~= y.ty then
				return x.ty < y.ty
			end
			return (x.n or 999) < (y.n or 999)
		end)
		for _, r in ipairs(rows) do
			local label = r.n and ('%s: %s (%d ores, %.0f%%)'):format(r.ty, r.name, r.n, r.ch or 0) or ('%s: %s'):format(r.ty, r.name)
			labels[#labels + 1] = label
			byLabel[label] = r.name
			labelOf[r.name] = label
		end
	end)
	G.FTPieceLabels = labels
	if not labelOf[settings.forgePiece] then
		settings.forgePiece = 'Any'
	end
	UI.forgeOres:AddDropdown('FTForgePiece', { Text = 'Piece target', Values = labels, Default = labelOf[settings.forgePiece] or 'Any', AllowNull = false,
		Tooltip = 'Pick a piece (e.g. Medium Leggings) and every forge uses the ore count that gives it the best chance, shown next to each name with that chance. It also decides weapon or armor while set. It is a chance, not a guarantee: for a guarantee use molds below. "Any" = off.' }):OnChanged(function(v)
		if type(v) == 'string' then
			settings.forgePiece = byLabel[v] or 'Any'
			save()
		end
	end)
end
do
	local labels, byLabel, labelOf = { 'None' }, {}, {}
	pcall(function()
		local E = require(RS.Shared.Data.Equipments)
		local rows = {}
		local function scan(t, depth)
			for k, v in pairs(t) do
				if type(k) == 'string' and type(v) == 'table' then
					local info = Mold.info(k)
					if info then
						rows[#rows + 1] = { name = k, info = info }
					elseif depth < 2 then
						scan(v, depth + 1)
					end
				end
			end
		end
		scan(E, 0)
		table.sort(rows, function(x, y)
			if x.info.kind ~= y.info.kind then
				return x.info.kind > y.info.kind -- weapons first
			end
			return x.name < y.name
		end)
		local seen = {}
		for _, r in ipairs(rows) do
			if not seen[r.name] then
				seen[r.name] = true
				local label = ('%s: %s (%d molds, %d+ ores)'):format(r.info.kind, r.name, r.info.molds, r.info.minOres)
				labels[#labels + 1] = label
				byLabel[label] = r.name
				labelOf[r.name] = label
			end
		end
	end)
	UI.forgeOres:AddDropdown('FTForgeMold', { Text = 'Mold target', Values = labels, Default = labelOf[settings.forgeMold] or 'None', AllowNull = false,
		Tooltip = 'Aims the forge at one item with molds. Only used when you own the full number of molds that guarantees that item (fewer is mostly wasted: half the molds is a quarter of the chance) and when "Make" is its type; the forge then waits for the minimum ore count of that item. Otherwise it forges normally and no molds are spent.' }):OnChanged(function(v)
		if type(v) == 'string' then
			settings.forgeMold = byLabel[v] or 'None'
			save()
		end
	end)
end
bindSlider(UI.forgeOres, 'FTForgeOres', 'forgeOres', 'Ores per forge (max)', 3, 60, 'The most ores one item may use. Left at 3, the smart picks treat it as no limit.')
bindSlider(UI.forgeOres, 'FTForgeMinOres', 'forgeMinOres', 'Ores per forge (min)', 3, 60, 'The fewest ores one item may use. Few ores only ever make the small pieces (helmets, daggers): raise this for chestplates, leggings and big weapons. Trait mode with rare ores you only own 2 of otherwise settles on 6-ore items.')
bindSlider(UI.sellOres, 'FTForgeKeep', 'forgeKeep', 'Keep of each ore (auto sell)', 0, 20, 'With auto forge on, auto sell leaves this many of each ore for forging.')
bindToggle(UI.sellOres, 'FTKeepTraitOres', 'keepTraitOres', 'Keep ores that give traits', 'Ores that give an item a trait are never sold (auto sell and Sell ores now skip them). They can still be used for forging.')
do
	local oreList = {}
	for name in pairs(ORE_NAMES) do
		oreList[#oreList + 1] = name
	end
	table.sort(oreList)
	if type(settings.keepOres) ~= 'table' then
		settings.keepOres = {}
	end
	local keepDD = UI.sellOres:AddDropdown('FTKeepOres', { Text = 'Save these ores (never sell / forge)', Values = oreList, Multi = true, Searchable = true, Default = settings.keepOres, AllowNull = true, Tooltip = 'Picked ores are kept: auto sell and auto forge leave them alone (e.g. Galgite, Heavenite).' })
	keepDD:OnChanged(function(v)
		local out = {}
		for k, on in pairs(type(v) == 'table' and v or {}) do
			if on then
				out[k] = true
			end
		end
		settings.keepOres = out
		save()
	end)
end
UI.forge:AddButton('Forge now', function()
	forgeOnce()
end)

bindToggle(UI.mobs, 'FTAutoMobs', 'autoMobs', 'Auto kill mobs', 'Tweens to the nearest mob and fights it with your Weapon.')
pcall(function()
	local names = {}
	pcall(function()
		for name in pairs(require(RS.Shared.Data.Mutations).Mutations) do
			names[#names + 1] = name
		end
	end)
	if #names == 0 then
		names = { 'Heaven', 'Hell', 'Limbo', 'Lucky', 'Ancient', 'Chaotic', 'Giant', 'Golden' }
	end
	table.sort(names)
	if type(settings.huntSpecial) ~= 'table' then
		settings.huntSpecial = {}
	end
	UI.mobs:AddDropdown('FTHuntSpecial', { Text = 'Hunt special enemies', Values = names, Multi = true, Default = (function() local d = {} for k, on in pairs(settings.huntSpecial) do if on == true then d[#d + 1] = k end end return d end)(), AllowNull = true,
		Tooltip = 'Enemies with one of these modifiers (Heaven, Hell, Lucky...) are fought first, wherever they are on the map, before quests and farming. Works without "Auto kill mobs". Nothing picked = off.' }):OnChanged(function(v)
		local out = {}
		for k, on in pairs(type(v) == 'table' and v or {}) do
			if on then
				out[k] = true
			end
		end
		settings.huntSpecial = out
		save()
	end)
end)
local mobDD = bindDropdown(UI.mobs, 'FTMobFilter', 'mobFilter', 'Target', mobNames())
bindSlider(UI.health, 'FTKiteHp', 'kiteHp', 'Back off below % health', 0, 90, 'Below this the fight stops and it keeps its distance from every mob until health is back at the heal-to value (at least 25% above this). Works in raids too. 0 = off.')
bindSlider(UI.health, 'FTRetreatHp', 'retreatHp', 'Retreat to spawn below % health', 0, 90, 'Below this it stops to heal (health comes back about 1% a second). 0 = never stop to heal, keep working.')
bindSlider(UI.health, 'FTHealTo', 'healTo', 'Back to work at % health', 5, 100, 'How far it heals before it carries on. Lower = less standing around, more risk.')
-- The slider used to stop at 2000, which silently hid every bigger mob (island 3: Elite Orc,
-- Crystal Golem, Yeti, Demonic / Prismarine Spider...). Left at that old maximum = no limit.
if tonumber(settings.maxMobHp) == 2000 then
	settings.maxMobHp = 0
end
bindSlider(UI.mobs, 'FTMaxMobHp', 'maxMobHp', 'Only fight mobs with max HP up to', 0, 20000, '0 = any mob. Mobs above this are ignored completely (not fought, not in quests).')
-- (a safety setting, not a feature toggle: it keeps its saved value across loads, default on)
settings.fleeDeadly = settings.fleeDeadly ~= false
UI.mobs:AddToggle('FTFleeDeadly', { Text = 'Avoid mobs that killed me', Default = settings.fleeDeadly, Tooltip = 'Any mob type that kills you, or takes about half your health in one hit, goes on a list. The script then never fights that type, skips rocks near it and moves away when one comes close. Turn off (or use the button below) once your gear is better.' }):OnChanged(function(v)
	settings.fleeDeadly = v == true
	save()
end)
UI.mobs:AddButton('Forget deadly mobs', function()
	local was = table.concat(Deadly.list(), ', ')
	Deadly.clear()
	setStatus('deadly list cleared' .. (was ~= '' and (' (was: ' .. was .. ')') or ''))
end)
bindDropdown(UI.defense, 'FTDodgeWhat', 'dodgeWhat', 'Dodge', { 'Only threats', 'Everything', 'Low health only' }, 'Low health only: no stepping out of attacks, markers or shots - parries only - except the back-off below "Back off below % health". Only threats: a mob\'s attacks are only dodged once that kind has hurt you for real - one hit of 25% of your health or more, or damage faster than you heal it back (both measured as you fight). When you drop under 45% health, or lose 12% more than you heal within 8 seconds, everything is dodged until you are back over 85%. Everything: every attack is dodged, as before.')
bindDropdown(UI.defense, 'FTCombatStyle', 'combatStyle', 'Combat style', { 'Hit & run', 'Behind + dodge', 'Block / parry', 'Attack only', 'Face tank' }, "Hit & run: steps out of reach right before each attack lands, then comes back in to hit. Behind + dodge: the same, but always comes back in at the mob's back. Block / parry: stands behind the mob and blocks. Attack only: stands behind the mob and swings, never dodges or blocks. Face tank: walks straight up to the mob's face and swings, never moves round it, dodges or blocks (stuns will land). The island boss is always parried in Attack only / Face tank. (Floating over mobs was tested: their attacks reach straight up, so it is not offered.)")
bindSlider(UI.defense, 'FTDodgeDist', 'dodgeDist', 'Dodge distance (studs)', 8, 30, 'How far it steps away from an incoming attack.')
bindToggle(UI.abyss, 'FTAutoAbyss', 'autoAbyss', 'Auto Abyss', 'Goes to the Abyss cage, starts a run, picks a card each floor (see below) and fights every floor. Re-enters when you come back.')
bindToggle(UI.boss, 'FTAutoBoss', 'autoBoss', 'Auto boss (this island)', 'UNTESTED. Goes to this island\'s boss gate (Island 4: Asura\'s Incarnate), opens a party, starts it when the lobby opens and fights the boss. Boss lobbies are free (no ticket). Ignores the max mob health slider. Tries once right away, then each time the gate countdown runs out; gives up for 30 minutes after 3 starts in a row that do not go through.')
bindSlider(UI.raids, 'FTRaidTier', 'raidTier', 'Raid tier', 1, 15, 'The Tower of Hell tier the button below starts.')
bindSlider(UI.raids, 'FTRaidRetries', 'raidRetries', 'Raid retries left (1 ticket each)', 0, 10, 'When a raid ends, the Retry button is pressed this many more times. Each press starts another raid and spends one Raid Ticket; the number counts down by itself. 0 = never press it.')
bindToggle(UI.raids, 'FTAutoRaid', 'autoRaid', 'Auto raid (spends Raid Tickets)', 'Starts a Tower of Hell raid at the tier above whenever you have a Raid Ticket, and presses Retry while tickets last. Out of tickets: farms Asura\'s Incarnate (1 ticket per kill) and mines between spawns until you are back to the number below, then raids again.')
bindSlider(UI.raids, 'FTRaidTicketMax', 'raidTicketMax', 'Raid tickets to farm back to', 1, 20, 'With Auto raid on and no tickets left, Asura is farmed until you have this many again.')
UI.raids:AddButton('Start ONE raid (spends 1 Raid Ticket)', function()
	G.FTRaidStart = { tier = tonumber(settings.raidTier) or 1 }
end)
UI.combatMisc:AddButton('Weapon DPS test (dummies)', function()
	G.FTDpsTest = true
end)
bindToggle(UI.abyss, 'FTAutoCards', 'autoCards', 'Auto pick abyss cards', 'Picks a card for you after each floor, even when you play the Abyss yourself.')
bindDropdown(UI.abyss, 'FTCardFocus', 'cardFocus', 'Card priority', { 'Best overall', 'Damage', 'Survival', 'Loot' }, 'Best overall: rarest card (Abyssal > Fusion > Epic > Rare > Common). Damage / Survival / Loot: that kind of card first, then rarity.')
bindToggle(UI.defense, 'FTAutoBlock', 'autoBlock', 'Auto block (F)', 'Blocks right before a mob\'s attack lands, then goes back to swinging.')
if (tonumber(settings.parryShineLead) or 0) == 8 then
	settings.parryShineLead = 0 -- (v190-v191 default: before the shine, which only ever gave a plain block)
end
bindSlider(UI.defense, 'FTParryShineLead', 'parryShineLead', 'Parry delay (x10 ms after the shine)', 0, 30, 'The block is pressed when the parry shine appears on the mob. 0 = that instant, which measured as a real parry. Raise it only if you see plain blocks (stamina lost, some damage) instead of the orange parry.')
bindSlider(UI.mobs, 'FTSwitchMins', 'switchMins', 'With auto mine on, switch every (min)', 1, 15, 'Mobs and mining take turns so you still get ores to forge with.')
local QuestBox = UI.quests

-- Race reroll: spends spins on the current race slot until the race is at least the rarity picked.
-- A button, not a toggle: every roll replaces your race and cannot be undone.
do
	local RaceBox = UI.race
	local ORDER = { 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic', 'Relic', 'Exotic', 'Divine' }
	local rank = {}
	for i, n in ipairs(ORDER) do
		rank[n] = i
	end
	local function raceInfo()
		local d = data()
		local name = d and d.Race
		local rarity
		pcall(function()
			local R = require(RS.Shared.Data.Races)
			for i, n in ipairs(R.RarityOrder or {}) do
				rank[n] = rank[n] or i
			end
			rarity = R.Races[name] and R.Races[name].Rarity
		end)
		return name, rarity, d and tonumber(d.Spins) or 0
	end
	bindDropdown(RaceBox, 'FTRaceStop', 'raceStop', 'Stop at rarity (or better)', { 'Rare', 'Epic', 'Legendary', 'Mythic', 'Relic', 'Exotic', 'Divine' }, 'Rerolling stops as soon as your race is this rarity or better. If it already is, nothing is rolled.')
	-- Specific races: with any picked here, rolling stops on one of THOSE and the rarity above is ignored.
	pcall(function()
		local names, rr = {}, {}
		pcall(function()
			local R = require(RS.Shared.Data.Races)
			for i, n in ipairs(R.RarityOrder or {}) do
				rank[n] = rank[n] or i
			end
			for name, def in pairs(R.Races) do
				if type(def) == 'table' then
					names[#names + 1] = name
					rr[name] = rank[def.Rarity] or 0
				end
			end
		end)
		for name in pairs(type(settings.raceWant) == 'table' and settings.raceWant or {}) do
			if rr[name] == nil then
				names[#names + 1] = name
				rr[name] = 0
			end
		end
		table.sort(names, function(a, b)
			if rr[a] ~= rr[b] then
				return rr[a] > rr[b]
			end
			return a < b
		end)
		local dd = RaceBox:AddDropdown('FTRaceWant', { Text = 'Stop at these races', Values = names, Multi = true, Default = settings.raceWant, AllowNull = true,
			Tooltip = 'Pick one or more races: rolling goes on until you have one of them, whatever its rarity, and the rarity setting above is ignored. Nothing picked = stop by rarity. Listed rarest first.' })
		dd:OnChanged(function(v)
			local out = {}
			for k, on in pairs(type(v) == 'table' and v or {}) do
				if on then
					out[k] = true
				end
			end
			settings.raceWant = out
			save()
		end)
	end)
	bindSlider(RaceBox, 'FTRaceKeepSpins', 'raceKeepSpins', 'Keep this many spins', 0, 200, 'Rerolling also stops when only this many spins are left.')
	local rolling = false
	RaceBox:AddButton('Reroll race', function()
		if rolling then
			rolling = false -- pressed again: stop
			return
		end
		rolling = true
		task.spawn(function()
			local want = rank[settings.raceStop] or rank.Legendary
			local keep = math.max(0, tonumber(settings.raceKeepSpins) or 0)
			local used, fails = 0, 0
			local svc = service('RaceService')
			local banner
			pcall(function()
				local B = require(RS.Shared.Data.RaceBanners)
				local active = B:GetActive()
				banner = active and active.Id or B.Standard.Id
			end)
			local Races
			pcall(function()
				Races = require(RS.Shared.Data.Races).Races
			end)
			-- is this race one to stop on?
			local function wanted(name)
				local picks = type(settings.raceWant) == 'table' and next(settings.raceWant) and settings.raceWant or nil
				if picks then
					return name ~= nil and picks[name] == true
				end
				local def = Races and name and Races[name]
				return (rank[type(def) == 'table' and def.Rarity or ''] or 0) >= want
			end
			-- the race the server's own answer to the roll names, if it names one
			local function raceFrom(r)
				if not Races then
					return nil
				end
				if type(r) == 'string' then
					return Races[r] and r or nil
				end
				if type(r) == 'table' then
					for _, k in ipairs({ 'Race', 'NewRace', 'Result', 'Name', 'race', 'name', 'result' }) do
						if type(r[k]) == 'string' and Races[r[k]] then
							return r[k]
						end
					end
					for _, v in pairs(r) do
						if type(v) == 'string' and Races[v] then
							return v
						end
					end
				end
				return nil
			end
			while alive and rolling do
				local name, rarity, spins = raceInfo()
				local done = wanted(name)
				if done then
					setStatus(('race reroll: you have %s (%s) — done, %d spins used, %d left'):format(tostring(name), tostring(rarity), used, spins))
					break
				end
				if spins <= keep then
					setStatus(('race reroll: stopped at %d spins left — race is %s (%s), %d spins used'):format(spins, tostring(name), tostring(rarity), used))
					break
				end
				if not svc then
					setStatus('race reroll: race service not found')
					break
				end
				-- (v232, the user: "the race reroll skipped demon". The game keeps its own list of race
				-- changes (RaceLog: from, new, time). When the roll's answer names no race, the new entry
				-- in that list says what was rolled, before the next roll can go out. Every roll is also
				-- written to PlayerTools/forgetools_racerolls.txt.)
				local function logNewest()
					local d0 = data()
					local best
					for _, e in pairs(d0 and type(d0.RaceLog) == 'table' and d0.RaceLog or {}) do
						if type(e) == 'table' and type(e.T) == 'number' and (not best or e.T > best.T) then
							best = e
						end
					end
					return best
				end
				local log0 = logNewest()
				local ok, got = pcall(function()
					local _, r = svc:Reroll(banner):await()
					return r
				end)
				if ok and got then
					used += 1
					fails = 0
					local viaLog
					if not raceFrom(got) then
						local tl = os.clock()
						while os.clock() - tl < 3 do
							local e = logNewest()
							if e and e ~= log0 and (not log0 or e.T >= log0.T) and e.F == name and type(e.N) == 'string' and Races and Races[e.N] then
								viaLog = e.N
								break
							end
							task.wait(0.05)
						end
						if viaLog then
							got = viaLog
						end
					end
					pcall(function()
						local ans = type(got) == 'table' and HttpService:JSONEncode(got) or tostring(got)
						local wf = isfile('PlayerTools/forgetools_racerolls.txt') and appendfile or writefile; wf('PlayerTools/forgetools_racerolls.txt', ('%s roll %d from %s: answer %s%s\n'):format(os.date('%m-%d %H:%M:%S'), used, tostring(name), string.sub(ans, 1, 200), viaLog and ' (from the game log)' or ''))
					end)
					-- It used to wait (2s at most) for the spin count to drop and then read the race: the
					-- race arrives in a separate update, so the next round could still see the OLD race and
					-- roll straight over the one it was meant to stop on. Now: the server's own answer
					-- decides first, and nothing is rolled again until our data is confirmed.
					local told = raceFrom(got)
					if told and wanted(told) then
						setStatus(('race reroll: rolled %s — done, %d spins used'):format(told, used))
						break
					end
					local t0 = os.clock()
					local n2, r2, s2 = raceInfo()
					while os.clock() - t0 < 8 and (s2 == spins or (told and n2 ~= told)) do
						task.wait(0.1)
						n2, r2, s2 = raceInfo()
					end
					if not told then
						-- no race in the answer: the race we read must hold still before it is trusted
						local same = os.clock()
						while os.clock() - same < 2.5 do -- (v232: was 1 s)
							task.wait(0.1)
							local n3 = raceInfo()
							if n3 ~= n2 then
								n2, same = n3, os.clock()
							end
						end
						n2, r2, s2 = raceInfo()
					end
					setStatus(('race reroll #%d: %s (%s) — %d spins left'):format(used, tostring(n2), tostring(r2), s2))
					pcall(function()
						local wf = isfile('PlayerTools/forgetools_racerolls.txt') and appendfile or writefile; wf('PlayerTools/forgetools_racerolls.txt', ('%s   -> data says %s (%s), %d spins left\n'):format(os.date('%m-%d %H:%M:%S'), tostring(n2), tostring(r2), s2))
					end)
					if s2 == spins or (told and n2 ~= told) then
						setStatus(('race reroll: could not confirm roll #%d (answer %s, data %s) — stopped so nothing gets rolled over. Check your race, then press again.'):format(used, tostring(told), tostring(n2)))
						break
					end
					task.wait(0.2)
				else
					fails += 1
					if fails >= 3 then
						setStatus('race reroll: the game refused the roll 3 times — stopped (' .. tostring(got):sub(1, 60) .. ')')
						break
					end
					task.wait(1.5)
				end
			end
			rolling = false
		end)
	end)
	RaceBox:AddLabel('Press again to stop. Rolls the current slot.', true)

	-- Race swap: the game lets you change race slot from anywhere, at once (measured: 0.4s, no
	-- cooldown, health kept). Costs nothing - it only picks which of the races you own is active.
	do
		local function slots()
			local d = data()
			return d and type(d.RaceSlots) == 'table' and d.RaceSlots or {}, d and d.CurrentRaceSlot
		end
		local function switchTo(i)
			local list, cur = slots()
			if rolling or not list[i] or cur == i then
				return false
			end
			local svc = service('RaceService')
			if not svc then
				return false
			end
			local ok = pcall(function()
				svc:SwitchSlot(i)
			end)
			return ok
		end
		local function slotOf(name)
			for i, n in pairs((slots())) do
				if n == name then
					return i
				end
			end
		end
		local vals = { 'No change' }
		do
			local seen = {}
			local list = slots()
			for i = 1, 8 do
				local n = list[i]
				if n and not seen[n] then
					seen[n] = true
					vals[#vals + 1] = n
				end
			end
			for _, k in ipairs({ 'raceMine', 'raceFight' }) do
				if type(settings[k]) ~= 'string' or (settings[k] ~= 'No change' and not seen[settings[k]]) then
					settings[k] = 'No change' -- (a race no longer in any slot)
				end
			end
		end
		G.FTSettings = settings -- (for live tests)
		G.FTBest = Best
		G.FTMold = Mold
		local SwapBox = UI.swap
		bindDropdown(SwapBox, 'FTRaceMine', 'raceMine', 'Race while mining', vals, 'Switches to this race (one of your slots) whenever the bot is mining. Free and instant.')
		bindDropdown(SwapBox, 'FTRaceFight', 'raceFight', 'Race while fighting', vals, 'Switches to this race whenever the bot is fighting or dodging a mob, and back to the mining one afterwards.')
		SwapBox:AddButton('Switch to next race slot', function()
			local list, cur = slots()
			local n = 0
			for i in pairs(list) do
				n = math.max(n, i)
			end
			for step = 1, n do
				local i = ((cur or 1) - 1 + step) % n + 1
				if list[i] then
					if switchTo(i) then
						setStatus(('race: switched to %s (slot %d)'):format(tostring(list[i]), i))
					end
					break
				end
			end
		end)
		SwapBox:AddLabel('Paused while a reroll is running. Reload after getting a new race to see it listed.', true)
		local FIGHT = { 'fighting ', 'dodging ', 'dodged a', 'finishing ', 'clearing ' }
		task.spawn(function()
			local mineSince
			while alive do
				task.wait(0.4)
				local st = tostring(G.FTStatus)
				local mode
				if string.sub(st, 1, 7) == 'mining ' then
					mode = 'mine'
				else
					for _, pre in ipairs(FIGHT) do
						if string.sub(st, 1, #pre) == pre then
							mode = 'fight'
							break
						end
					end
				end
				local want
				if mode == 'fight' then
					mineSince = nil
					want = settings.raceFight
				elseif mode == 'mine' then
					-- (a second of mining first: the status flips between the two around a fight)
					mineSince = mineSince or os.clock()
					if os.clock() - mineSince >= 1.5 then
						want = settings.raceMine
					end
				else
					mineSince = nil
				end
				if want and want ~= 'No change' and not rolling then
					local i = slotOf(want)
					local _, cur = slots()
					if i and cur ~= i then
						pcall(switchTo, i)
						task.wait(0.6)
					end
				end
			end
		end)
	end
end
-- Runes onto gear, from anywhere (the Runemaker's own calls answer at any distance: measured, a
-- price came back from 335 studs). Attaching costs gold and uses the rune up, so it only ever
-- happens on a button press. The lists follow the inventory by themselves and the choice stays
-- put after an attach, so several runes can go on one piece press after press.
do
	local RuneBox = UI.runes
	local gearMap, runeMap = {}, {} -- label -> gear id / label -> rune kind
	local runeGuid = {} -- rune kind -> one GUID of it
	local gearId, runeKind
	local function gearList()
		local names, seen = {}, {}
		table.clear(gearMap)
		local d = data()
		for _, e in pairs(d and d.Inventory and d.Inventory.Equipments or {}) do
			-- (pickaxes have no GUID: the game knows them by name)
			local id = type(e) == 'table' and (e.GUID or e.Name)
			if id and type(e.Runes) == 'table' and #e.Runes > 0 then
				local free = 0
				for _, r in ipairs(e.Runes) do
					if type(r) == 'table' and r.IsEmpty then
						free += 1
					end
				end
				local label = e.GUID and ('%s +%d (%d of %d free)'):format(tostring(e.Type), tonumber(e.Upgrade) or 0, free, #e.Runes)
					or ('%s (%d of %d free)'):format(tostring(e.Name), free, #e.Runes)
				local base, i = label, 1
				while seen[label] do
					i += 1
					label = base .. ' #' .. i
				end
				seen[label] = true
				gearMap[label] = id
				names[#names + 1] = label
			end
		end
		table.sort(names)
		return names
	end
	local function runeList()
		local names, count = {}, {}
		table.clear(runeMap)
		table.clear(runeGuid)
		local d = data()
		local okR, R = pcall(function()
			return require(RS.Shared.Data.Runes).Runes
		end)
		for _, it in pairs(d and d.Inventory and d.Inventory.Misc or {}) do
			local def = okR and type(it) == 'table' and it.GUID and it.Id and R[it.Id]
			if def then
				local n = tostring(def.Name or it.Id)
				count[n] = (count[n] or 0) + 1
				runeGuid[n] = runeGuid[n] or it.GUID
			end
		end
		for n, c in pairs(count) do
			local label = ('%s (x%d)'):format(n, c)
			runeMap[label] = n
			names[#names + 1] = label
		end
		table.sort(names)
		return names
	end
	local gearDD = RuneBox:AddDropdown('FTRuneGear', { Text = 'Gear', Values = gearList(), Multi = false, AllowNull = true })
	local runeDD = RuneBox:AddDropdown('FTRuneRune', { Text = 'Rune', Values = runeList(), Multi = false, AllowNull = true })
	local syncing = false
	gearDD:OnChanged(function(v)
		if not syncing then
			gearId = type(v) == 'string' and gearMap[v] or nil
		end
	end)
	runeDD:OnChanged(function(v)
		if not syncing then
			runeKind = type(v) == 'string' and runeMap[v] or nil
		end
	end)
	-- Rebuild both lists and put the choice back on the same piece / same kind of rune (their
	-- labels change with every attach: "2 of 2 free" becomes "1 of 2 free", "x4" becomes "x3").
	local lastKey
	local function sync(force)
		local g, r = gearList(), runeList()
		local key = table.concat(g, '|') .. '//' .. table.concat(r, '|')
		if key == lastKey and not force then
			return
		end
		lastKey = key
		syncing = true
		pcall(function()
			gearDD:SetValues(g)
			runeDD:SetValues(r)
			local gl, rl
			for label, id in pairs(gearMap) do
				if id == gearId then
					gl = label
				end
			end
			for label, kind in pairs(runeMap) do
				if kind == runeKind then
					rl = label
				end
			end
			gearDD:SetValue(gl)
			runeDD:SetValue(rl)
			if not gl then
				gearId = nil
			end
			if not rl then
				runeKind = nil -- (that was the last one of its kind)
			end
		end)
		syncing = false
	end
	task.spawn(function()
		while alive and G.SB2ForgeToolsToken == nil do
			task.wait(0.5)
		end
		local mine = G.SB2ForgeToolsToken
		while alive and G.SB2ForgeToolsToken == mine do
			task.wait(1)
			pcall(sync)
		end
	end)
	bindToggle(RuneBox, 'FTRuneAsk', 'runeAskPrice', 'Show the price first (press twice)', 'On: the first press only shows what the attach costs, the second does it. Off: one press attaches straight away, and the price paid is shown after.')
	local armed = { key = nil, at = 0 }
	local busy = false
	RuneBox:AddButton('Attach rune', function()
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			pcall(function()
				pcall(sync)
				local eg, kind = gearId, runeKind
				local rg = kind and runeGuid[kind]
				if not eg or not rg then
					setStatus('runes: pick a piece of gear and a rune first')
					return
				end
				local svc = service('RuneService')
				if not svc then
					setStatus('runes: rune service not found')
					return
				end
				local price
				pcall(function()
					local _, v = svc:GetPriceInfo(eg, rg, 'Attach'):await()
					price = v
				end)
				if type(price) ~= 'number' then
					armed.key = nil
					setStatus(('runes: %s cannot go on that item (the game gave no price)'):format(tostring(kind)))
					return
				end
				local key = tostring(eg) .. kind
				if settings.runeAskPrice and (armed.key ~= key or os.clock() - armed.at > 15) then
					armed.key, armed.at = key, os.clock()
					setStatus(('runes: %s costs %d gold to attach — press again within 15s'):format(kind, price))
					return
				end
				armed.at = os.clock() -- (same piece, same kind: the next press goes straight through)
				local okA, got = pcall(function()
					local _, v = svc:PurchaseAttach(eg, rg):await()
					return v
				end)
				if okA and got then
					setStatus(('runes: attached %s for %d gold'):format(kind, price))
				else
					setStatus('runes: the game refused the attach (' .. tostring(got):sub(1, 60) .. ')')
				end
				-- the inventory catches up a moment later: wait for that rune to be gone
				local t0 = os.clock()
				while os.clock() - t0 < 2 do
					runeList()
					if runeGuid[kind] ~= rg then
						break
					end
					task.wait(0.1)
				end
				pcall(sync, true)
			end)
			busy = false
		end)
	end)
	RuneBox:AddLabel('Costs gold and uses the rune. Lists update by themselves.', true)
end
bindToggle(QuestBox, 'FTAutoAccept', 'autoAcceptQuests', 'Auto accept quests', 'Visits NPCs and takes any quest they offer (repeatable ones again when they come back).')
bindToggle(QuestBox, 'FTAutoComplete', 'autoCompleteQuests', 'Auto complete quests', 'Works the objectives (forge, sell, equip, talk, kill, mine, buy) and turns quests in at the NPC.')
-- Quest tracker: pick the quest to focus on (it goes first and decides mine vs mobs).
local QuestDataUI
pcall(function()
	QuestDataUI = require(RS.Shared.Data.Quests)
end)
local function questLabel(id)
	local q = QuestDataUI and QuestDataUI[id]
	return tostring(q and q.Name or id)
end
local focusMap = {}
local function focusValues()
	local out = { 'Auto' }
	focusMap = { Auto = 'Auto' }
	local d = data()
	local ids = {}
	for id in pairs(d and d.Quests or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		return questLabel(a) < questLabel(b)
	end)
	for _, id in ipairs(ids) do
		local name = questLabel(id)
		if focusMap[name] then
			name = name .. ' (' .. id .. ')'
		end
		focusMap[name] = id
		out[#out + 1] = name
	end
	return out
end
local focusList = focusValues()
local focusDefault = 'Auto'
for name, id in pairs(focusMap) do
	if id == settings.focusQuest then
		focusDefault = name
	end
end
local focusDD = QuestBox:AddDropdown('FTFocusQuest', { Text = 'Focus quest', Values = focusList, Default = focusDefault, AllowNull = false, Tooltip = 'Auto complete works this quest first. Auto = one-time quests before repeatable ones.' })
focusDD:OnChanged(function(v)
	if type(v) == 'table' then
		v = next(v)
	end
	if v ~= nil and focusMap[v] then
		settings.focusQuest = focusMap[v]
		save()
	end
end)
local trackerLabel = QuestBox:AddLabel('Tracking: -')
task.spawn(function()
	local lastSig
	while alive do
		pcall(function()
			local d = data()
			local quests = d and d.Quests or {}
			-- refresh the dropdown when quests come and go
			local ids = {}
			for id in pairs(quests) do
				ids[#ids + 1] = id
			end
			table.sort(ids)
			local sig = table.concat(ids, ',')
			if sig ~= lastSig then
				lastSig = sig
				focusDD:SetValues(focusValues())
			end
			local id = settings.focusQuest
			if id == 'Auto' or not quests[id] then
				trackerLabel:SetText(id ~= 'Auto' and 'Tracking: quest finished (back to Auto)' or 'Tracking: Auto')
				return
			end
			local lines = { 'Tracking: ' .. questLabel(id) }
			for _, pr in ipairs(quests[id].Progress or {}) do
				lines[#lines + 1] = ('  %s %s  %s/%s'):format(tostring(pr.questType), tostring(pr.target),
					tostring(pr.currentProgress or 0), tostring(pr.requiredAmount or 1))
			end
			trackerLabel:SetText(table.concat(lines, '\n'))
		end)
		task.wait(2)
	end
end)
bindToggle(QuestBox, 'FTQuestBuy', 'questBuy', 'Buy quest items with gold', 'For "Purchase X" objectives (e.g. Bronze Pickaxe). In-game gold only, then equips the better pickaxe.')
bindToggle(UI.shop, 'FTAutoPickaxe', 'autoPickaxe', 'Auto buy best pickaxe', 'Buys the best pickaxe sold on your current island that you can afford and do not own (gold only, skips locked ones), then equips it.')
UI.shop:AddButton('Buy best pickaxe now', function()
	task.spawn(function()
		local ok, bought = pcall(Quest.buyBestPickaxe)
		if ok and not bought then
			setStatus('no better pickaxe to buy on this island right now')
		end
	end)
end)
bindToggle(UI.rewards, 'FTClaimBoard', 'claimBoard', 'Claim quest board rewards', 'Claims finished Daily / Weekly / Monthly board quests.')
bindSlider(QuestBox, 'FTQuestRange', 'questRange', 'Look for new quests within (studs)', 200, 5000, 'NPCs farther than this are not visited just to check for quests (quest turn-ins and talk objectives still go anywhere).')
bindToggle(UI.rewards, 'FTAutoMail', 'autoMail', 'Auto claim mail & rewards', 'Every minute: claims all mail, level rewards, index (codex) rewards, and free seasonal-event rewards (event quests, milestones, altar daily).')
bindToggle(UI.rewards, 'FTAutoOffer', 'autoOffer', 'Auto offer altar shards', 'Twilight War altar: spends your side\'s shards on offers (x10 while you can, then x1) and takes the free daily gifts.')
bindToggle(UI.rewards, 'FTAutoDaily', 'autoDaily', 'Auto claim daily login', 'Claims the daily login reward when it is ready.')
bindToggle(UI.rewards, 'FTAutoCodes', 'autoCodes', 'Auto redeem codes', 'Reads the working codes from theforge.gg every 15 minutes and redeems any you have not used. A tracker can be hours behind the game\'s Discord: a brand new code can also go in PlayerTools/forgecodes.txt (one per line).')
bindToggle(UI.enhance, 'FTAutoEnhance', 'autoEnhance', 'Auto enhance equipped gear', 'Spends essences and gold to enhance the weapon and armor you are wearing, one level at a time. A failed enhance drops the item a level and can cost a rune slot; use the chance slider below to only take safer rolls. Never uses medallions.')
-- The limit used to default to 100%, which stopped every item at +3 (+3 -> +4 is a 70% roll).
-- No limit by default now; whatever was saved before (the slider could not go under 50) is
-- cleared once.
if not settings.enhanceNoLimitV2 then
	settings.enhanceNoLimitV2 = true
	settings.enhanceMinChance = 0
	save()
end
bindSlider(UI.enhance, 'FTEnhanceMinChance', 'enhanceMinChance', 'Only enhance at this chance or better (%)', 0, 100, '0 = no limit: keeps trying whatever the odds. At 100 an enhance can never fail, which stops at +3.')
bindSlider(UI.enhance, 'FTEnhanceMaxLevel', 'enhanceMaxLevel', 'Stop enhancing at +', 1, 9, 'Items already at this level are left alone.')
bindToggle(UI.enhance, 'FTAutoEquip', 'autoEquip', 'Auto equip better gear', 'After forging, equips the item if its slot is empty or its base stats beat what you have on. Enhancement levels are ignored, so a better new piece replaces an upgraded old one.')
bindToggle(UI.recycle, 'FTAutoRecycle', 'autoRecycle', 'Auto recycle forged gear', 'Spare gear (the same picks as auto sell gear: never what you wear, the best item of each slot, favorited items or pickaxes) is recycled for ores instead of sold. Costs gold equal to the items\' sell price and gives back half the ores that went in. Runs before auto sell gear.')
UI.recycle:AddLabel('Costs gold (the items\' sell price). Gives back half the ores.', true)
UI.mobs:AddButton('Refresh lists', function()
	pcall(function()
		mobDD:SetValues(mobNames())
	end)
	pcall(function()
		zoneDD:SetValues(zoneNames())
	end)
	pcall(function()
		rockDD:SetValues(rockNames())
	end)
end)

-- Island travel (same thing the Portal tool does). Lists islands and whether you've unlocked them.
do
	local IslandsMod
	pcall(function()
		IslandsMod = require(RS.Shared.Data.Islands)
	end)
	local function islandList()
		local out = {}
		for _, isl in ipairs(IslandsMod and IslandsMod.Data or {}) do
			local ok, st = pcall(IslandsMod.GetRequirementStatus, isl.Name, data())
			local open = ok and type(st) == 'table' and st.AllMet
			out[#out + 1] = isl.Name .. (open and '' or ' (locked)')
		end
		return out
	end
	local list = islandList()
	local dd = UI.travel:AddDropdown('FTIsland', { Text = 'Travel to island', Values = list, Default = list[2] or list[1], AllowNull = false })
	UI.travel:AddButton('Travel', function()
		local v = dd.Value
		if type(v) == 'table' then
			v = next(v)
		end
		v = tostring(v or ''):gsub(' %(locked%)$', '')
		local ok, st = pcall(IslandsMod.GetRequirementStatus, v, data())
		if ok and type(st) == 'table' and not st.AllMet then
			local need = {}
			for _, r in ipairs(st.Requirements or {}) do
				if not r.Met then
					need[#need + 1] = tostring(r.DisplayText)
				end
			end
			setStatus(v .. ' is locked: ' .. table.concat(need, ', '))
			return
		end
		setStatus('travelling to ' .. v .. '…')
		task.spawn(function()
			local okT, a, b = pcall(function()
				return service('PortalService'):TeleportToIsland(v):await()
			end)
			if not okT or a == false then
				setStatus('travel failed: ' .. tostring(b or a))
			end
		end)
	end)
end

statusLabel = UI.status:AddLabel('Status: idle')
local statsLabel = UI.status:AddLabel('')
bindToggle(UI.script, 'FTNoBlur', 'noBlur', 'No blur', 'Keeps the game\'s blur effects (forge / menus / dialogue) switched off.')
bindSlider(UI.move, 'FTTweenSpeed', 'tweenSpeed', 'Tween speed (studs/s)', 20, 120, 'Too fast can get you snapped back.')
bindSlider(UI.move, 'FTWalkSpeed', 'walkSpeed', 'Walk speed while pathing (0 = game default)', 0, 150, 'Speed used when the script walks around walls. The game walks at 13 and runs at 24.')
UI.script:AddToggle('FTAutoload', { Text = 'Autoload on this account', Default = settings.autoload == true }):OnChanged(function(v)
	settings.autoload = v == true
	save()
end)

---------------------------------------------------------------------------
-- Main loop: forge > sell > mobs > mine
---------------------------------------------------------------------------
local token = {}
local lastQuestStep = 0
G.SB2ForgeToolsToken = token

-- Anti blur: keep every blur effect at 0 (forge screen, menus, dialogue depth of field).
task.spawn(function()
	local L = game:GetService('Lighting')
	while alive and G.SB2ForgeToolsToken == token do
		if settings.noBlur then
			for _, x in ipairs(L:GetChildren()) do
				if x:IsA('BlurEffect') and x.Size > 0 then
					x.Size = 0
				elseif x:IsA('DepthOfFieldEffect') and x.Name == 'DialogueDOF' then
					x.Enabled = false
				end
			end
			pcall(function()
				for _, x in ipairs(workspace.CurrentCamera:GetChildren()) do
					if x:IsA('BlurEffect') and x.Size > 0 then
						x.Size = 0
					end
				end
			end)
		end
		task.wait(0.3)
	end
end)

-- Forge watchdog: if a forge sits at the hammer step with an unbroken mould (a resumed forge,
-- or one started before a reload), click the mould open; also make sure the minigames are hooked.
task.spawn(function()
	local since
	while alive and G.SB2ForgeToolsToken == token do
		pcall(function()
			local FC = controller('ForgeController')
			if FC and FC.ForgeActive then
				hookMinigames(FC)
			end
			local mold = workspace:FindFirstChild('Debris') and workspace.Debris:FindFirstChild('Mold')
			if FC and FC.ForgeActive and FC.Sequence == 'Hammer' and mold and mold:GetAttribute('IsDestroyed') ~= true then
				since = since or os.clock()
				if os.clock() - since > 3 then
					local cd = mold:FindFirstChild('ClickDetector')
					if cd then
						for _, c in ipairs(getconnections(cd.MouseClick)) do
							c:Fire()
						end
					end
				end
			else
				since = nil
			end
		end)
		task.wait(0.4)
	end
end)
local loopGen = 0
---------------------------------------------------------------------------
-- Potions: keep Luck / Miner running. Measured in game: a potion is drunk by equipping it
-- (CharacterService:EquipMisc puts it in the backpack as a tool) and activating it (about 2s);
-- each one adds its Duration (300s) to Replica.Data.Potions[name], up to its MaxDuration
-- (Luck 3600s, Miner 900s) - so anything drunk past the cap is wasted and we never do that.
-- The shop only sells standing at the stall (Purchase from across the map answers Success=false).
---------------------------------------------------------------------------
local Potions = { want = { autoLuckPotion = { 'LuckPotion2', 'LuckPotion1' }, autoMinerPotion = { 'MinerPotion2', 'MinerPotion1' } }, retryAt = 0, REACH = 2500, TOWN = 220 }
function Potions.load()
	if Potions.defs == nil then
		local ok, ex = pcall(function()
			return require(RS.Shared.Data.Extras).Items.Potion
		end)
		Potions.defs = ok and ex or false
		local ok2, sh = pcall(function()
			return require(RS.Shared.Data.Proximities).Shop
		end)
		Potions.shop = ok2 and sh or {}
	end
	return Potions.defs
end
function Potions.count(name)
	local d = data()
	for _, it in pairs(d and d.Inventory and d.Inventory.Misc or {}) do
		if type(it) == 'table' and it.Name == name then
			return tonumber(it.Quantity) or 1
		end
	end
	return 0
end
function Potions.left(name)
	local d = data()
	return tonumber(d and d.Potions and d.Potions[name]) or 0
end
-- the stall selling it, if it is on this island
function Potions.stall(name)
	local prox = workspace:FindFirstChild('Proximity')
	local m = prox and prox:FindFirstChild(name)
	local _, hrp = char()
	if not m or not hrp or not Potions.shop[name] then
		return nil
	end
	local ok, pos = pcall(function()
		return m:GetPivot().Position
	end)
	if ok and (pos - hrp.Position).Magnitude < Potions.REACH then
		return pos
	end
	return nil
end
-- On the way to a rock nothing is in our hands and nothing needs to be: that is when to drink.
function Potions.calm()
	local _, hrp = char()
	return hrp ~= nil and next(attackWarn) == nil and mobsNear(hrp.Position, 35) == 0
end
function Potions.walking()
	local _, hrp = char()
	return hrp and G.FTTravel and string.sub(tostring(G.FTStatus), 1, 7) == 'mining ' and (G.FTTravel - hrp.Position).Magnitude > 25 and Potions.calm()
end
function Potions.drink(name, onTheMove)
	local CS, TS = service('CharacterService'), service('ToolService')
	local c, _, hum = char()
	if not CS or not TS or not c or not hum or Potions.busy then
		return false
	end
	Potions.busy = true
	local q0, l0 = Potions.count(name), Potions.left(name)
	local def = Potions.defs[name]
	if not onTheMove then
		setStatus(('drinking %s (%d left after this)'):format(def and def.Name or name, q0 - 1))
	end
	-- (measured: ToolService:ToolActivated(name) on its own, potion neither equipped nor held,
	-- answered true after 3.3s with stock 10 -> 9 and the timer 0 -> 299. So no tool swap at all.)
	local t0 = os.clock()
	pcall(function()
		TS:ToolActivated(name):await()
	end)
	while alive and os.clock() - t0 < 5 and Potions.count(name) >= q0 do
		task.wait(0.1)
	end
	task.wait(0.2)
	Potions.log = Potions.log or {}
	Potions.log[#Potions.log + 1] = ('%s %s: stock %d -> %d, timer %d -> %d%s'):format(os.date('%H:%M:%S'), name, q0, Potions.count(name), l0, Potions.left(name), onTheMove and ' (while walking)' or '')
	Potions.busy = false
	return Potions.count(name) < q0 or Potions.left(name) > l0 + 60
end
function Potions.next(urgentOnly)
	for key, names in pairs(Potions.want) do
		if settings[key] then
			for _, name in ipairs(names) do
				local def = Potions.defs[name]
				if def and Potions.count(name) > 0 and Potions.left(name) + (tonumber(def.Duration) or 300) <= (tonumber(def.MaxDuration) or 900)
					and (not urgentOnly or Potions.left(name) < 20) then
					return name
				end
			end
		end
	end
	return nil
end
task.spawn(function()
	while alive do
		task.wait(0.5)
		if (settings.autoLuckPotion or settings.autoMinerPotion) and not Potions.busy and os.clock() >= (Potions.drinkAt or 0) then
			pcall(function()
				if Potions.load() then
					local name = Potions.next(false) -- (asked for: keep drinking until the timer is as full as the game allows)
					if name and not Potions.drink(name, true) then
						Potions.busy = false
						Potions.drinkAt = os.clock() + 5
					end
				end
			end)
			Potions.busy = false
		end
	end
end)
-- true when it used up this turn of the main loop (a drink or a trip to the stall)
function Potions.step()
	if not (settings.autoLuckPotion or settings.autoMinerPotion) or not Potions.load() then
		return false
	end
	local d = data()
	if not d or type(d.Potions) ~= 'table' then
		return false
	end
	local now = os.clock()
	local shopping = {}
	for key, names in pairs(Potions.want) do
		if settings[key] then
			local buyName
			for _, name in ipairs(names) do
				local def = Potions.defs[name]
				if def then
					local dur, cap = tonumber(def.Duration) or 300, tonumber(def.MaxDuration) or 900
					if Potions.count(name) > 0 and Potions.left(name) + dur <= cap and now >= (Potions.drinkAt or 0) and not Potions.busy then
						if not Potions.drink(name) then
							Potions.drinkAt = os.clock() + 20 -- (did not go down: not again right away)
						end
						return true
					end
					buyName = buyName or (Potions.stall(name) and name)
				end
			end
			-- (asked for: no topping up - a potion is only bought once there is none of it left)
			-- nothing of this kind left to drink and the last one is about to run out: restock
			local have, running = 0, 0
			for _, name in ipairs(names) do
				have += Potions.count(name)
				running = math.max(running, Potions.left(name))
			end
			if buyName and Potions.count(buyName) < 1 and not table.find(shopping, buyName) then
				shopping[#shopping + 1] = buyName
			end
		end
	end
	if #shopping == 0 or now < Potions.retryAt then
		return false
	end
	if Potions.topping then
		Potions.topping = nil
		Potions.topAt = now + 60
	end
	-- one trip stocks up every kind that is switched on (not just the one that ran out)
	for key, names in pairs(Potions.want) do
		if settings[key] then
			for _, name in ipairs(names) do
				if Potions.stall(name) and not table.find(shopping, name) then
					local other = 0
					for _, n2 in ipairs(names) do
						other += Potions.count(n2)
					end
					if Potions.count(name) < 1 then
						shopping[#shopping + 1] = name
					end
					break
				end
			end
		end
	end
	local PS = service('ProximityService')
	local bought = false
	for _, name in ipairs(shopping) do
		local sh = Potions.shop[name]
		local price = tonumber(sh.Price) or math.huge
		local qty = math.min((tonumber(sh.MaxPurchaseLimit) or 10) - Potions.count(name), math.floor((tonumber(data().Gold) or 0) / price))
		local pos = Potions.stall(name)
		if PS and pos and qty > 0 then
			local def = Potions.defs[name]
			setStatus(('going to buy %d x %s (%d gold each)'):format(qty, def and def.Name or name, price))
			local _, hrp = char()
			if (hrp and (hrp.Position - pos).Magnitude < 9) or tweenTo(CFrame.new(pos + Vector3.new(0, 1, 5))) then
				task.wait(0.3)
				local q0 = Potions.count(name)
				pcall(function()
					PS:Purchase(name, qty):await()
				end)
				local tb = os.clock()
				while os.clock() - tb < 2 and Potions.count(name) == q0 do
					task.wait(0.1)
				end
				if Potions.count(name) > q0 then
					bought = true
					setStatus(('bought %d x %s'):format(Potions.count(name) - q0, def and def.Name or name))
				end
			end
		end
	end
	if not bought then
		Potions.retryAt = os.clock() + 300
		setStatus('could not buy potions (no gold, or the stall did not sell) — trying again in 5 minutes')
	end
	return true
end
G.FTPotions = Potions

-- Junk runes (Frost Speck, Rage Mark, Ward Patch... pile up by the hundred). Measured: Greedy Cey
-- takes them from anywhere on the map, through the same sale the ores go through, basket keyed
-- by the rune's GUID. Favorited runes are never sold, and one of each kind is always kept.
local RuneSell = { at = 0, LOW = { common = true, uncommon = true, rare = true } }
function RuneSell.kind(def, id)
	return (string.gsub(tostring(def.Name or id), '%s+[IVX]+$', ''))
end
function RuneSell.step()
	if not settings.autoSellRunes or os.clock() < RuneSell.at then
		return false
	end
	RuneSell.at = os.clock() + 30
	if RuneSell.defs == nil then
		local ok, R = pcall(function()
			return require(RS.Shared.Data.Runes).Runes
		end)
		RuneSell.defs = ok and R or false
	end
	local d = data()
	local npc = workspace:FindFirstChild('Proximity') and workspace.Proximity:FindFirstChild('Greedy Cey')
	if not RuneSell.defs or not d then
		return false
	end
	local maxTier = math.clamp(tonumber(settings.runeSellTier) or 1, 1, 5)
	local fav = d.Favorites or {}
	local basket, n, kept = {}, 0, {}
	for _, it in pairs(d.Inventory and d.Inventory.Misc or {}) do
		local def = type(it) == 'table' and it.GUID and it.Id and RuneSell.defs[it.Id]
		-- Epic and rarer are never sold. Only a rune whose rarity is KNOWN to be below Epic goes:
		-- one with no rarity, or a rarity name we have not seen, is kept.
		local rar = def and string.lower(tostring(it.Rarity or def.Rarity or ''))
		-- The kinds picked to keep ("Drain Edge" covers I, II and III) are never sold at all; of
		-- every other kind nothing is held back, not even one.
		local kind = def and RuneSell.kind(def, it.Id)
		if def and not (type(settings.runeKeep) == 'table' and settings.runeKeep[kind] and (tonumber(def.Tier) or 1) >= (tonumber(settings.runeKeepTier) or 3)) and (RuneSell.LOW[rar] or settings.runeSellEpic == true) and (tonumber(def.Tier) or 1) <= maxTier and fav[it.GUID] == nil then
			basket[it.GUID] = 1
			n += 1
		end
	end
	if n < 1 then
		return false
	end
	setStatus(('selling %d runes'):format(n))
	local PS, DS = service('ProximityService'), service('DialogueService')
	local goldBefore = d.Gold or 0
	local function waitGold()
		local tg = os.clock()
		while os.clock() - tg < 3 and ((data() or {}).Gold or 0) == goldBefore do
			task.wait(0.1)
		end
		return ((data() or {}).Gold or 0) ~= goldBefore
	end
	-- The direct call needs no NPC, so it also works in a raid (measured there: +25 gold for one
	-- tier 1 rune). The dialogue route is the fallback, where Greedy Cey exists.
	pcall(function()
		local IS = service('InventoryService')
		if IS then
			IS:SellMisc(basket)
		end
	end)
	if not waitGold() and npc then
		pcall(function()
			PS:ForceDialogue(npc, 'SellConfirmMisc')
		end)
		task.wait(0.4)
		pcall(function()
			DS:RunCommand('SellConfirm', { Basket = basket })
		end)
		waitGold()
		pcall(function()
			getsenv(LocalPlayer.PlayerGui.DialogueUI.DialogueHandler).Close()
		end)
	end
	local gained = ((data() or {}).Gold or 0) - goldBefore
	if gained > 0 then
		setStatus(('sold %d runes for %d gold'):format(n, gained))
	else
		RuneSell.at = os.clock() + 300
		setStatus('selling runes did not go through — trying again in 5 minutes')
	end
	return true
end

-- Runes sell on their own clock, not from the main loop: that loop stops at "dead / respawning"
-- (all of a raid, measured: 82 tier 2 runes sat unsold with the slider at 2) and the sale is
-- only a remote call - it needs no character.
task.spawn(function()
	while alive and G.SB2ForgeToolsToken == token do
		task.wait(5)
		pcall(RuneSell.step)
	end
end)

-- (v254, asked for: "when retrying just click retry theres a checkpoint system".) After a defeat in
-- an Abyss run the game shows its results screen with a Retry button, which restarts from the last
-- checkpoint. Pressed here, on its own clock (the main loop stops at "dead"). ONLY inside an Abyss
-- run: the same screen is used for raids, where a retry may cost a Raid Ticket - never touched.
task.spawn(function()
	while alive and G.SB2ForgeToolsToken == token do
		task.wait(2)
		pcall(function()
			if not settings.autoAbyss or workspace:GetAttribute('AbyssRun') ~= true then
				return
			end
			local rr = LocalPlayer.PlayerGui:FindFirstChild('RaidRewards')
			local btn = rr and rr.Enabled and rr:FindFirstChild('Retry', true)
			if not btn or not btn:IsA('GuiButton') or os.clock() - (G.FTAbyssRetryAt or 0) < 6 then
				return
			end
			local q = btn
			while q and q ~= rr do
				if q:IsA('GuiObject') and not q.Visible then
					return
				end
				q = q.Parent
			end
			for _, t in ipairs(btn:GetDescendants()) do
				if t:IsA('TextLabel') and string.find(t.Text, 'Restarting', 1, true) then
					return -- (already pressed)
				end
			end
			G.FTAbyssRetryAt = os.clock()
			setStatus('abyss: defeated - pressing Retry (from the checkpoint)')
			for _, c in ipairs(getconnections(btn.Activated)) do
				pcall(function()
					c:Fire()
				end)
			end
			G.FTAbyssRetries = (G.FTAbyssRetries or 0) + 1
		end)
	end
end)

local function mainLoop(myGen)
	while alive and G.SB2ForgeToolsToken == token and loopGen == myGen do
		local ok, err = pcall(function()
			local _, _, hum = char()
			if not hum or hum.Health <= 0 then
				setStatus('dead / respawning')
				pcall(MineHooks.reset)
				task.wait(1)
				return
			end
			local FC = controller('ForgeController')
			if FC and FC.ForgeActive and not settings.autoForge and not questForgeType() then
				setStatus('forge open')
				task.wait(0.5)
				return
			end
			if game.PlaceId == 84980181568016 and workspace:GetAttribute('RaidRunStartedAt') and workspace:GetAttribute('AbyssRun') ~= true then
				-- (v267, seen live: a raid the user asked for was started with "Auto mobs" off, and inside
				-- it stood there "no rocks to mine" with five zombies around. A raid is only ever entered
				-- on purpose, and there is nothing else to do in one: fight.)
				-- (v320, the user: "i dont even have auto kill enemies on why ... is it teleporting to them".
				-- Auto kill mobs off = it does not go to them in a raid either; auto parry still runs.)
				if not settings.autoMobs then
					QS.wantMobs = false
					setStatus('raid: Auto kill mobs is off — not moving')
					task.wait(0.3)
					return
				end
				QS.wantMobs = true
				if #mobList() > 0 then
					fightOnce()
				else
					setStatus('raid: waiting for the next mobs')
					task.wait(0.3)
				end
				return
			end
			if settings.autoAbyss and Abyss.inRun() then
				-- In the Abyss: just fight (no quests / forging in there).
				-- (v314: hold still while a card is being picked or skipped - at most 15 s)
				if G.FTAbyssCardBusy and os.clock() - G.FTAbyssCardBusy < 15 then
					setStatus('abyss: choosing a card')
					task.wait(0.2)
					return
				end
				QS.wantMobs = true
				if #mobList() > 0 then
					fightOnce()
				elseif (function()
					-- (v251) no mob within 800 studs but the floor's mobs are alive further off: we are off the
					-- floor. Back to the middle of the level they stand on (the level, not a mob's position).
					G.FTAbyssAll = true
					local okL, far = pcall(mobList)
					G.FTAbyssAll = nil
					local e1 = okL and far[1]
					local rl = workspace:FindFirstChild('RaidLevels')
					if not e1 or not rl then
						return false
					end
					local best, bd
					for _, l in ipairs(rl:GetChildren()) do
						local okP, pv = pcall(function()
							return l:GetPivot().Position
						end)
						local dd = okP and (pv - e1.r.Position).Magnitude
						if dd and dd < 600 and (not bd or dd < bd) then
							best, bd = pv, dd
						end
					end
					if not best then
						return false
					end
					setStatus('abyss: off the floor - going back to it')
					G.FTAbyssBack = true
					pcall(tweenTo, CFrame.new(best + Vector3.new(0, 8, 0)))
					G.FTAbyssBack = nil
					return true
				end)() then
					task.wait(0.2)
				else
					setStatus('abyss: waiting for the next floor')
					task.wait(0.5)
				end
				return
			end
			if Raid.step() then
				return
			end
			if Craft.step() then
				return
			end
			if Quest.pickPlan and Quest.pickPlan() then
				return
			end
			if type(G.FTForgeRecipe) == 'table' then
				local okF = forgeOnce()
				G.FTForgeResult = { ok = okF, status = _statusText, at = os.time() }
				return
			end
			if Dps.step() then
				return
			end
			if Pickup.step() then
				return
			end
			if Abyss.step() then
				return
			end
			if Boss.step() then
				return
			end
			if Meteor.step() then
				return
			end
			do
				-- (measured: with every modifier ticked and "retreat at" on 0 it ran 800 studs back to a
				-- Possessed Monk Panda five times and died next to it each time)
				local _, _, hh = char()
				local frac = hh and hh.MaxHealth > 0 and hh.Health / hh.MaxHealth or 0
				local sp = frac >= 0.6 and not lowHp() and not (settings.ignoreMobs and not settings.autoMobs) and specialTargets()[1] or nil
				if sp then
					setStatus(('hunting %s %s (%.0f studs)'):format(sp.mut, sp.m.Name, sp.d))
					fightOnce(sp)
					local _, _, h2 = char()
					if not h2 or h2.Health <= 0 then
						huntSkip[sp.key] = 0 -- (v246: was a 15 minute skip after it killed us)
						statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('%s killed us — leaving that kind alone for 15 minutes'):format(sp.key)
					elseif sp.m.Parent and sp.h.Health > 0 and h2.Health / math.max(1, h2.MaxHealth) < 0.4 then
						-- backed out hurt: get clear of it, and it waits until we are back over 60%
						local _, hr = char()
						if hr and sp.r.Parent then
							dodgeFrom(sp.r.Position, 60)
						end
					end
					return
				end
			end
			if os.clock() - lastQuestStep > 3 then
				lastQuestStep = os.clock()
				Rewards.step()
				if Quest.step() then
					return
				end
			end
			if Potions.step() then
				return
			end
			local farm = chooseFarm()
			if forgeNeeded() then
				forgeOnce()
			elseif sellNeeded() then
				sellOres()
			elseif Quest.recycleNeeded() then
				Quest.recycleGear()
			elseif Quest.gearSellNeeded() then
				Quest.sellGear()
			elseif G.FTCamp and type(G.FTCampStay) == 'table' and G.FTCampStay[tostring(G.FTCampFor)] and not (farm == 'mine' and craftWant() and craftRockUp()) then
				-- (v235, asked for: wait where the quest's mob lives instead of mining around it, in case
				-- the game only respawns a zone's mobs while someone stands in that zone)
				-- (v239: this used to come after "fight anything", so with Auto mobs on it walked 1,000
				-- studs off to the apes. Now only mobs within 220 studs of the waiting spot are fought.)
				local _, hc = char()
				local nearE
				if farm == 'mobs' or settings.autoMobs then
					for _, e in ipairs(mobList()) do
						if e.r and (e.r.Position - G.FTCamp).Magnitude <= 220 then
							nearE = e
							break
						end
					end
				end
				if nearE then
					fightOnce(nearE)
				elseif hc and (hc.Position - G.FTCamp).Magnitude > 25 then
					setStatus(('going to wait where %s lives'):format(tostring(G.FTCampFor)))
					tweenTo(CFrame.new(G.FTCamp + Vector3.new(0, 3, 0)))
				else
					setStatus(('waiting here for %s to respawn'):format(tostring(G.FTCampFor)))
					task.wait(1)
				end
			elseif farm == 'mobs' and #mobList() > 0 then
				fightOnce()
			elseif farm == 'mine' or (farm == 'mobs' and (settings.autoMine or QS.wantMine or craftWant())) then
				if not mineOnce() then
					task.wait(1)
				end
			else
				local cap = tonumber(settings.maxMobHp) or 0
				if farm == 'mobs' and cap > 0 then
					setStatus(('nothing to fight: every %s here is over your max mob health of %d'):format(tostring(QS.mobTarget or settings.mobFilter), cap))
				else
					setStatus('idle')
				end
				task.wait(0.5)
			end
		end)
		if not ok then
			warn('[ForgeTools] ' .. tostring(err))
			setStatus('error: ' .. tostring(err):sub(1, 120))
			task.wait(1)
		end
		task.wait(0.05)
	end
end
local loopThread = task.spawn(mainLoop, loopGen)
-- Auto-buy best pickaxe runs on its own timer so the quest/forge steps can't starve it.
task.spawn(function()
	while alive and G.SB2ForgeToolsToken == token do
		if settings.autoPickaxe then
			pcall(Quest.buyBestPickaxe)
		end
		task.wait(8)
	end
end)
-- Tracers pill + sync tracers to the saved setting
pcall(wireTracersPill)
pcall(setTracers, settings.tracers == true)

---------------------------------------------------------------------------
-- Special-enemy tracers: a line to every mob carrying one of the game's modifiers (Heaven, Hell,
-- Limbo, Lucky, Ancient, Chaotic, Giant...), in the modifier's own name colour, with its name and
-- distance. Toggled by the "SP" pill. The modifier list is the game's own (Shared.Data.Mutations).
-- How a mob is recognised: an attribute holding a modifier name, else a modifier name written on
-- its name tag (a word that is not part of the mob's own name).
---------------------------------------------------------------------------
local MobTrace = { list = {}, found = {} }
do
	local muts
	local function names()
		if not muts then
			local out = {}
			pcall(function()
				local M = require(RS.Shared.Data.Mutations)
				for name, def in pairs(M.Mutations or {}) do
					if type(def) == 'table' then
						out[name] = typeof(def.NameColor) == 'Color3' and def.NameColor or Color3.fromRGB(255, 220, 90)
					end
				end
			end)
			if next(out) then
				muts = out
			else
				return out
			end
		end
		return muts
	end
	function MobTrace.mutation(m)
		local mu = names()
		for k, v in pairs(m:GetAttributes()) do
			if type(v) == 'string' and mu[v] then
				return v, 'attribute ' .. tostring(k)
			end
		end
		local own = {}
		for word in string.gmatch(m.Name, '%a+') do
			own[word] = true
		end
		local hrp = m:FindFirstChild('HumanoidRootPart')
		local fr = hrp and hrp:FindFirstChild('infoFrame')
		if fr then
			for _, d in ipairs(fr:GetDescendants()) do
				if d:IsA('TextLabel') and d.Text ~= '' then
					local text = string.gsub(d.Text, '<[^>]->', '')
					for word in string.gmatch(text, '%a+') do
						if mu[word] and not own[word] then
							return word, 'name tag'
						end
					end
				end
			end
		end
		return nil
	end
	function MobTrace.scan()
		local list = {}
		local living = workspace:FindFirstChild('Living')
		for _, m in ipairs(living and living:GetChildren() or {}) do
			if m:GetAttribute('IsNpc') and not m:GetAttribute('DpsDummy') then
				local hrp = m:FindFirstChild('HumanoidRootPart')
				local hum = m:FindFirstChildOfClass('Humanoid')
				if hrp and hum and hum.Health > 0 then
					local ok, mut, how = pcall(MobTrace.mutation, m)
					if ok and mut then
						list[#list + 1] = { m = m, hrp = hrp, mut = mut, color = names()[mut], name = (string.gsub(m.Name, '%d+$', '')) }
						if not MobTrace.found[m] then
							MobTrace.found[m] = true
							statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. ('special enemy: %s %s (seen by %s)'):format(mut, m.Name, tostring(how))
						end
					end
				end
			end
		end
		MobTrace.list = list
	end
	local lines, texts = {}, {}
	local function hide(from)
		for i = from, #lines do
			lines[i].Visible = false
			texts[i].Visible = false
		end
	end
	function MobTrace.clear()
		for i = 1, #lines do
			pcall(function()
				lines[i]:Remove()
				texts[i]:Remove()
			end)
		end
		lines, texts = {}, {}
	end
	function MobTrace.draw()
		if not settings.mobTracers or type(Drawing) ~= 'table' and type(Drawing) ~= 'userdata' then
			hide(1)
			return
		end
		local cam = workspace.CurrentCamera
		local vp = cam.ViewportSize
		local from = Vector2.new(vp.X / 2, vp.Y - 4)
		local me = cam.CFrame.Position
		local n = 0
		for _, e in ipairs(MobTrace.list) do
			if e.m.Parent and e.hrp.Parent then
				local pos, onScreen = cam:WorldToViewportPoint(e.hrp.Position)
				if pos.Z > 0 then
					n += 1
					if not lines[n] then
						local l = Drawing.new('Line')
						l.Thickness = 2
						l.Transparency = 1
						lines[n] = l
						local t = Drawing.new('Text')
						t.Size = 16
						t.Center = true
						t.Outline = true
						texts[n] = t
					end
					local l, t = lines[n], texts[n]
					l.From, l.To, l.Color, l.Visible = from, Vector2.new(pos.X, pos.Y), e.color, true
					t.Text = ('%s %s  %dm'):format(e.mut, e.name, math.floor((e.hrp.Position - me).Magnitude))
					t.Position, t.Color, t.Visible = Vector2.new(pos.X, pos.Y - 28), e.color, onScreen
				end
			end
		end
		hide(n + 1)
	end
	task.spawn(function()
		while alive do
			if settings.mobTracers then
				pcall(MobTrace.scan)
			else
				MobTrace.list = {}
			end
			task.wait(1)
		end
	end)
	local rc = RunService.RenderStepped:Connect(function()
		if alive then
			pcall(MobTrace.draw)
		end
	end)
	task.spawn(function()
		while alive do
			task.wait(0.5)
		end
		rc:Disconnect()
		MobTrace.clear()
	end)
	G.FTMobTrace = MobTrace
	pcall(function()
		local reg = G.SB2RegisterPill
		if type(reg) ~= 'function' then
			return
		end
		local btn
		local function paint()
			local on = settings.mobTracers == true
			btn.Text = on and 'SP \226\151\143' or 'SP'
			btn.TextColor3 = on and Color3.fromRGB(255, 214, 120) or Color3.fromRGB(220, 230, 245)
			local st = btn:FindFirstChildOfClass('UIStroke')
			if st then
				st.Color = on and Color3.fromRGB(230, 180, 70) or Color3.fromRGB(70, 90, 120)
			end
		end
		btn = reg({
			id = 'SP',
			text = settings.mobTracers and 'SP \226\151\143' or 'SP',
			onClick = function()
				settings.mobTracers = not settings.mobTracers
				save()
				paint()
			end,
		})
		paint()
	end)
end

-- Auto enhance: the gear being worn goes up one level at a time while the game's own success
-- chance is at least the user's limit and the essences + gold are there. (Game rules: a failed
-- enhance takes the item down a level, and at +3 / +6 / +9 it also loses a rune slot.)
task.spawn(function()
	local pauseUntil = 0
	local gap = 5
	local noChange = 0
	while alive and G.SB2ForgeToolsToken == token do
		task.wait(gap)
		-- (by hand the game lets you spam the button: after any roll, won or lost, the next one
		-- follows at once; only with nothing to enhance does it look again every 3s)
		gap = 3
		if settings.autoEnhance and os.clock() >= pauseUntil then
			pcall(function()
				local FC = controller('ForgeController')
				local d = data()
				local svc = service('EnhanceService')
				if not d or not svc or (FC and FC.ForgeActive) then
					return
				end
				local have = {}
				for _, it in pairs((d.Inventory or {}).Misc or {}) do
					if type(it) == 'table' and it.Name then
						have[it.Name] = (have[it.Name] or 0) + (tonumber(it.Quantity) or 1)
					end
				end
				local maxLv = math.clamp(tonumber(settings.enhanceMaxLevel) or 9, 1, 9)
				local minCh = math.clamp(tonumber(settings.enhanceMinChance) or 0, 0, 100)
				-- (d.Equipped is a copy that does not follow enhances: levels come from the inventory list)
				local fresh = {}
				for _, e in ipairs((d.Inventory or {}).Equipments or {}) do
					if type(e) == 'table' and e.GUID then
						fresh[e.GUID] = e
					end
				end
				G.FTEnhanced = G.FTEnhanced or {}
				-- Speed (the game lets the button be spammed): every worn item rolls at the same time, each
				-- one roll after another with nothing in between; chance and cost are asked once per item
				-- and level and remembered, so a roll is a single round trip.
				G.FTEnhCache = G.FTEnhCache or {}
				local running, didRoll, refused = 0, false, false
				for slot, worn in pairs(d.Equipped or {}) do
					local it = type(worn) == 'table' and worn.GUID and (fresh[worn.GUID] or worn) or nil
					local known = it and math.max(tonumber(it.Upgrade) or 0, G.FTEnhanced[it.GUID] or 0) or 0
					if it and it.Type and known < maxLv then
						running += 1
						task.spawn(function()
							pcall(function()
								local lv = known
								for _ = 1, 40 do
									if not alive or not settings.autoEnhance or lv >= maxLv then
										break
									end
									local ckey = it.GUID .. ':' .. lv
									local c = G.FTEnhCache[ckey]
									if not c then
										local probe = table.clone(it)
										probe.Upgrade = lv
										local okC, ch = svc:PreviewChance(it.GUID, {}, nil):await()
										local okR, req = svc:GetUpgradeRequirements(probe):await()
										c = { chance = okC and type(ch) == 'table' and tonumber(ch.Final) or 0, req = okR and type(req) == 'table' and req or nil }
										if c.req then
											G.FTEnhCache[ckey] = c
										end
									end
									local req, chance = c.req, c.chance
									local dn = data()
									local can = req and type(req.materials) == 'table' and chance >= minCh
										and (tonumber(dn and dn.Gold) or 0) >= (tonumber(req.totalPrice) or math.huge)
									if can then
										local haveNow = {}
										for _, mi in pairs(((dn or {}).Inventory or {}).Misc or {}) do
											if type(mi) == 'table' and mi.Name then
												haveNow[mi.Name] = (haveNow[mi.Name] or 0) + (tonumber(mi.Quantity) or 1)
											end
										end
										for _, m in ipairs(req.materials) do
											if (haveNow[m.material.Name] or 0) < (tonumber(m.quantity) or 0) then
												can = false
												G.FTEnhanceTold = G.FTEnhanceTold or {}
												local key = it.GUID .. ':' .. lv .. ':' .. m.material.Name
												if not G.FTEnhanceTold[key] then
													G.FTEnhanceTold[key] = true
													local msg = ('%s +%d -> +%d needs %d %s (you have %d)'):format(it.Type, lv, lv + 1,
														tonumber(m.quantity) or 0, m.material.Name, haveNow[m.material.Name] or 0)
													statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. 'auto enhance waiting: ' .. msg
													pcall(function()
														game:GetService('StarterGui'):SetCore('SendNotification', { Title = 'Auto enhance waiting', Text = msg, Duration = 8 })
													end)
												end
											end
										end
									end
									if not can then
										break
									end
									local okE, res = svc:EnhanceEquipment(it.GUID, nil, nil):await()
									local nlv = okE and type(res) == 'table' and tonumber(res.newLevel) or lv
									G.FTEnhanced[it.GUID] = nlv
									if nlv > lv then
										didRoll = true
										setStatus(('enhanced %s to +%d (%.0f%% chance)'):format(it.Type, nlv, chance))
									elseif nlv < lv then
										didRoll = true
										setStatus(('enhancing %s failed: +%d -> +%d'):format(it.Type, lv, nlv))
									else
										refused = true
										G.FTEnhCache[ckey] = nil
										break
									end
									lv = nlv
								end
							end)
							running -= 1
						end)
					end
				end
				local tw = os.clock()
				while running > 0 and os.clock() - tw < 60 do
					task.wait(0.05)
				end
				if didRoll then
					gap, noChange = 0.1, 0
				elseif refused then
					-- (one refusal can be the server's own rate limit: only three rounds in a row is a stop)
					noChange += 1
					gap = 1
					if noChange >= 3 then
						noChange = 0
						pauseUntil = os.clock() + 300
						setStatus('the game is not enhancing — trying again in 5 minutes')
					end
				end
			end)
		end
	end
end)

-- Stuck watchdog: if an auto option is on but nothing has changed for 75s (no new status, no
-- movement, no forge running), stop whatever it is waiting on and restart the loop.
-- Every status is also written to PlayerTools/forgetools_log_<account>.txt so problems can be traced.
task.spawn(function()
	local lastPos, lastSave = nil, 0
	local logPath = 'PlayerTools/forgetools_log_' .. string.lower(LocalPlayer.Name) .. '.txt'
	while alive and G.SB2ForgeToolsToken == token do
		task.wait(3)
		local _, hrp = char()
		if hrp then
			if lastPos and (hrp.Position - lastPos).Magnitude > 3 then
				lastProgress = os.clock()
			end
			lastPos = hrp.Position
		end
		local anyOn = settings.autoMine or settings.autoMobs or settings.autoForge or settings.autoSell
			or settings.autoCompleteQuests or settings.autoAcceptQuests or settings.autoAbyss
		local FC = controller('ForgeController')
		local forging = FC and FC.ForgeActive
		if anyOn and not forging and os.clock() - lastProgress > 75 and _statusText ~= 'idle' then
			statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. 'WATCHDOG: stuck on "' .. tostring(_statusText) .. '" - restarting loop'
			warn('[ForgeTools] stuck on "' .. tostring(_statusText) .. '" for 75s - restarting')
			pcall(stopTween)
			pcall(function()
				getsenv(LocalPlayer.PlayerGui.DialogueUI.DialogueHandler).Close()
			end)
			pcall(task.cancel, loopThread)
			loopGen += 1
			lastProgress = os.clock()
			loopThread = task.spawn(mainLoop, loopGen)
		end
		if os.clock() - lastSave > 15 then
			lastSave = os.clock()
			pcall(writefile, logPath, table.concat(statusLog, '\n'))
		end
	end
end)

task.spawn(function()
	while alive and G.SB2ForgeToolsToken == token do
		local used, cap = bagCapacity()
		local d = data() or {}
		pcall(statsLabel.SetText, statsLabel, ('Gold %s · bag %s/%s · mined %d · sold %d · forged %d · kills %d'):format(
			tostring(math.floor((d.Gold or 0) * 100) / 100), tostring(used or '?'), tostring(cap or '?'),
			stats.mined, stats.sold, stats.forged, stats.kills))
		task.wait(1)
	end
end)

---------------------------------------------------------------------------
-- Teleport persistence + unload
---------------------------------------------------------------------------
pcall(function()
	local q = queue_on_teleport or (syn and syn.queue_on_teleport)
	if type(q) == 'function' then
		q([[
			if not game:IsLoaded() then game.Loaded:Wait() end
			task.wait(4)
			if getgenv().SB2ForgeToolsLoaded then return end
			if isfile('PlayerTools/ForgeTools.lua') then
				local fn = (loadstring or load)(readfile('PlayerTools/ForgeTools.lua'), 'ForgeTools.lua')
				if fn then task.spawn(fn) end
			end
		]])
	end
end)

G.SB2ForgeToolsUnload = function(fromWindow)
	pcall(Nav.saveEdges, true)
	pcall(function()
		LocalPlayer.Character:SetAttribute('EmoteWalkSpeed', nil)
		LocalPlayer.Character:FindFirstChildOfClass('Humanoid'):SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
	end)
	alive = false
	G.SB2ForgeToolsToken = nil
	G.SB2ForgeToolsLoaded = nil
	G.SB2ForgeToolsUnload = nil
	stopTween()
	for _, c in ipairs(type(G.FTBlockConns) == 'table' and G.FTBlockConns or {}) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(function()
		G.FTDialogueConn:Disconnect()
	end)
	pcall(function()
		local tc = controller('ToolController')
		if tc and tc.isBlocking then
			tc:StopBlock()
		end
	end)
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	if not fromWindow then
		pcall(function()
			Library:Unload()
		end)
	end
end

Library:Notify('Forge Tools loaded (' .. LocalPlayer.Name .. ')', 4)
warn('[ForgeTools] loaded ' .. BUILD)
