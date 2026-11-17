--[[
	Forge Tools - fight report. For testing Auto kill mobs on someone else's connection.

	  loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/forgetools/main/diag.lua"))()

	It updates and starts Forge Tools through the normal loader (so it always runs the newest build),
	then watches the fights for a few minutes - ping, how long a block takes to come up, parries,
	hits taken, kills, what the bot was doing, any errors - and saves a report:
	    workspace/PlayerTools/forgetools_report.txt
	A short summary is copied to the clipboard. Send the report file to whoever asked for it.

	Turn on Auto kill mobs (and stand where the mobs are) before or right after running it.
	Options, set before running:  getgenv().FTDiagSecs = 300  (how long to watch, default 180)
	No names, ids or account details go in the report.
]]

local G = getgenv()
local Players = game:GetService('Players')
local LP = Players.LocalPlayer
local SECS = math.clamp(tonumber(G.FTDiagSecs) or 180, 30, 1800)
local OUT = 'PlayerTools/forgetools_report.txt'

local function notify(text, dur)
	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', { Title = 'Forge Tools report', Text = text, Duration = dur or 8 })
	end)
	warn('[ForgeTools report] ' .. tostring(text))
end

if G.FTDiagRunning then
	notify('Already recording - wait for it to finish.')
	return
end
G.FTDiagRunning = true

-- 1) newest build through the normal loader (skipped when it is already running)
if not G.FTDiagNoLoader then
	local before = G.SB2ForgeToolsBuild
	local ok, err = pcall(function()
		local src = game:HttpGet('https://raw.githubusercontent.com/NickB926/forgetools/main/loader.lua?t=' .. os.time())
		task.spawn(loadstring(src))
	end)
	if not ok then
		notify('Loader failed: ' .. tostring(err), 12)
	end
	local t0 = os.clock()
	while os.clock() - t0 < 60 and (not G.SB2ForgeToolsBuild or (before and G.SB2ForgeToolsBuild == before and os.clock() - t0 < 20)) do
		task.wait(0.5)
	end
end
if not G.SB2ForgeToolsBuild then
	G.FTDiagRunning = nil
	notify('Forge Tools did not start - nothing to record.', 12)
	return
end
task.wait(3)
notify(('Recording fights for %d s. Keep Auto kill mobs on.'):format(SECS))

