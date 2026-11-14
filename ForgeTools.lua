--[[
	ForgeTools.lua — The Forge (Roblox) helper with an Ataraxia window.
	  • Auto mine   — tweens to rocks and mines them with the game's own swing.
	  • Auto sell   — tweens to Greedy Cey and sells your ores when the bag is getting full.
	  • Auto forge  — tweens to the forge, puts in your ores and plays every minigame perfectly.
	  • Auto mobs   — tweens to mobs (the Living folder) and fights them with your Weapon.
	Movement is always a tween (no long teleports — the game snaps those back).
	Needs workspace/PlayerTools/AtaraxiaLibrary.lua. Autoload: autoexec/03_forgetools.lua.
]]

local BUILD = 'forge-tools-v99'
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
	forgeWhenFull = false,
	forgeAlternate = false,
	autoEnhance = false,
	enhanceMinChance = 0,
	enhanceMaxLevel = 9,
	raceStop = 'Legendary',
	raceKeepSpins = 0,
	sellAt = 90,
	autoForge = false,
	forgeType = 'Weapon',
	forgePiece = 'Any',
	fleeDeadly = true,
	forgeOres = 3,
	forgeKeep = 0,
	switchMins = 3,
	autoAcceptQuests = false,
	autoCompleteQuests = false,
	questBuy = false,
	autoPickaxe = false,
	tracers = false,
	claimBoard = false,
	autoBlock = false,
	autoMail = false,
	autoOffer = false,
	autoCodes = false,
	autoDaily = false,
	parryLead = 20,
	forgeBest = false,
	questRange = 1000,
	noBlur = false,
	combatStyle = 'Hit & run',
	autoAbyss = false,
	dodgeDist = 16,
	autoMobs = false,
	mobFilter = 'Any',
	retreatHp = 45,
	maxMobHp = 80,
	autoEquip = false,
	tweenSpeed = 55,
	walkSpeed = 50,
	autoload = true,
	focusQuest = 'Auto',
	keepOres = {},
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
				noclip = true
				while true do
					local dt = task.wait()
					local _, h, hm = char()
					if not h or not hm or hm.Health <= 0 then
						noclip = false
						return false, 'stuck'
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
				if not h or not hm or hm.Health <= 0 then
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
local function tweenTo(cf, opts)
	local prev = G.FTTravel
	G.FTTravel = typeof(cf) == 'CFrame' and cf.Position or cf
	local ok, a, b = pcall(tweenToRaw, cf, opts)
	G.FTTravel = prev
	if not ok then
		error(a, 0)
	end
	return a, b
end

local function standNear(part, gap)
	local _, hrp = char()
	local p = part.Position
	local dir = hrp and ((hrp.Position - p) * Vector3.new(1, 0, 1)) or Vector3.new(1, 0, 0)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
	local r = math.max(part.Size.X, part.Size.Z) / 2 + (gap or 2)
	local pos = p + dir * r
	return CFrame.lookAt(pos, Vector3.new(p.X, pos.Y, p.Z))
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
local function setStatus(t)
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
local noDamage = {} -- rock type name -> rocks in a row that took no damage
local unreachable = setmetatable({}, { __mode = 'k' }) -- rock Model -> os.clock() until which we skip it
local unreachFails = setmetatable({}, { __mode = 'k' }) -- rock Model -> times we failed to get to it
local zoneNoPath = {} -- zone name -> { n = rocks with no walkable route, at = last time }
local zoneBlocked = {} -- zone name -> os.clock() until which the whole zone is skipped (walled off from here)
local MineHooks = {} -- .clear(pos) is filled in by the mob code: kill mobs around a rock first

