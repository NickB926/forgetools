--[[
	Forge Tools loader — one line to install, and it updates itself every time it runs.

	  loadstring(game:HttpGet("https://raw.githubusercontent.com/NickB926/forgetools/main/loader.lua"))()

	What it does: asks GitHub for version.json; if that version is not the one saved on this
	machine (or a file is missing) it downloads the files into the PlayerTools folder, then runs
	Forge Tools from there. If GitHub cannot be reached it runs the copy already on disk.
]]

local G = getgenv()
local BASE = (type(G.ForgeToolsUpdateBase) == 'string' and G.ForgeToolsUpdateBase ~= '' and G.ForgeToolsUpdateBase:gsub('/+$', ''))
	or 'https://raw.githubusercontent.com/NickB926/forgetools/main'
local DIR = 'PlayerTools'
local FILES = { 'ForgeTools.lua', 'AtaraxiaLibrary.lua' }
local VERSION_FILE = DIR .. '/forgetools_version.txt'

local function notify(text, dur)
	pcall(function()
		game:GetService('StarterGui'):SetCore('SendNotification', { Title = 'Forge Tools', Text = text, Duration = dur or 6 })
	end)
	warn('[ForgeTools loader] ' .. tostring(text))
end

if type(G.ForgeToolsLoaderBusy) == 'number' and os.clock() - G.ForgeToolsLoaderBusy < 60 then
	notify('Already loading — wait a few seconds.')
	return
end
G.ForgeToolsLoaderBusy = os.clock()

local function httpGet(url)
	-- (the ?t= part stops GitHub / the executor handing back an old cached copy)
	url = url .. (url:find('?', 1, true) and '&' or '?') .. 't=' .. tostring(os.time())
	local req = (syn and syn.request) or http_request or (http and http.request) or request
	if type(req) == 'function' then
		local ok, res = pcall(req, { Url = url, Method = 'GET' })
		if ok and type(res) == 'table' then
			local body = res.Body or res.body
			local code = tonumber(res.StatusCode or res.Status or res.statusCode) or 0
			if code >= 200 and code < 300 and type(body) == 'string' and body ~= '' then
				return body
			end
		end
	end
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == 'string' and body ~= '' and not body:match('^%s*404: Not Found') then
		return body
	end
	return nil
end

local function has(path)
	local ok, yes = pcall(isfile, path)
	return ok and yes == true
end

local ok, err = pcall(function()
	pcall(makefolder, DIR)
	local HttpService = game:GetService('HttpService')
	local remote
	local raw = httpGet(BASE .. '/version.json')
	if raw then
		pcall(function()
			remote = HttpService:JSONDecode(raw)
		end)
	end
	local want = remote and tostring(remote.build or remote.version or '') or ''
	local have = has(VERSION_FILE) and readfile(VERSION_FILE) or ''
	local missing = false
	for _, name in ipairs(FILES) do
		if not has(DIR .. '/' .. name) then
			missing = true
		end
	end

	if want ~= '' and (want ~= have or missing) then
		-- Download everything first and only then write, so a half-finished update never
		-- replaces a working copy.
		local got = {}
		for _, name in ipairs(FILES) do
			local body = httpGet(BASE .. '/' .. name)
			if not body or not (loadstring or load)(body) then
				got = nil
				break
			end
			got[name] = body
		end
		if got then
			for name, body in pairs(got) do
				writefile(DIR .. '/' .. name, body)
			end
			writefile(VERSION_FILE, want)
			notify((have == '' and 'Installed ' or 'Updated to ') .. want)
		elseif missing then
			error('could not download the files from GitHub')
		else
			notify('Update to ' .. want .. ' failed to download — running the copy you already have.')
		end
	elseif want == '' and missing then
		error('GitHub could not be reached and Forge Tools is not installed yet')
	end

	local src = readfile(DIR .. '/ForgeTools.lua')
	local fn, cerr = (loadstring or load)(src, 'ForgeTools.lua')
	if not fn then
		error('ForgeTools.lua did not compile: ' .. tostring(cerr))
	end
	G.ForgeToolsLoaderBusy = nil
	fn()
end)
G.ForgeToolsLoaderBusy = nil
if not ok then
	notify('Could not start: ' .. tostring(err), 12)
end
