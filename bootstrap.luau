local API_URL = "https://raw.githubusercontent.com/Kyattou/UF-API/refs/heads/main/Main-API.luau"

local function fetch(url)
	if type(game.HttpGet) == "function" then
		return game:HttpGet(url)
	end
	local HttpService = game:GetService("HttpService")
	return HttpService:GetAsync(url)
end

local source = assert(fetch(API_URL), "Failed to fetch UFBarstool API")
local chunk = assert(loadstring(source), "Failed to compile UFBarstool API")
local Vybe = chunk()

return Vybe