-- Living mobs within radius of a position: count, list.
local function mobsNear(pos, radius)
	local living = workspace:FindFirstChild('Living')
	local list = {}
	if not living then
		return 0, list
	end
	for _, m in ipairs(living:GetChildren()) do
		if m:GetAttribute('IsNpc') and not Players:GetPlayerFromCharacter(m) then
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
		local _, _, hum = char()
		return hum ~= nil and h ~= nil and h.MaxHealth < 1e8 and h.MaxHealth > hum.MaxHealth * 12
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
	local _, list = mobsNear(hrp.Position, 12)
	for _, e in ipairs(list) do
		if e.h.MaxHealth < 1e8 and not e.m.Name:find('Dummy') then
			return e
		end
	end
	return MineHooks.attacker and MineHooks.attacker() or nil
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
		if (settings.mineZone == 'Any' or settings.mineZone == zone.Name) and os.clock() >= (zoneBlocked[zone.Name] or 0) then
			for _, sp in ipairs(zone:GetChildren()) do
				local m = sp:FindFirstChildWhichIsA('Model')
				local hb = m and m:FindFirstChild('Hitbox')
				local hp = m and m:GetAttribute('Health')
				if hb and type(hp) == 'number' and hp > 0 and not tooStrong[m.Name]
					and not (unreachable[m] and os.clock() < unreachable[m])
					and not ((settings.skipLucky or G.FTQuestWantsOre) and string.find(m.Name, 'Lucky', 1, true))
					and not Deadly.near(hb.Position, Deadly.RANGE + 8)
					and not Lava.at(groundAt(standNear(hb, 2).Position))
				then
					-- Rocks with mobs around them count as much farther away, so clear ones win.
					local danger = mobsNear(hb.Position, 22)
					local d = (hb.Position - hrp.Position).Magnitude
					local want = G.FTQuestRock and m.Name == G.FTQuestRock and -350 or 0 -- quest asks for this rock type
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
					list[#list + 1] = { m = m, hb = hb, d = d, zone = zone.Name, danger = danger,
						score = d + ((climb > 10 and d < 80) and climb * 4 or 0) + math.min(danger, 3) * 35 + taken * 150 + want }
				end
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
	local function handleThreat()
		local th = threatNow()
		if not th then
			return false
		end
		unreachable[target.m] = os.clock() + 60 -- come back to this rock once the mob is dealt with / gone
		if MineHooks.defend then
			MineHooks.defend(th)
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
	local okGo, why = tweenTo(standNear(target.hb, 2), { alt = alt, abort = function()
		return not (settings.autoMine or G.FTQuestWantsOre) or not target.m.Parent or threatNow() ~= nil or takenByOther()
	end, onRelay = function()
		setStatus(('mining %s (%.0f studs) — long route, walking via known spots'):format(target.m.Name, target.d))
	end })
	if handleThreat() then
		return true
	end
	if takenNow then
		setStatus(('someone else got to that %s first — picking another'):format(target.m.Name))
		return true
	end
	if not okGo then
		local _, myh = char()
		if settings.autoMine and target.m.Parent and myh and why ~= 'wedged'
			and (myh.Position - target.hb.Position).Magnitude > math.max(target.hb.Size.X, target.hb.Size.Z) / 2 + 10 then
			local fails = (unreachFails[target.m] or 0) + 1
			unreachFails[target.m] = fails
			if why == 'nopath' then
				-- Third rock in a row with no route at all, from the same place: it is not the rocks,
				-- it is where we are standing. Get out, and forget what was ruled out from in here.
				local sp = MineHooks.strandPos
				if sp and (myh.Position - sp).Magnitude < 25 then
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
				if z.n >= 2 and settings.mineZone == 'Any' then
					zoneBlocked[target.zone] = os.clock() + 1200
					zoneNoPath[target.zone] = nil
					setStatus(target.zone .. ' is walled off from here — mining other zones')
				else
					setStatus('no route to ' .. target.m.Name .. ' — skipping it')
				end
			else
				unreachable[target.m] = os.clock() + math.min(45 * fails, 300)
				setStatus('cannot reach ' .. target.m.Name .. ' on foot — skipping for now [' .. tostring(why) .. ': ' .. tostring(G.FTNavDbg) .. ']')
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
		if hp ~= lastHp then
			lastHp, lastChange = hp, os.clock()
			noDamage[target.m.Name] = nil
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
			if noDamage[target.m.Name] >= 3 then
				tooStrong[target.m.Name] = true
				setStatus(target.m.Name .. ' too strong for your pickaxe — skipping that type')
			else
				setStatus(('no damage on %s from %.0f studs away (rock is %.0f wide) — trying another'):format(
					target.m.Name, away, math.max(target.hb.Size.X, target.hb.Size.Z)))
			end
			break
		end
		local _, hrp, hum = char()
		if hrp then
			local half = math.max(target.hb.Size.X, target.hb.Size.Z) / 2
			local off = (hrp.Position - target.hb.Position) * Vector3.new(1, 0, 1)
			if off.Magnitude > half + 16 then
				break -- knocked far away
			elseif off.Magnitude > half + 3 and hum then
				hum:MoveTo(Vector3.new(target.hb.Position.X, hrp.Position.Y - 3, target.hb.Position.Z)) -- step in
			end
		end
		if handleThreat() then
			break
		end
		swing(tool)
		task.wait(0.35)
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
local function forgeTypeNow()
	return questForgeType() or Piece.typeOf(settings.forgePiece)
		or (settings.forgeAlternate and forgeAlt) or settings.forgeType
end

local function forgeNeeded()
	local _, total = oreCounts()
	if questForgeType() then
		return total >= 3
	end
	if not settings.autoForge then
		return false
	end
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
	if settings.forgeBest and need <= 3 then
		need = 20 -- wait for enough ores to make something bigger than a dagger
	end
	return total >= need
end