-- 2) record
local T0 = os.clock()
local log, errs = {}, {}
local function L(s)
	if #log < 6000 then
		log[#log + 1] = ('%7.2f %s'):format(os.clock() - T0, s)
	end
end
local conns = {}
local function on(sig, f)
	local ok, c = pcall(function()
		return sig:Connect(f)
	end)
	if ok and c then
		conns[#conns + 1] = c
	end
end
local S = { hits = 0, dmg = 0, deaths = 0, kills = 0, dealt = 0, parry = 0, blockHit = 0, shines = 0, presses = 0, ups = 0, stuns = 0 }
local pings, lats, statusTime = {}, {}, {}
local lastPress

-- presses (wrapped, put back at the end)
local tc
pcall(function()
	setthreadidentity(2)
	tc = require(game:GetService('ReplicatedStorage').Shared.Packages.Knit).GetController('ToolController')
end)
local origS, origE
if tc then
	origS, origE = tc.StartBlock, tc.StopBlock
	tc.StartBlock = function(...)
		lastPress = os.clock()
		S.presses += 1
		L('press')
		return origS(...)
	end
	tc.StopBlock = function(...)
		L('let go')
		return origE(...)
	end
end

local function hookChar(c)
	local hum = c:WaitForChild('Humanoid', 10)
	local st = c:WaitForChild('Status', 10)
	if hum then
		local last = hum.Health
		on(hum.HealthChanged, function(h)
			if h < last - 0.5 then
				S.hits += 1
				S.dmg += last - h
				L(('HIT -%.0f (hp %.0f/%.0f)'):format(last - h, h, hum.MaxHealth))
			end
			last = h
		end)
		on(hum.Died, function()
			S.deaths += 1
			L('DIED')
		end)
	end
	if st then
		on(st.ChildAdded, function(x)
			if x.Name == 'Blocking' then
				S.ups += 1
				if lastPress and os.clock() - lastPress < 1 then
					lats[#lats + 1] = os.clock() - lastPress
					L(('guard up %.2fs after press'):format(os.clock() - lastPress))
				else
					L('guard up')
				end
			elseif x.Name == 'Stun' then
				S.stuns += 1
				L('stunned')
			end
		end)
	end
end
if LP.Character then
	task.spawn(hookChar, LP.Character)
end
on(LP.CharacterAdded, function(c)
	task.spawn(hookChar, c)
end)

pcall(function()
	on(workspace:WaitForChild('Debris', 5).ChildAdded, function(x)
		if x.Name == 'Parry' then
			S.parry += 1
			L('PARRY')
		elseif x.Name == 'BlockHit' then
			S.blockHit += 1
			L('blocked (no parry)')
		end
	end)
end)

-- mobs near us: shines, their health going down (our hits), deaths
local hookedMob = setmetatable({}, { __mode = 'k' })
local function near(m, r)
	local root = m:FindFirstChild('HumanoidRootPart')
	local me = LP.Character and LP.Character:FindFirstChild('HumanoidRootPart')
	return root and me and (root.Position - me.Position).Magnitude <= r, root and me and (root.Position - me.Position).Magnitude or -1
end
local function hookMob(m)
	if hookedMob[m] or not m:IsA('Model') or Players:GetPlayerFromCharacter(m) then
		return
	end
	hookedMob[m] = true
	local h = m:FindFirstChildOfClass('Humanoid')
	local name = (m.Name:gsub('%d+$', ''))
	if h then
		local last = h.Health
		on(h.HealthChanged, function(v)
			local isNear = near(m, 30)
			if isNear and v < last then
				S.dealt += last - v
			end
			if isNear and v <= 0 and last > 0 then
				S.kills += 1
				L('killed ' .. name)
			end
			last = v
		end)
	end
	on(m.DescendantAdded, function(d)
		if d.Name == 'ParryWindow' then
			local isNear, dist = near(m, 25)
			if isNear then
				S.shines += 1
				L(('%s attack flash (%.0f studs)'):format(name, dist))
			end
		end
	end)
end
local living = workspace:FindFirstChild('Living')
if living then
	for _, m in ipairs(living:GetChildren()) do
		pcall(hookMob, m)
	end
	on(living.ChildAdded, function(m)
		task.wait(0.5)
		pcall(hookMob, m)
	end)
end

on(game:GetService('LogService').MessageOut, function(msg, kind)
	if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) and tostring(msg):find('ForgeTools') and #errs < 60 then
		errs[#errs + 1] = ('%7.2f %s'):format(os.clock() - T0, tostring(msg):sub(1, 300))
	end
end)

-- status + ping, sampled
local lastStatus
local tEnd = T0 + SECS
while os.clock() < tEnd and G.FTDiagRunning do
	local okP, p = pcall(function()
		return LP:GetNetworkPing()
	end)
	if okP and tonumber(p) then
		pings[#pings + 1] = p * 1000
	end
	local st = tostring(G.FTStatus or '?')
	local key = st:gsub('%d+', '#'):sub(1, 60)
	statusTime[key] = (statusTime[key] or 0) + 0.5
	if st ~= lastStatus then
		lastStatus = st
		L('status: ' .. st:sub(1, 120))
	end
	task.wait(0.5)
end

for _, c in ipairs(conns) do
	pcall(function()
		c:Disconnect()
	end)
end
if tc and origS then
	tc.StartBlock, tc.StopBlock = origS, origE
end

-- 3) report
local function q(list, f)
	if #list == 0 then
		return 0
	end
	local s = table.clone(list)
	table.sort(s)
	return s[math.clamp(math.ceil(#s * f), 1, #s)]
end
local secs = os.clock() - T0
local set = G.FTSettings or {}
local onList = {}
for k, v in pairs(set) do
	if v == true then
		onList[#onList + 1] = k
	end
end
table.sort(onList)
local stList = {}
for k, v in pairs(statusTime) do
	stList[#stList + 1] = { k, v }
end
table.sort(stList, function(a, b)
	return a[2] > b[2]
end)
local okE, exe = pcall(function()
	return (identifyexecutor or getexecutorname)()
end)

local sum = {}
local function P(s)
	sum[#sum + 1] = s
end
P('Forge Tools fight report')
P(('build %s | place %s | executor %s | %d s recorded'):format(tostring(G.SB2ForgeToolsBuild), tostring(game.PlaceId), okE and tostring(exe) or '?', secs))
P(('ping ms: median %.0f, 90%% %.0f, max %.0f'):format(q(pings, 0.5), q(pings, 0.9), q(pings, 1)))
P(('press -> guard up: median %.2fs, 90%% %.2fs (%d samples)'):format(q(lats, 0.5), q(lats, 0.9), #lats))
P(('attacks seen %d | parried %d | blocked %d | presses %d | guards up %d'):format(S.shines, S.parry, S.blockHit, S.presses, S.ups))
P(('hits taken %d (%.0f dmg) | stuns %d | deaths %d'):format(S.hits, S.dmg, S.stuns, S.deaths))
P(('kills %d | damage dealt %.0f (%.0f per min)'):format(S.kills, S.dealt, S.dealt / math.max(secs, 1) * 60))
P('combat style: ' .. tostring(set.combatStyle) .. ' | auto block: ' .. tostring(set.autoBlock) .. ' | dodge: ' .. tostring(set.dodgeWhat))
P('toggles on: ' .. table.concat(onList, ', '))
P('time by status:')
for i = 1, math.min(10, #stList) do
	P(('  %5.0fs  %s'):format(stList[i][2], stList[i][1]))
end
local ps = G.FTParryStats or {}
local pb = {}
for k, v in pairs(ps) do
	if type(v) == 'number' then
		pb[#pb + 1] = k .. '=' .. (math.floor(v * 1000 + 0.5) / 1000)
	end
end
table.sort(pb)
P('parry internals: ' .. table.concat(pb, ' '))
local summary = table.concat(sum, '\n')

local full = summary .. '\n\nerrors / warnings:\n' .. (#errs > 0 and table.concat(errs, '\n') or '  none') .. '\n\ntimeline:\n' .. table.concat(log, '\n')
pcall(makefolder, 'PlayerTools')
local okW = pcall(writefile, OUT, full)
pcall(function()
	setclipboard(summary)
end)
G.FTDiagRunning = nil
notify(okW and ('Done. Report saved to workspace/' .. OUT .. ' (summary copied).') or 'Done, but the report could not be saved - summary copied.', 15)
print(summary)