-- Mining vs mobs when both are on: take turns in blocks so ores still come in.
-- A pending forge quest with too few ores always mines.
-- Quests can switch farming on by themselves (kill X zombies / get Y ore).
local turnStart, turnMobs = os.clock(), true
local function chooseFarm()
	local mobs = settings.autoMobs or QS.wantMobs
	local mine = settings.autoMine or QS.wantMine
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
		local userOther = (QS.wantMobs and not QS.wantMine and settings.autoMine)
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
	function Best.pick(itemType, maxOres, exactN)
		local types = {}
		for name, n in pairs((oreCounts())) do
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
					if n >= 3 and all and (not exactN or n == exactN) then
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
		for name, n in pairs((oreCounts())) do
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
		for name, n in pairs((oreCounts())) do
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
		if settings.forgeBest then
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
	if settings.forgeBest then
		-- Slider left at the old default (3) would cap "best" at a dagger: treat <=3 as "no cap" (60).
		local cap = tonumber(settings.forgeOres) or 3
		cap = cap > 3 and cap or 60
		local pick, got = Best.pick(itemType or settings.forgeType, cap)
		if got >= 3 then
			return pick, got
		end
	end
	local want = math.max(3, tonumber(settings.forgeOres) or 3)
	local ores = oreCounts()
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
	local itemType = forgeTypeNow()
	local ores, got = pickForgeOres(itemType)
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
	end)
	local oreNote = {}
	for name, n in pairs(ores) do
		oreNote[#oreNote + 1] = tostring(name) .. ' x' .. tostring(n)
	end
	table.sort(oreNote)
	G.FTLastForge = itemType .. ': ' .. table.concat(oreNote, ', ')
	task.spawn(function()
		pcall(function()
			FC:ChangeSequence('Melt')
		end)
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
		if os.clock() - t2 > 6 and FC.Sequence == 'OreSelect' then
			rejected = true
			break
		end
		task.wait(0.5)
	end
	if rejected then
		setStatus('forge was rejected — reopening it next time [' .. tostring(G.FTLastForge):sub(1, 160) .. ']')
	end
	task.wait(2)
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
		if forgeFails >= 2 then
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
G.FTAtkDur = G.FTAtkDur or {}
local Attack = { flag = setmetatable({}, { __mode = 'k' }), off = setmetatable({}, { __mode = 'k' }), dur = G.FTAtkDur }
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
				attackWarn[m] = t0
				Attack.flag[m] = d
				Attack.off[m] = nil
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
	local _, _, hum = char()
	return hum ~= nil and h.MaxHealth > hum.MaxHealth * 12
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
	local filter = QS.mobTarget or settings.mobFilter
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
			local cap = tonumber(settings.maxMobHp) or 0
			if h and r and h.Health > 0 and m:GetAttribute('KillCredited') ~= true
				and mobMatches(baseName(m.Name), filter)
				and (cap <= 0 or h.MaxHealth <= cap)
				and h.MaxHealth < 1e8 and not m.Name:find('Dummy') -- training dummies never die
				and not Deadly.is(m) -- never pick a fight with a mob that has killed us (quests included)
				and not string.find(m.Name, 'Bomber', 1, true) -- (they explode in melee range)
				and not Lava.at(r.Position) -- (standing in lava: we would have to stand in it too)
			then
				list[#list + 1] = { m = m, h = h, r = r, d = (r.Position - hrp.Position).Magnitude, big = mobTooBig(h) }
			end
		end
	end
	if filter == 'Any' then
		local small = {}
		for _, e in ipairs(list) do
			if not e.big then
				small[#small + 1] = e
			end
		end
		if #small > 0 then
			list = small
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	return list
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
		if pct >= 90 then
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
				learn()
			end
		end)
	end)
	local hpConn, hpChar
	local function watchHealth()
		local c, _, hum = char()
		if c and hum and c ~= hpChar then
			hpChar = c
			if hpConn then
				hpConn:Disconnect()
			end
			local last = hum.Health
			hpConn = hum.HealthChanged:Connect(function(h)
				if h < last - 0.5 then
					learn()
				end
				last = h
			end)
			blockConns[#blockConns + 1] = hpConn
		end
	end

	local stopping = false
	local function holdBlock(untilT)
		local tc = controller('ToolController')
		local ch = LocalPlayer.Character
		if not tc or not (ch and ch:FindFirstChild('Weapon')) then
			return
		end
		blockUntil = math.max(blockUntil, untilT)
		if not tc.isBlocking then
			pcall(tc.StartBlock, tc)
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
				pcall(tc.StopBlock, tc)
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
		pending[#pending + 1] = { id = id, t = t0, m = m, r = r, hitAt = hitAt }
		-- Block / parry style only (hit & run dodges instead).
		if settings.combatStyle ~= 'Block / parry' or not settings.autoBlock or not c:FindFirstChild('Weapon') then
			return
		end
		if (r.Position - hrp.Position).Magnitude > 16 then
			return
		end
		local lead = (tonumber(settings.parryLead) or 20) / 100
		local startIn = math.max(0, hitAt - lead) - (os.clock() - t0)
		task.delay(math.max(0, startIn), function()
			holdBlock(t0 + hitAt + 0.3)
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
				if (not h or h.Health > 0) and (p.r.Position - hrp.Position).Magnitude <= radius then
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
			task.wait(2)
		end
	end)
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
	if dodgeOnce(fromPos, distOverride) then
		return true
	end
	if distOverride and distOverride > 14 then
		return dodgeOnce(fromPos, distOverride * 0.6) or dodgeOnce(fromPos, nil)
	end
	return false
end
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
local Hazard = { seen = {}, n = { proj = 0, ground = 0 }, last = 0 }
G.FTHazard = Hazard.n
pcall(function()
	if G.FTHazardConn then
		G.FTHazardConn:Disconnect()
	end
	G.FTHazardConn = workspace:WaitForChild('Debris', 10).ChildAdded:Connect(function(x)
		if x:IsA('BasePart') or x:IsA('Model') then
			Hazard.seen[x] = { t = os.clock() }
		end
	end)
end)
-- Step off a projectile's line. (Not dodgeFrom: that picks whichever direction ends up furthest
-- from mobs, which can be straight along the line - measured: a 12 stud "dodge" that still let the
-- shot pass 2.4 studs from us.)
function Hazard.sidestep(hrp, perp)
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
function Hazard.step()
	local _, hrp, hum = char()
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	local me = hrp.Position
	for x, e in pairs(Hazard.seen) do
		if not x.Parent or now - e.t > 6 then
			Hazard.seen[x] = nil
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
							if Hazard.sidestep(hrp, perp) then
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
		if not forging and next(Hazard.seen) and (settings.autoMine or settings.autoMobs or settings.autoAbyss
			or settings.autoCompleteQuests or QS.wantMobs or QS.wantMine) then
			pcall(Hazard.step)
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
					if r and h and h.Health > 0 and (r.Position - hrp.Position).Magnitude < 22 then
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
		return forced ~= nil or settings.autoMobs or QS.wantMobs
	end
	if not (LocalPlayer.Backpack:FindFirstChild('Weapon') or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('Weapon'))) then
		setStatus('no weapon — forge one first')
		return false
	end
	if lowHp() then
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
	local hitRun = settings.combatStyle == 'Hit & run'
	local swingIdx, lastSwingAt, nextSwingAt, sentAt, ownAnimAt, animWorks = 0, 0, 0, nil, 0, false
	local strikeAt, strikeEnd = nil, 0 -- when our hitbox comes out / is gone again
	local STRIKE_LEAD = 0.12 -- be in place this long before the hitbox (position has to reach the server)
	-- (set per swing in swingTick: 0.35s for slow weapons - measured: hopping in 0.12s before a
	-- scythe's hitbox, from 30 studs out, missed 4 swings in 5)
	local UNSAFE_FROM, UNSAFE_TO = 0.22, 0.85 -- seconds into a mob's wind-up during which we must not be near it
	local animConn
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
	local function strikeSafe(reach, ahead)
		local at = os.clock() + (ahead or 0)
		for m, t in pairs(attackWarn) do
			local r = m.Parent and mobRoot(m)
			if r and target.r.Parent and (r.Position - target.r.Position).Magnitude <= math.max(reach + 10, 22) then
				local age = at - t
				if age > UNSAFE_FROM and at < math.max(t + UNSAFE_TO, Attack.ends(m, t)) then
					return false
				end
			end
		end
		return true
	end
	G.FTSwingLog = G.FTSwingLog or {}
	local pend
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
		if now < pend.at - 0.3 then
			pend.hp = target.h.Health
		elseif now <= pend.at + pend.hd + 0.05 then
			pend.far = math.max(pend.far or 0, gap)
			pend.nearest = math.min(pend.nearest or 999, gap)
		end
		if flush or now > pend.at + pend.hd + 0.45 then
			local log = G.FTSwingLog
			log[#log + 1] = ('%s#%d ht=%.2f gap %.0f..%.0f reach=%.0f %s'):format(target.m.Name:gsub('%d+$', ''), pend.idx, pend.ht,
				pend.nearest or -1, pend.far or -1, pend.reach, target.h.Health < (pend.hp or target.h.Health) - 0.5 and 'HIT' or 'miss')
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
	local function hopIn(h, reach)
		-- The hitbox only reaches ~reach studs in front of us: stand well inside it, facing the mob.
		local cf = standFor(math.clamp(reach - 3.5, 1.5, 4))
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
		h.CFrame = cf
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
		if strikeAt or now < nextSwingAt or Block.active() or not target.r.Parent then
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
		STRIKE_LEAD = ht >= 0.6 and 0.42 or 0.12
		if hitRun and not (strikeSafe(reach, ht - STRIKE_LEAD) and strikeSafe(reach, ht + hd)) then
			return -- this swing's hitbox would come out while a mob's hit is landing: hold it a moment
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
			if lateEnd then
				if now + ht < lateEnd + 0.05 then
					return -- our hitbox would come out while it is still attacking: start a bit later
				end
			elseif engaged and not (lastOff and now - lastOff < 0.6) and waited < 1.5 then
				return -- nothing to answer yet: wait for its next wind-up
			end
		end
		swingIdx = idx
		swing(tool)
		lastSwingAt, sentAt = now, now
		-- (a great axe's swing plays for 1.6s but its cooldown says 1.5: a press in between is dropped)
		local dur = combat and type(combat.AttackDuration) == 'table' and tonumber(combat.AttackDuration[idx]) or 0
		nextSwingAt = now + math.max(cd, dur) + 0.05
		strikeAt, strikeEnd = now + ht, now + ht + hd + (ht >= 0.6 and 0.22 or 0.1)
		track(true) -- (close the books on the previous swing)
		pend = { at = now + ht, hd = hd, ht = ht, idx = idx, reach = reach, hp = target.h.Health }
	end
	local retargetAt, regroupAt = os.clock() + 1, 0
	while alive and allowed() and target.m.Parent and target.h.Health > 0 and os.clock() - t0 < 45 do
		if lowHp() then
			retreatAndHeal()
			return true
		end
		-- Several mobs: do not chase the one we started on while another is right on top of us.
		-- (only between swings, so a swing in flight still lands on what it was aimed at)
		if not forced and not strikeAt and os.clock() >= retargetAt then
			retargetAt = os.clock() + 0.5
			local _, h0 = char()
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
		elseif settings.combatStyle == 'Block / parry' and settings.autoBlock then
			-- Hold block for the whole warned swing (halves the hit, parries it when the timing lines up).
			local wPos, wEnd = attackThreat(reach + 6)
			if wPos then
				Block.hold(wEnd - os.clock())
			end
		end
		local now = os.clock()
		local kite = false
		if hitRun and target.r.Parent then
			-- only in a crowd: against one mob we stay in reach and dodge just its wind-ups
			kite = mobsNear(target.r.Position, 25) >= 2
		end
		local inRange = hrp and (hrp.Position - target.r.Position).Magnitude <= reach - 1 + math.max(target.r.Size.X, target.r.Size.Z) / 2
		local striking = hitRun and strikeAt and now >= strikeAt - STRIKE_LEAD and now <= strikeEnd
		if striking and hrp and strikeSafe(reach, 0) and not (rem and rem > 0 and rem < 0.25) then
			-- Our hitbox is (about to be) out and no hit is landing on us: be on the mob for it.
			if not inRange then
				hopIn(hrp, reach)
			else
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(target.r.Position.X, hrp.Position.Y, target.r.Position.Z))
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
					if strikeAt and n2 >= strikeAt - STRIKE_LEAD and n2 <= strikeEnd and strikeSafe(reach, 0) then
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
				local w4 = attackThreat(14)
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
				tweenTo(standFor(hitRun and 14 or math.clamp(reach - 3.5, 1.5, 4)), { abort = function()
					return not allowed() or not target.m.Parent or target.h.Health <= 0
				end })
			end
			tool = equip('Weapon')
		else
			if hrp then
				if not hitRun and os.clock() >= regroupAt then
					regroupAt = os.clock() + 1.5
					if mobsNear(hrp.Position, 14) >= 3 then
						local cf = standFor(math.clamp(reach - 3.5, 1.5, 4))
						if (cf.Position - hrp.Position).Magnitude > 6 then
							hrp.CFrame = cf
							hrp.AssemblyLinearVelocity = Vector3.zero
						end
					end
				end
				-- keep facing the mob every frame: the hitbox comes out in front of us a moment after the swing
				hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(target.r.Position.X, hrp.Position.Y, target.r.Position.Z))
			end
			if Block.active() then
				task.wait(0.05) -- holding block through an incoming hit
			else
				if not hitRun then
					swingTick(reach)
				end
				task.wait()
			end
		end
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
	local cap = tonumber(settings.maxMobHp) or 0
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
	if pct < math.max(40, tonumber(settings.retreatHp) or 0) then
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
			if pk >= 60 then
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
			if p2 >= 90 then
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
	else
		setStatus(th.m.Name .. ' is too strong to fight — moving to another rock')
		pcall(dodgeFrom, th.r.Position)
		task.wait(0.3)
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
		for _, c in ipairs(cmds.check) do
			pcall(function()
				DS:RunCommand(c)
			end)
			task.wait(0.2)
		end
		for _, c in ipairs(cmds.finish) do
			pcall(function()
				DS:RunCommand(c)
			end)
			task.wait(0.2)
		end
		if settings.autoAcceptQuests then
			for _, g in ipairs(cmds.give) do
				if g.quest and eligible(g.quest) then
					pcall(function()
						DS:RunCommand(g.cmd)
					end)
					setStatus('accepted quest ' .. tostring(g.quest))
					task.wait(0.3)
				end
			end
		end
		task.wait(0.3)
		closeDialogue()
		task.wait(0.5)
		if questSig() == before then
			backoff[bk] = { n = (b and b.n or 0) + 1, t = os.clock() }
		else
			backoff[bk] = nil
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
		if n and item then
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
			return q.Npc and visit(q.Npc, 'deliver') or false
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
			local focusId = settings.focusQuest ~= 'Auto' and d.Quests[settings.focusQuest] ~= nil and settings.focusQuest or nil
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
				local ra = QuestData and QuestData[a] and QuestData[a].Repeatable and 1 or 0
				local rb = QuestData and QuestData[b] and QuestData[b].Repeatable and 1 or 0
				if ra ~= rb then
					return ra < rb
				end
				return tostring(a) < tostring(b)
			end)
			local nowQ = os.clock()
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
				elseif nowQ - lockAt > 360 then
					stalled[lockId] = nowQ + 600
					setStatus(('quest %s: no progress for 6 min — trying another one for a while'):format(tostring(lockId)))
					lockId = nil
				end
			end
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
						if t == 'Kill' then
							QS.wantMobs = true
							engaged = true
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
							QS.wantMine = true
							engaged = true
							if t == 'Mine' and target ~= 'Any' and target ~= 'Rock' then
								G.FTQuestRock = G.FTQuestRock or target
							end
							if pri then
								QS.storyMine = true
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
							if target == 'None' or parseBring(desc) then
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
				stalled[lockId] = os.clock() + 300
				lockId = nil
			end
		end
		-- A quest that needs ore: don't sit on a 10,000 HP Lucky Block.
		G.FTQuestWantsOre = QS.wantMine
		-- (new quests are only looked for when there is no quest left to work on)
		if settings.autoAcceptQuests and lockId == nil and os.clock() - lastAcceptScan > 20 then
			lastAcceptScan = os.clock()
			local prox = workspace:FindFirstChild('Proximity')
			for _, npc in ipairs(prox and prox:GetChildren() or {}) do
				local isTalker = DialogueNpcs and (DialogueNpcs[npc.Name] or false)
				-- Only scout NPCs reasonably close (some sit thousands of studs away in side areas).
				local near = false
				pcall(function()
					local _, hrp = char()
					near = hrp and (npc:GetPivot().Position - hrp.Position).Magnitude <= (tonumber(settings.questRange) or 1000)
				end)
				if isTalker and near and npc:IsA('Model') then
					local tree = treeOf[npc.Name]
					local want = false
					if not tree then
						want = not visited[npc.Name] or os.clock() - visited[npc.Name] > 900
					else
						for _, g in ipairs(treeCommands(tree).give) do
							if g.quest and eligible(g.quest) then
								want = true
							end
						end
						want = want and (not visited[npc.Name] or os.clock() - visited[npc.Name] > 60)
					end
					if want and visit(npc.Name, 'looking for quests') then
						return true
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
	local tried = {}
	pcall(function()
		if isfile(triedPath) then
			for line in readfile(triedPath):gmatch('[^\r\n]+') do
				tried[line] = true
			end
		end
	end)
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
			for _, code in ipairs(codeList()) do
				if not tried[code] and not redeemed[code] and not redeemed[code:upper()] then
					tried[code] = true
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
						for c in pairs(tried) do
							lines[#lines + 1] = c
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
	local function cardScore(card)
		if type(card) ~= 'table' then
			return -1
		end
		local text = string.lower(tostring(card.Text or ''))
		-- Never take a card with a downside (all Cursed cards, Deep Pact, anything with a Cost or
		-- that makes enemies stronger / you take more damage / lowers a stat).
		if card.Cost ~= nil or card.Enemy ~= nil or card.Rarity == 'Cursed'
			or text:find('more damage') or text:find('stronger') or text:find('%-%d') then
			return -1000
		end
		local score = RANK[tostring(card.Rarity)] or 5
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
		G.FTAbyssPickedConn = AS.CardPicked:Connect(function()
			lastPicked = os.clock()
		end)
		G.FTAbyssCardConn = AS.CardOffer:Connect(function(offer)
			if not (settings.autoCards or settings.autoAbyss) or type(offer) ~= 'table' or type(offer.Cards) ~= 'table' then
				return
			end
			local offeredAt = os.clock()
			task.wait(1)
			-- Reroll every card that has a downside (3 rerolls per slot), then take the best one.
			local cards = table.clone(offer.Cards)
			for slot = 1, #cards do
				for _ = 1, 3 do
					if os.clock() - offeredAt > 9 then
						break
					end
					if cardScore(A and A.GetCard and A.GetCard(cards[slot])) > -1000 then
						break
					end
					local ok, a, b, c = pcall(function()
						return AS:RerollCards(slot):await()
					end)
					local newId = ok and a and b and c or nil
					if newId == nil then
						break -- out of rerolls
					end
					cards[slot] = newId
					task.wait(0.3)
				end
			end
			local best, bestScore = pickFrom({ Cards = cards })
			if best == nil then
				return
			end
			if bestScore <= -1000 then
				pcall(function()
					AS:SkipCards():await()
				end)
				setStatus('abyss: only cards with downsides — skipped')
				return
			end
			local card = A and A.GetCard and A.GetCard(best)
			-- Retry a few times in case the first call lands before the menu is ready.
			for _ = 1, 4 do
				pcall(function()
					AS:PickCard(best)
				end)
				task.wait(1.2)
				if lastPicked and lastPicked >= offeredAt then
					break
				end
			end
			setStatus('abyss: took ' .. tostring(card and card.Name or best))
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
			return false
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
			setStatus('abyss: teleporting to the Abyss lobby')
			pcall(function()
				service('AbyssService'):Enter():await()
			end)
			local t0 = os.clock()
			while os.clock() - t0 < 8 do
				task.wait(0.5)
				local _, h2 = char()
				if h2 and (h2.Position - pos).Magnitude < 250 then
					break
				end
			end
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
local Tab = Window:AddTab('Main', 'pickaxe')
local FarmBox = Tab:AddLeftGroupbox('Mining & selling')
local ForgeBox = Tab:AddRightGroupbox('Forge')
local MobBox = Tab:AddLeftGroupbox('Mobs')
local InfoBox = Tab:AddRightGroupbox('Status')

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

bindToggle(FarmBox, 'FTAutoMine', 'autoMine', 'Auto mine', 'Tweens to the nearest rock and mines it. Rock types your pickaxe cannot damage are skipped.')
local zoneDD = bindDropdown(FarmBox, 'FTMineZone', 'mineZone', 'Mine in', zoneNames())
bindToggle(FarmBox, 'FTSkipLucky', 'skipLucky', 'Skip Lucky Blocks', 'Lucky Blocks have 10,000 HP.')
bindToggle(FarmBox, 'FTAutoSell', 'autoSell', 'Auto sell ores', 'Sells your ores at Greedy Cey when the bag reaches the % below.')
bindSlider(FarmBox, 'FTSellAt', 'sellAt', 'Sell when bag is % full', 20, 100)
bindToggle(FarmBox, 'FTAutoSellGear', 'autoSellGear', 'Auto sell spare gear', 'Sells weapons and armor at Marbles once 3+ spares pile up. Never sells what you are wearing, the best item of each slot (weapon / helmet / chestplate / leggings), favorited items or pickaxes.')
FarmBox:AddButton('Sell ores now', function()
	sellOres()
end)

bindToggle(ForgeBox, 'FTAutoForge', 'autoForge', 'Auto forge', 'When you have enough ores: tweens to the forge, puts them in and plays every minigame perfectly.')
bindToggle(ForgeBox, 'FTForgeWhenFull', 'forgeWhenFull', 'Only forge when the stash is full', 'With Auto forge on: keeps mining until the stash is full, then forges until the stash is used up before mining again.')
bindDropdown(ForgeBox, 'FTForgeType', 'forgeType', 'Forge', { 'Weapon', 'Armor' })
bindToggle(ForgeBox, 'FTForgeAlternate', 'forgeAlternate', 'Alternate weapon / armor', 'Starts with the type picked above, then switches after every item it makes.')
bindDropdown(ForgeBox, 'FTForgePiece', 'forgePiece', 'Aim for piece', Piece.names(), 'The game rolls the piece from how many ores go in, so it cannot be forced. This waits for the ore count with the best odds for the piece you pick, forges with exactly that many, and repeats. Overrides Weapon / Armor above. "Ores per forge (max)" still caps it.')
bindSlider(ForgeBox, 'FTForgeOres', 'forgeOres', 'Ores per forge (max)', 3, 60, 'With "Best gear" on this is the most it will use; otherwise it uses exactly this many, most plentiful ores first.')
bindToggle(ForgeBox, 'FTForgeBest', 'forgeBest', 'Best gear (smart ore pick)', 'Uses your highest-multiplier ores and the ore count that gives the strongest expected item (bigger weapon/armor types vs. keeping the average multiplier high).')
bindSlider(ForgeBox, 'FTForgeKeep', 'forgeKeep', 'Keep of each ore (auto sell)', 0, 20, 'With auto forge on, auto sell leaves this many of each ore for forging.')
do
	local oreList = {}
	for name in pairs(ORE_NAMES) do
		oreList[#oreList + 1] = name
	end
	table.sort(oreList)
	if type(settings.keepOres) ~= 'table' then
		settings.keepOres = {}
	end
	local keepDD = ForgeBox:AddDropdown('FTKeepOres', { Text = 'Save these ores (never sell / forge)', Values = oreList, Multi = true, Default = settings.keepOres, AllowNull = true, Tooltip = 'Picked ores are kept: auto sell and auto forge leave them alone (e.g. Galgite, Heavenite).' })
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
ForgeBox:AddButton('Forge now', function()
	forgeOnce()
end)

bindToggle(MobBox, 'FTAutoMobs', 'autoMobs', 'Auto kill mobs', 'Tweens to the nearest mob and fights it with your Weapon.')
local mobDD = bindDropdown(MobBox, 'FTMobFilter', 'mobFilter', 'Target', mobNames())
bindSlider(MobBox, 'FTRetreatHp', 'retreatHp', 'Retreat to spawn below % health', 0, 90, 'Goes back to spawn and waits until health is 90% before fighting again.')
-- The slider used to stop at 2000, which silently hid every bigger mob (island 3: Elite Orc,
-- Crystal Golem, Yeti, Demonic / Prismarine Spider...). Left at that old maximum = no limit.
if tonumber(settings.maxMobHp) == 2000 then
	settings.maxMobHp = 0
end
bindSlider(MobBox, 'FTMaxMobHp', 'maxMobHp', 'Only fight mobs with max HP up to', 0, 20000, '0 = any mob. Mobs above this are ignored completely (not fought, not in quests).')
-- (a safety setting, not a feature toggle: it keeps its saved value across loads, default on)
settings.fleeDeadly = settings.fleeDeadly ~= false
MobBox:AddToggle('FTFleeDeadly', { Text = 'Avoid mobs that killed me', Default = settings.fleeDeadly, Tooltip = 'Any mob type that kills you, or takes about half your health in one hit, goes on a list. The script then never fights that type, skips rocks near it and moves away when one comes close. Turn off (or use the button below) once your gear is better.' }):OnChanged(function(v)
	settings.fleeDeadly = v == true
	save()
end)
MobBox:AddButton('Forget deadly mobs', function()
	local was = table.concat(Deadly.list(), ', ')
	Deadly.clear()
	setStatus('deadly list cleared' .. (was ~= '' and (' (was: ' .. was .. ')') or ''))
end)
bindDropdown(MobBox, 'FTCombatStyle', 'combatStyle', 'Combat style', { 'Hit & run', 'Block / parry' }, 'Hit & run: steps out of reach right before each attack lands, then comes back in to hit. Block / parry: stands and blocks. (Floating over mobs was tested: their attacks reach straight up, so it is not offered.)')
bindSlider(MobBox, 'FTDodgeDist', 'dodgeDist', 'Dodge distance (studs)', 8, 30, 'How far it steps away from an incoming attack.')
bindToggle(MobBox, 'FTAutoAbyss', 'autoAbyss', 'Auto Abyss', 'Goes to the Abyss cage, starts a run, picks a card each floor (see below) and fights every floor. Re-enters when you come back.')
bindToggle(MobBox, 'FTAutoCards', 'autoCards', 'Auto pick abyss cards', 'Picks a card for you after each floor, even when you play the Abyss yourself.')
bindDropdown(MobBox, 'FTCardFocus', 'cardFocus', 'Card priority', { 'Best overall', 'Damage', 'Survival', 'Loot' }, 'Best overall: rarest card (Abyssal > Fusion > Epic > Rare > Common). Damage / Survival / Loot: that kind of card first, then rarity.')
bindToggle(MobBox, 'FTAutoBlock', 'autoBlock', 'Auto block (F)', 'Blocks right before a mob\'s attack lands, then goes back to swinging.')
bindSlider(MobBox, 'FTParryLead', 'parryLead', 'Parry lead (x10 ms before the hit)', 5, 50, 'Blocks this long before each attack lands. It learns every mob attack\'s timing by itself; ~20 parries best. Raise it if hits get through, lower it if you block but don\'t parry.')
bindSlider(MobBox, 'FTSwitchMins', 'switchMins', 'With auto mine on, switch every (min)', 1, 15, 'Mobs and mining take turns so you still get ores to forge with.')
local QuestBox = Tab:AddRightGroupbox('Quests')

-- Race reroll: spends spins on the current race slot until the race is at least the rarity picked.
-- A button, not a toggle: every roll replaces your race and cannot be undone.
do
	local RaceBox = Tab:AddLeftGroupbox('Race reroll')
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
	bindSlider(RaceBox, 'FTRaceKeepSpins', 'raceKeepSpins', 'Keep this many spins', 0, 200, 'Rerolling also stops when only this many spins are left.')
	local rolling = false
	RaceBox:AddButton('Reroll race until that rarity', function()
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
			while alive and rolling do
				local name, rarity, spins = raceInfo()
				if (rank[rarity] or 0) >= want then
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
				local ok, got = pcall(function()
					local _, r = svc:Reroll(banner):await()
					return r
				end)
				if ok and got then
					used += 1
					fails = 0
					-- wait for our data to show the new race before deciding again
					local t0 = os.clock()
					while os.clock() - t0 < 2 and select(3, raceInfo()) == spins do
						task.wait(0.1)
					end
					local n2, r2, s2 = raceInfo()
					setStatus(('race reroll #%d: %s (%s) — %d spins left'):format(used, tostring(n2), tostring(r2), s2))
					task.wait(0.4)
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
bindToggle(QuestBox, 'FTAutoPickaxe', 'autoPickaxe', 'Auto buy best pickaxe', 'Buys the best pickaxe sold on your current island that you can afford and do not own (gold only, skips locked ones), then equips it.')
QuestBox:AddButton('Buy best pickaxe now', function()
	task.spawn(function()
		local ok, bought = pcall(Quest.buyBestPickaxe)
		if ok and not bought then
			setStatus('no better pickaxe to buy on this island right now')
		end
	end)
end)
bindToggle(QuestBox, 'FTClaimBoard', 'claimBoard', 'Claim quest board rewards', 'Claims finished Daily / Weekly / Monthly board quests.')
bindSlider(QuestBox, 'FTQuestRange', 'questRange', 'Look for new quests within (studs)', 200, 5000, 'NPCs farther than this are not visited just to check for quests (quest turn-ins and talk objectives still go anywhere).')
bindToggle(QuestBox, 'FTAutoMail', 'autoMail', 'Auto claim mail & rewards', 'Every minute: claims all mail, level rewards, index (codex) rewards, and free seasonal-event rewards (event quests, milestones, altar daily).')
bindToggle(QuestBox, 'FTAutoOffer', 'autoOffer', 'Auto offer altar shards', 'Twilight War altar: spends your side\'s shards on offers (x10 while you can, then x1) and takes the free daily gifts.')
bindToggle(QuestBox, 'FTAutoDaily', 'autoDaily', 'Auto claim daily login', 'Claims the daily login reward when it is ready.')
bindToggle(QuestBox, 'FTAutoCodes', 'autoCodes', 'Auto redeem codes', 'Tries each known code once per account. Add new codes to PlayerTools/forgecodes.txt (one per line).')
bindToggle(ForgeBox, 'FTAutoEnhance', 'autoEnhance', 'Auto enhance equipped gear', 'Spends essences and gold to enhance the weapon and armor you are wearing, one level at a time. A failed enhance drops the item a level and can cost a rune slot; use the chance slider below to only take safer rolls. Never uses medallions.')
-- The limit used to default to 100%, which stopped every item at +3 (+3 -> +4 is a 70% roll).
-- No limit by default now; whatever was saved before (the slider could not go under 50) is
-- cleared once.
if not settings.enhanceNoLimitV2 then
	settings.enhanceNoLimitV2 = true
	settings.enhanceMinChance = 0
	save()
end
bindSlider(ForgeBox, 'FTEnhanceMinChance', 'enhanceMinChance', 'Only enhance at this chance or better (%)', 0, 100, '0 = no limit: keeps trying whatever the odds. At 100 an enhance can never fail, which stops at +3.')
bindSlider(ForgeBox, 'FTEnhanceMaxLevel', 'enhanceMaxLevel', 'Stop enhancing at +', 1, 9, 'Items already at this level are left alone.')
bindToggle(ForgeBox, 'FTAutoEquip', 'autoEquip', 'Auto equip better gear', 'After forging, equips the item if its slot is empty or its base stats beat what you have on. Enhancement levels are ignored, so a better new piece replaces an upgraded old one.')
MobBox:AddButton('Refresh lists', function()
	pcall(function()
		mobDD:SetValues(mobNames())
	end)
	pcall(function()
		zoneDD:SetValues(zoneNames())
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
	local dd = InfoBox:AddDropdown('FTIsland', { Text = 'Travel to island', Values = list, Default = list[2] or list[1], AllowNull = false })
	InfoBox:AddButton('Travel', function()
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

statusLabel = InfoBox:AddLabel('Status: idle')
local statsLabel = InfoBox:AddLabel('')
bindToggle(InfoBox, 'FTNoBlur', 'noBlur', 'No blur', 'Keeps the game\'s blur effects (forge / menus / dialogue) switched off.')
bindSlider(InfoBox, 'FTTweenSpeed', 'tweenSpeed', 'Tween speed (studs/s)', 20, 120, 'Too fast can get you snapped back.')
bindSlider(InfoBox, 'FTWalkSpeed', 'walkSpeed', 'Walk speed while pathing (0 = game default)', 0, 150, 'Speed used when the script walks around walls. The game walks at 13 and runs at 24.')
InfoBox:AddToggle('FTAutoload', { Text = 'Autoload on this account', Default = settings.autoload == true }):OnChanged(function(v)
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
			if settings.autoAbyss and Abyss.inRun() then
				-- In the Abyss: just fight (no quests / forging in there).
				QS.wantMobs = true
				if #mobList() > 0 then
					fightOnce()
				else
					setStatus('abyss: waiting for the next floor')
					task.wait(0.5)
				end
				return
			end
			if Abyss.step() then
				return
			end
			if os.clock() - lastQuestStep > 3 then
				lastQuestStep = os.clock()
				Rewards.step()
				if Quest.step() then
					return
				end
			end
			local farm = chooseFarm()
			if forgeNeeded() then
				forgeOnce()
			elseif sellNeeded() then
				sellOres()
			elseif Quest.gearSellNeeded() then
				Quest.sellGear()
			elseif farm == 'mobs' and #mobList() > 0 then
				fightOnce()
			elseif farm == 'mine' or (farm == 'mobs' and (settings.autoMine or QS.wantMine)) then
				if not mineOnce() then
					task.wait(1)
				end
			else
				setStatus('idle')
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

-- Auto enhance: the gear being worn goes up one level at a time while the game's own success
-- chance is at least the user's limit and the essences + gold are there. (Game rules: a failed
-- enhance takes the item down a level, and at +3 / +6 / +9 it also loses a rune slot.)
task.spawn(function()
	local pauseUntil = 0
	local gap = 5
	while alive and G.SB2ForgeToolsToken == token do
		task.wait(gap)
		gap = 10 -- (right after a successful enhance the next one follows in 1.5s)
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
				for slot, worn in pairs(d.Equipped or {}) do
					local it = type(worn) == 'table' and worn.GUID and (fresh[worn.GUID] or worn) or nil
					local known = it and math.max(tonumber(it.Upgrade) or 0, G.FTEnhanced[it.GUID] or 0) or 0
					if it and it.Type and known < maxLv then
						local lv = known
						local okC, ch = svc:PreviewChance(it.GUID, {}, nil):await()
						local okR, req = svc:GetUpgradeRequirements(it):await()
						local chance = okC and type(ch) == 'table' and tonumber(ch.Final) or 0
						local can = okR and type(req) == 'table' and type(req.materials) == 'table' and chance >= minCh
							and (tonumber(d.Gold) or 0) >= (tonumber(req.totalPrice) or math.huge)
						if can then
							for _, m in ipairs(req.materials) do
								if (have[m.material.Name] or 0) < (tonumber(m.quantity) or 0) then
									can = false
									-- (it used to just sit there: say what is missing, once per item and level)
									G.FTEnhanceTold = G.FTEnhanceTold or {}
									local key = it.GUID .. ':' .. lv .. ':' .. m.material.Name
									if not G.FTEnhanceTold[key] then
										G.FTEnhanceTold[key] = true
										local msg = ('%s +%d -> +%d needs %d %s (you have %d)'):format(it.Type, lv, lv + 1,
											tonumber(m.quantity) or 0, m.material.Name, have[m.material.Name] or 0)
										statusLog[#statusLog + 1] = os.date('%H:%M:%S ') .. 'auto enhance waiting: ' .. msg
										pcall(function()
											game:GetService('StarterGui'):SetCore('SendNotification', { Title = 'Auto enhance waiting', Text = msg, Duration = 8 })
										end)
									end
								end
							end
						end
						if can then
							local okE, res = svc:EnhanceEquipment(it.GUID, nil, nil):await()
							local nlv = lv
							if okE and type(res) == 'table' and tonumber(res.newLevel) then
								nlv = tonumber(res.newLevel)
								G.FTEnhanced[it.GUID] = nlv
							end
							if nlv > lv then
								gap = 1.5
								setStatus(('enhanced %s to +%d (%.0f%% chance)'):format(it.Type, nlv, chance))
							elseif nlv < lv then
								setStatus(('enhancing %s failed: +%d -> +%d'):format(it.Type, lv, nlv))
							else
								pauseUntil = os.clock() + 300
								setStatus(('the game did not enhance %s — trying again in 5 minutes'):format(it.Type))
							end
							return -- one item per round
						end
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
