-- Vybe Loadstring API
-- Headless Luau runtime extracted from the supplied GUI scripts.
-- Use only with code and asset IDs you control or trust.

local API = {}

API.Name = "Vybe Loadstring API"
API.Version = "1.0.0"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local FIELD_LEN_FB = 360
local FIELD_WID_FB = 160
local DEFAULT_COLLISION_GROUP = "VybeNC"
local DEFAULT_JERSEY_PREFIX = "JERSEY_"

local state = {
	collisionGroup = DEFAULT_COLLISION_GROUP,
	groups = {},
	activeGroup = nil,
	charConns = {},
	watchConns = {},
	playerAddedConn = nil,
	cooldowns = {},
}

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
	return tostring(value or ""):lower()
end

local function ensureCollisionGroup(name)
	name = name or state.collisionGroup or DEFAULT_COLLISION_GROUP
	state.collisionGroup = name
	pcall(function()
		if PhysicsService.IsCollisionGroupRegistered and not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		else
			PhysicsService:CreateCollisionGroup(name)
		end
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(name, "Default", false)
	end)
	return name
end

local function setNonColliding(part)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	pcall(function()
		part.CollisionGroup = ensureCollisionGroup()
	end)
end

local function getParts(target)
	local parts = {}
	if typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			table.insert(parts, target)
		else
			for _, item in ipairs(target:GetDescendants()) do
				if item:IsA("BasePart") then
					table.insert(parts, item)
				end
			end
		end
	elseif type(target) == "table" then
		for _, item in ipairs(target) do
			if typeof(item) == "Instance" and item:IsA("BasePart") then
				table.insert(parts, item)
			end
		end
	end
	return parts
end

local function serializeCFrame(cf)
	local x, y, z, a, b, c, d, e, f, g, h, i = cf:GetComponents()
	return { Components = { x, y, z, a, b, c, d, e, f, g, h, i } }
end

local function deserializeCFrame(data)
	if data.Components then
		local c = data.Components
		return CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	end
	local p, r, u, l = data.Position, data.Right, data.Up, data.Look
	return CFrame.new(p[1], p[2], p[3], r[1], u[1], l[1], r[2], u[2], l[2], r[3], u[3], l[3])
end

local function boundsFromParts(parts)
	if #parts == 0 then
		return nil
	end
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(parts) do
		local pos, size = part.Position, part.Size
		min = Vector3.new(
			math.min(min.X, pos.X - size.X / 2),
			math.min(min.Y, pos.Y - size.Y / 2),
			math.min(min.Z, pos.Z - size.Z / 2)
		)
		max = Vector3.new(
			math.max(max.X, pos.X + size.X / 2),
			math.max(max.Y, pos.Y + size.Y / 2),
			math.max(max.Z, pos.Z + size.Z / 2)
		)
	end
	return {
		Min = min,
		Max = max,
		Size = max - min,
		Center = (min + max) / 2,
	}
end

local function findFieldPart(name)
	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == name then
			return item
		end
	end
	return nil
end

local function fieldGeometry(options)
	options = options or {}
	if options.length and options.width and options.center then
		return {
			length = options.length,
			width = options.width,
			center = options.center,
			direction = options.direction or Vector3.new(0, 0, 1),
			floorY = options.floorY or 0,
		}
	end

	local north, south = findFieldPart("NorthEndzone"), findFieldPart("SouthEndzone")
	if north and south then
		local nPos, sPos = north.Position, south.Position
		local dir = nPos - sPos
		return {
			length = dir.Magnitude,
			width = math.max(north.Size.X, north.Size.Z, south.Size.X, south.Size.Z),
			center = Vector3.new((nPos.X + sPos.X) / 2, 0, (nPos.Z + sPos.Z) / 2),
			direction = dir.Unit,
			floorY = (nPos.Y + sPos.Y) / 2,
		}
	end

	local field = workspace:FindFirstChild("Field")
	if not field then
		for _, item in ipairs(workspace:GetDescendants()) do
			if item.Name == "Field" and (item:IsA("Model") or item:IsA("BasePart")) then
				field = item
				break
			end
		end
	end

	if field then
		local parts = getParts(field)
		local b = boundsFromParts(parts)
		if b then
			local fLen, fWid, fDir
			if b.Size.Z >= b.Size.X then
				fLen, fWid, fDir = b.Size.Z, b.Size.X, Vector3.new(0, 0, 1)
			else
				fLen, fWid, fDir = b.Size.X, b.Size.Z, Vector3.new(1, 0, 0)
			end
			return {
				length = fLen,
				width = fWid,
				center = Vector3.new(b.Center.X, 0, b.Center.Z),
				direction = fDir,
				floorY = b.Min.Y,
			}
		end
	end

	local floorY = 0
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		floorY = baseplate.Position.Y + baseplate.Size.Y / 2
	end
	return {
		length = options.fallbackLength or FIELD_LEN_FB,
		width = options.fallbackWidth or FIELD_WID_FB,
		center = options.fallbackCenter or Vector3.new(0, 0, 0),
		direction = Vector3.new(0, 0, 1),
		floorY = floorY,
	}
end

local function groundY(geo, excludedFolder)
	local excluded = {}
	if excludedFolder then
		for _, item in ipairs(excludedFolder:GetDescendants()) do
			if item:IsA("BasePart") then
				table.insert(excluded, item)
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true

	local origin = Vector3.new(geo.center.X, 500, geo.center.Z)
	local direction = Vector3.new(0, -1000, 0)
	local current = origin

	for _ = 1, 50 do
		local result = workspace:Raycast(current, direction, params)
		if not result then
			break
		end
		local hit = result.Instance
		local name = lower(hit.Name)
		local helper = name:find("invisible") or name:find("collision") or name:find("hitbox") or name:find("barrier")
		local outsideImported = true
		if excludedFolder then
			local parent = hit
			while parent do
				if parent == excludedFolder then
					outsideImported = false
					break
				end
				parent = parent.Parent
			end
		end
		if hit.Transparency < 0.8 and outsideImported and not helper then
			return result.Position.Y
		end
		table.insert(excluded, hit)
		params.FilterDescendantsInstances = excluded
		current = result.Position + Vector3.new(0, -0.1, 0)
	end

	return geo.floorY
end

local function autoFitParts(parts, geo, folder)
	local b = boundsFromParts(parts)
	if not b then
		return false
	end

	local sizeX, sizeZ = b.Size.X, b.Size.Z
	local bestAngle, bestScore = 0, math.huge
	for _, angle in ipairs({ 0, math.pi / 2, math.pi, math.pi * 1.5 }) do
		local c, s = math.abs(math.cos(angle)), math.abs(math.sin(angle))
		local score = math.abs(sizeX * c + sizeZ * s - geo.length) + math.abs(sizeX * s + sizeZ * c - geo.width)
		if score < bestScore then
			bestScore = score
			bestAngle = angle
		end
	end

	local fieldAngle = math.atan2(geo.direction.X, geo.direction.Z)
	local finalAngle = fieldAngle + bestAngle
	local c, s = math.abs(math.cos(bestAngle)), math.abs(math.sin(bestAngle))
	local estimatedLength = sizeX * c + sizeZ * s
	local estimatedWidth = sizeX * s + sizeZ * c
	local scale = (geo.length * 3.20 / estimatedLength) * 0.65 + (geo.width * 3.00 / estimatedWidth) * 0.35
	local pivotX, pivotZ = b.Center.X, b.Center.Z
	local bottomY = b.Min.Y
	local rotation = CFrame.Angles(0, finalAngle, 0)
	local floor = groundY(geo, folder)

	local original = {}
	for _, part in ipairs(parts) do
		original[part] = { CFrame = part.CFrame, Size = part.Size }
	end

	local minVisible, minAny = math.huge, math.huge
	for _, part in ipairs(parts) do
		local old = original[part]
		local relY = (old.CFrame.Position.Y - bottomY) * scale
		local halfHeight = (old.Size.Y * scale) / 2
		local worldY = floor + relY
		minAny = math.min(minAny, worldY - halfHeight)
		local name = lower(part.Name)
		if part.Transparency < 0.8 and not (name:find("invisible") or name:find("collision") or name:find("hitbox")) then
			minVisible = math.min(minVisible, worldY - halfHeight)
		end
	end

	local effectiveMin = minVisible < math.huge and minVisible or minAny
	local yCorrection = floor - effectiveMin

	for index, part in ipairs(parts) do
		local old = original[part]
		local pos = old.CFrame.Position
		local relX = (pos.X - pivotX) * scale
		local relZ = (pos.Z - pivotZ) * scale
		local relY = (pos.Y - bottomY) * scale
		local rotatedOffset = rotation * Vector3.new(relX, 0, relZ)
		part.Size = old.Size * scale
		part.CFrame = CFrame.new(
			geo.center.X + rotatedOffset.X,
			floor + relY + yCorrection,
			geo.center.Z + rotatedOffset.Z
		) * (rotation * old.CFrame.Rotation)
		if index % 100 == 0 then
			task.wait()
		end
	end

	return true
end

local function setPrimaryPart(model)
	local best, bestVolume = nil, 0
	for _, part in ipairs(getParts(model)) do
		if part.Transparency < 0.5 then
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > bestVolume then
				best = part
				bestVolume = volume
			end
		end
	end
	if best then
		pcall(function()
			model.PrimaryPart = best
		end)
	end
	return best
end

local function normalizeTextureId(raw)
	if not raw or raw == "" then
		return nil
	end
	local text = trim(raw)
	if text:match("^rbxassetid://%d+$") then
		return text
	end
	local id = text:match("rbxassetid://(%d+)") or text:match("[?&]id=(%d+)") or text:match("^(%d+)$")
	return id and ("rbxassetid://" .. id) or nil
end

local function disconnectBucket(bucket)
	for _, conns in pairs(bucket) do
		for _, conn in ipairs(conns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
	end
end

local function cloneSwapHandle(accessory, mutator)
	local handle = accessory:FindFirstChild("Handle")
	if not handle then
		return false, "Accessory has no Handle"
	end

	local newHandle = handle:Clone()
	local ok, err = pcall(mutator, newHandle)
	if not ok then
		newHandle:Destroy()
		return false, err
	end

	local oldCFrame = handle.CFrame
	newHandle.Anchored = false
	handle:Destroy()
	newHandle.Parent = accessory
	newHandle.CFrame = oldCFrame

	local character = accessory.Parent
	if character then
		local firstAttachment = newHandle:FindFirstChildOfClass("Attachment")
		if firstAttachment then
			for _, item in ipairs(character:GetDescendants()) do
				if item:IsA("Attachment") and item.Name == firstAttachment.Name and item.Parent ~= newHandle then
					local bodyPart = item.Parent
					local insideAccessory = false
					pcall(function()
						insideAccessory = bodyPart.Parent:IsA("Accessory")
					end)
					if bodyPart and bodyPart:IsA("BasePart") and not insideAccessory then
						newHandle.CFrame = item.WorldCFrame * firstAttachment.CFrame:Inverse()
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = newHandle
						weld.Part1 = bodyPart
						weld.Parent = newHandle
						break
					end
				end
			end
		end
	end

	return true
end

local function applyTexture(accessory, textureId)
	local normalized = normalizeTextureId(textureId)
	if not normalized then
		return false, "Invalid texture ID"
	end
	pcall(function()
		ContentProvider:PreloadAsync({ normalized })
	end)
	return cloneSwapHandle(accessory, function(handle)
		if handle:IsA("MeshPart") then
			handle.TextureID = normalized
		else
			local mesh = handle:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh.TextureId = normalized
			end
		end
	end)
end

local function characterFrom(value)
	if typeof(value) ~= "Instance" then
		return nil
	end
	if value:IsA("Player") then
		return value.Character
	end
	if value:IsA("Model") then
		return value
	end
	return nil
end

local function playerByName(name)
	for _, player in ipairs(Players:GetPlayers()) do
		if lower(player.Name) == lower(name) then
			return player
		end
	end
	return nil
end

local function findGroup(groupOrName)
	if type(groupOrName) == "table" then
		return groupOrName
	end
	for _, group in ipairs(state.groups) do
		if lower(group.name) == lower(groupOrName) then
			return group
		end
	end
	return nil
end

local function pushPlayer(player, group, prefix)
	group = group or state.activeGroup
	prefix = prefix or DEFAULT_JERSEY_PREFIX
	if not player or not player.Character or not group then
		return 0
	end

	local applied = 0
	for _, child in ipairs(player.Character:GetChildren()) do
		if child:IsA("Accessory") and child.Name:sub(1, #prefix) == prefix then
			local textureId = group.slots[child.Name]
			if textureId then
				local key = tostring(player.UserId) .. child.Name
				if not state.cooldowns[key] then
					state.cooldowns[key] = true
					task.delay(0.5, function()
						state.cooldowns[key] = nil
					end)
					local ok = applyTexture(child, textureId)
					if ok then
						applied = applied + 1
					end
				end
			end
		end
	end
	return applied
end

local function watchAccessory(player, accessory, group, prefix)
	local key = tostring(player.UserId) .. ":" .. accessory.Name
	if state.watchConns[key] then
		return
	end

	local conns = {}
	local handle = accessory:FindFirstChild("Handle")
	if handle then
		local function recheck()
			local textureId = group.slots[accessory.Name]
			if textureId then
				task.defer(function()
					applyTexture(accessory, textureId)
				end)
			end
		end
		local ok1, conn1 = pcall(function()
			return handle:GetPropertyChangedSignal("TextureID"):Connect(recheck)
		end)
		if ok1 then
			table.insert(conns, conn1)
		end
		local mesh = handle:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			local ok2, conn2 = pcall(function()
				return mesh:GetPropertyChangedSignal("TextureId"):Connect(recheck)
			end)
			if ok2 then
				table.insert(conns, conn2)
			end
		end
	end

	state.watchConns[key] = conns
end

local function watchPlayer(player, group, prefix)
	prefix = prefix or DEFAULT_JERSEY_PREFIX
	if not state.charConns[player.UserId] then
		state.charConns[player.UserId] = {}
	end

	local function onCharacter(character)
		task.wait(0.18)
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Accessory") and child.Name:sub(1, #prefix) == prefix then
				watchAccessory(player, child, group, prefix)
			end
		end
		table.insert(state.charConns[player.UserId], character.ChildAdded:Connect(function(child)
			if child:IsA("Accessory") and child.Name:sub(1, #prefix) == prefix then
				task.wait(0.1)
				watchAccessory(player, child, group, prefix)
				pushPlayer(player, group, prefix)
			end
		end))
		pushPlayer(player, group, prefix)
	end

	if player.Character then
		onCharacter(player.Character)
	end
	table.insert(state.charConns[player.UserId], player.CharacterAdded:Connect(onCharacter))
end

local function serializePart(part, root)
	local data = {
		ClassName = part.ClassName,
		Name = part.Name,
		Size = { part.Size.X, part.Size.Y, part.Size.Z },
		CFrame = serializeCFrame(part.CFrame),
		Color = { part.Color.R, part.Color.G, part.Color.B },
		BrickColor = part.BrickColor.Name,
		Material = part.Material.Name,
		Transparency = part.Transparency,
		Reflectance = part.Reflectance,
		Anchored = part.Anchored,
		CanCollide = part.CanCollide,
		CanTouch = part.CanTouch,
		CanQuery = part.CanQuery,
		CastShadow = part.CastShadow,
		TopSurface = part.TopSurface.Name,
		BottomSurface = part.BottomSurface.Name,
		Parent = part.Parent and part.Parent.Name or "Parts",
	}

	if root and part:IsDescendantOf(root) then
		local pieces = {}
		local current = part
		while current and current ~= root do
			table.insert(pieces, 1, current.Name)
			current = current.Parent
		end
		data.FullPath = table.concat(pieces, "/")
	end

	if part:IsA("Part") then
		data.Shape = part.Shape.Name
	elseif part:IsA("MeshPart") then
		data.MeshId = part.MeshId
		data.TextureID = part.TextureID
	end

	local meshes = {}
	local decals = {}
	local appearances = {}
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SpecialMesh") then
			table.insert(meshes, {
				ClassName = child.ClassName,
				Name = child.Name,
				MeshType = child.MeshType.Name,
				MeshId = child.MeshId,
				TextureId = child.TextureId,
				Scale = { child.Scale.X, child.Scale.Y, child.Scale.Z },
			})
		elseif child:IsA("Decal") or child:IsA("Texture") then
			table.insert(decals, {
				ClassName = child.ClassName,
				Name = child.Name,
				Texture = child.Texture,
				Face = child.Face.Name,
				Transparency = child.Transparency,
			})
		elseif child:IsA("SurfaceAppearance") then
			table.insert(appearances, {
				Name = child.Name,
				AlphaMode = child.AlphaMode.Name,
				ColorMap = child.ColorMap,
				MetalnessMap = child.MetalnessMap,
				NormalMap = child.NormalMap,
				RoughnessMap = child.RoughnessMap,
			})
		end
	end

	if #meshes > 0 then
		data.Meshes = meshes
	end
	if #decals > 0 then
		data.Decals = decals
	end
	if #appearances > 0 then
		data.SurfaceAppearances = appearances
	end

	return data
end

local function buildPartFromData(data)
	local part
	local className = data.ClassName
	if className == "Part" then
		part = Instance.new("Part")
		if data.Shape then
			pcall(function()
				part.Shape = Enum.PartType[data.Shape]
			end)
		end
	elseif className == "WedgePart" then
		part = Instance.new("WedgePart")
	elseif className == "CornerWedgePart" then
		part = Instance.new("CornerWedgePart")
	elseif className == "MeshPart" then
		part = Instance.new("MeshPart")
	elseif className == "TrussPart" then
		part = Instance.new("TrussPart")
	else
		part = Instance.new("Part")
	end

	part.Name = data.Name or className or "Part"
	part.Size = Vector3.new(data.Size[1], data.Size[2], data.Size[3])
	part.CFrame = deserializeCFrame(data.CFrame)
	part.Color = Color3.new(data.Color[1], data.Color[2], data.Color[3])
	if data.BrickColor then
		pcall(function()
			part.BrickColor = BrickColor.new(data.BrickColor)
		end)
	end
	pcall(function()
		part.Material = Enum.Material[data.Material]
	end)
	part.Transparency = data.Transparency or 0
	part.Reflectance = data.Reflectance or 0
	part.Anchored = data.Anchored ~= nil and data.Anchored or true
	part.CanCollide = data.CanCollide ~= nil and data.CanCollide or true
	if data.CanTouch ~= nil then
		part.CanTouch = data.CanTouch
	end
	if data.CanQuery ~= nil then
		part.CanQuery = data.CanQuery
	end
	if data.CastShadow ~= nil then
		part.CastShadow = data.CastShadow
	end
	pcall(function()
		part.TopSurface = Enum.SurfaceType[data.TopSurface]
	end)
	pcall(function()
		part.BottomSurface = Enum.SurfaceType[data.BottomSurface]
	end)

	if part:IsA("MeshPart") and data.MeshId then
		part.MeshId = data.MeshId
		part.TextureID = data.TextureID or ""
	end

	if data.Meshes then
		for _, meshData in ipairs(data.Meshes) do
			pcall(function()
				local mesh = Instance.new("SpecialMesh")
				mesh.Name = meshData.Name or "Mesh"
				mesh.MeshType = Enum.MeshType[meshData.MeshType]
				mesh.MeshId = meshData.MeshId or ""
				mesh.TextureId = meshData.TextureId or ""
				mesh.Scale = Vector3.new(meshData.Scale[1], meshData.Scale[2], meshData.Scale[3])
				mesh.Parent = part
			end)
		end
	end

	if data.Decals then
		for _, decalData in ipairs(data.Decals) do
			pcall(function()
				local decal = Instance.new(decalData.ClassName == "Texture" and "Texture" or "Decal")
				decal.Name = decalData.Name or decal.ClassName
				decal.Texture = decalData.Texture or ""
				decal.Face = Enum.NormalId[decalData.Face]
				decal.Transparency = decalData.Transparency or 0
				decal.Parent = part
			end)
		end
	end

	if data.SurfaceAppearances then
		for _, appearanceData in ipairs(data.SurfaceAppearances) do
			pcall(function()
				local appearance = Instance.new("SurfaceAppearance")
				appearance.Name = appearanceData.Name or "SurfaceAppearance"
				pcall(function()
					appearance.AlphaMode = Enum.AlphaMode[appearanceData.AlphaMode]
				end)
				appearance.ColorMap = appearanceData.ColorMap or ""
				appearance.MetalnessMap = appearanceData.MetalnessMap or ""
				appearance.NormalMap = appearanceData.NormalMap or ""
				appearance.RoughnessMap = appearanceData.RoughnessMap or ""
				appearance.Parent = part
			end)
		end
	end

	if (data.Transparency or 0) >= 0.95 or data.CanCollide == false then
		setNonColliding(part)
	end

	return part, data.Parent or "Parts", data.FullPath or ""
end

API.Loadstrings = {}

function API.Loadstrings.compile(source, env)
	if type(source) ~= "string" then
		return nil, "source must be a string"
	end
	local loader = type(loadstring) == "function" and loadstring or load
	if type(loader) ~= "function" then
		return nil, "loadstring is not available in this environment"
	end
	local chunk, err = loader(source)
	if not chunk then
		return nil, err
	end
	if env and type(setfenv) == "function" then
		pcall(function()
			setfenv(chunk, env)
		end)
	end
	return chunk
end

function API.Loadstrings.run(source, env, ...)
	local chunk, err = API.Loadstrings.compile(source, env)
	if not chunk then
		return false, err
	end
	return pcall(chunk, ...)
end

function API.Loadstrings.fetch(url, options)
	options = options or {}
	if type(options.fetcher) == "function" then
		return options.fetcher(url, options)
	end
	local ok, result = pcall(function()
		if type(game.HttpGet) == "function" then
			return game:HttpGet(url)
		end
		if RunService:IsServer() then
			return HttpService:GetAsync(url)
		end
		error("No fetcher available; pass options.fetcher")
	end)
	if not ok then
		return nil, result
	end
	return result
end

function API.Loadstrings.fromUrl(url, options, ...)
	local source, fetchErr = API.Loadstrings.fetch(url, options)
	if not source then
		return false, fetchErr
	end
	local env = options and options.env or nil
	return API.Loadstrings.run(source, env, ...)
end

API.Stadium = {}

function API.Stadium.getParts(target)
	return getParts(target)
end

function API.Stadium.bounds(target)
	return boundsFromParts(getParts(target))
end

function API.Stadium.fieldGeometry(options)
	return fieldGeometry(options)
end

function API.Stadium.autoFit(target, options)
	options = options or {}
	local parts = getParts(target)
	local geo = options.geometry or fieldGeometry(options)
	return autoFitParts(parts, geo, typeof(target) == "Instance" and target or options.folder)
end

function API.Stadium.translate(target, offset)
	for _, part in ipairs(getParts(target)) do
		part.CFrame = part.CFrame + offset
	end
	return target
end

function API.Stadium.rotate(target, degrees, pivot)
	local parts = getParts(target)
	local b = boundsFromParts(parts)
	if not b then
		return target
	end
	pivot = pivot or b.Center
	local rotation = CFrame.Angles(0, math.rad(degrees or 0), 0)
	local original = {}
	for _, part in ipairs(parts) do
		original[part] = part.CFrame
	end
	for _, part in ipairs(parts) do
		local old = original[part]
		local rel = old.Position - pivot
		part.CFrame = CFrame.new(pivot + rotation * rel) * (rotation * old.Rotation)
	end
	return target
end

function API.Stadium.scale(target, factor, pivot)
	local parts = getParts(target)
	local b = boundsFromParts(parts)
	if not b then
		return target
	end
	pivot = pivot or b.Center
	local original = {}
	for _, part in ipairs(parts) do
		original[part] = { CFrame = part.CFrame, Size = part.Size }
	end
	for _, part in ipairs(parts) do
		local old = original[part]
		part.Size = old.Size * factor
		part.CFrame = CFrame.new(pivot + (old.CFrame.Position - pivot) * factor) * old.CFrame.Rotation
	end
	return target
end

function API.Stadium.serializeModel(model, options)
	options = options or {}
	local data = {}
	for _, part in ipairs(getParts(model)) do
		table.insert(data, serializePart(part, model))
	end
	if options.asJson then
		return HttpService:JSONEncode(data)
	end
	return data
end

function API.Stadium.toJson(model)
	return API.Stadium.serializeModel(model, { asJson = true })
end

function API.Stadium.fromData(data, options)
	options = options or {}
	if data.parts then
		data = data.parts
	end

	local model = Instance.new("Model")
	model.Name = options.name or "VybeStadium"
	local folders = {}
	local parts = {}

	for index, partData in ipairs(data) do
		local ok, part, parentName = pcall(function()
			local builtPart, groupName = buildPartFromData(partData)
			return builtPart, groupName
		end)
		if ok and part then
			local parent = model
			if options.groupByParent ~= false then
				parentName = parentName or "Parts"
				if not folders[parentName] then
					local folder = Instance.new("Model")
					folder.Name = parentName
					folder.Parent = model
					folders[parentName] = folder
				end
				parent = folders[parentName]
			end
			part.Parent = parent
			table.insert(parts, part)
		end
		if index % 50 == 0 then
			task.wait()
		end
	end

	model.Parent = options.parent or workspace
	if options.autoFit ~= false and #parts > 0 then
		API.Stadium.autoFit(parts, { geometry = options.geometry, folder = model })
	end
	setPrimaryPart(model)
	return {
		model = model,
		parts = parts,
		count = #parts,
	}
end

function API.Stadium.fromJson(json, options)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok then
		return nil, data
	end
	return API.Stadium.fromData(data, options)
end

function API.Stadium.importAsset(assetId, options)
	options = options or {}
	local id = tostring(assetId):match("(%d+)")
	if not id then
		return nil, "Invalid asset ID"
	end

	local ok, objects = pcall(function()
		return game:GetObjects("rbxassetid://" .. id)
	end)
	if not ok or not objects or #objects == 0 then
		return nil, "Asset load failed"
	end

	local model = Instance.new("Model")
	model.Name = options.name or ("VybeAsset_" .. id)
	for _, object in ipairs(objects) do
		object.Parent = model
	end

	local parts = getParts(model)
	for _, part in ipairs(parts) do
		if part.Transparency >= 0.8 then
			setNonColliding(part)
		end
	end

	if #parts == 0 then
		model:Destroy()
		return nil, "Asset has no BaseParts"
	end

	model.Parent = options.parent or workspace
	local resized = false
	if options.autoFit ~= false then
		resized = API.Stadium.autoFit(parts, { geometry = options.geometry, folder = model })
	end
	setPrimaryPart(model)

	return {
		model = model,
		parts = parts,
		count = #parts,
		resized = resized,
		id = tonumber(id),
	}
end

API.Jerseys = {}

function API.Jerseys.normalizeId(raw)
	return normalizeTextureId(raw)
end

function API.Jerseys.scan(playerOrCharacter, prefix)
	prefix = prefix or DEFAULT_JERSEY_PREFIX
	local character = characterFrom(playerOrCharacter) or (Players.LocalPlayer and Players.LocalPlayer.Character)
	local jerseys = {}
	if not character then
		return jerseys
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and child.Name:sub(1, #prefix) == prefix then
			table.insert(jerseys, child.Name)
		end
	end
	table.sort(jerseys)
	return jerseys
end

function API.Jerseys.apply(accessory, textureId)
	return applyTexture(accessory, textureId)
end

function API.Jerseys.applyToCharacter(playerOrCharacter, slots, options)
	options = options or {}
	local character = characterFrom(playerOrCharacter)
	local prefix = options.prefix or DEFAULT_JERSEY_PREFIX
	if not character then
		return 0
	end

	local applied = 0
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and child.Name:sub(1, #prefix) == prefix then
			local textureId = slots[child.Name]
			if textureId then
				local ok = applyTexture(child, textureId)
				if ok then
					applied = applied + 1
				end
			end
		end
	end
	return applied
end

function API.Jerseys.createGroup(name, slots, players)
	local group = {
		name = trim(name),
		slots = {},
		players = {},
	}
	for accessoryName, textureId in pairs(slots or {}) do
		local normalized = normalizeTextureId(textureId)
		if normalized then
			group.slots[accessoryName] = normalized
		end
	end
	for _, username in ipairs(players or {}) do
		table.insert(group.players, tostring(username))
	end
	table.insert(state.groups, group)
	return group
end

function API.Jerseys.groups()
	return state.groups
end

function API.Jerseys.activeGroup()
	return state.activeGroup
end

function API.Jerseys.setTexture(groupOrName, accessoryName, textureId)
	local group = findGroup(groupOrName)
	local normalized = normalizeTextureId(textureId)
	if not group then
		return false, "Group not found"
	end
	if not normalized then
		return false, "Invalid texture ID"
	end
	group.slots[accessoryName] = normalized
	return true
end

function API.Jerseys.addPlayer(groupOrName, username)
	local group = findGroup(groupOrName)
	if not group then
		return false, "Group not found"
	end
	username = trim(username)
	for _, existing in ipairs(group.players) do
		if lower(existing) == lower(username) then
			return true
		end
	end
	table.insert(group.players, username)
	local player = playerByName(username)
	if player and state.activeGroup == group then
		watchPlayer(player, group, DEFAULT_JERSEY_PREFIX)
		pushPlayer(player, group, DEFAULT_JERSEY_PREFIX)
	end
	return true
end

function API.Jerseys.removePlayer(groupOrName, username)
	local group = findGroup(groupOrName)
	if not group then
		return false, "Group not found"
	end
	for index, existing in ipairs(group.players) do
		if lower(existing) == lower(username) then
			table.remove(group.players, index)
			return true
		end
	end
	return false, "Player not in group"
end

function API.Jerseys.activateGroup(groupOrName, options)
	options = options or {}
	local group = findGroup(groupOrName)
	if not group then
		return false, "Group not found"
	end

	disconnectBucket(state.charConns)
	disconnectBucket(state.watchConns)
	state.charConns = {}
	state.watchConns = {}
	if state.playerAddedConn then
		pcall(function()
			state.playerAddedConn:Disconnect()
		end)
		state.playerAddedConn = nil
	end

	state.activeGroup = group
	local prefix = options.prefix or DEFAULT_JERSEY_PREFIX
	if options.watch ~= false then
		for _, username in ipairs(group.players) do
			local player = playerByName(username)
			if player then
				watchPlayer(player, group, prefix)
			end
		end
		state.playerAddedConn = Players.PlayerAdded:Connect(function(player)
			if state.activeGroup ~= group then
				return
			end
			for _, username in ipairs(group.players) do
				if lower(username) == lower(player.Name) then
					watchPlayer(player, group, prefix)
					break
				end
			end
		end)
	end

	API.Jerseys.pushAll(group, { prefix = prefix })
	return true
end

function API.Jerseys.pushPlayer(playerOrUsername, groupOrName, options)
	options = options or {}
	local player = typeof(playerOrUsername) == "Instance" and playerOrUsername or playerByName(playerOrUsername)
	local group = findGroup(groupOrName) or state.activeGroup
	return pushPlayer(player, group, options.prefix or DEFAULT_JERSEY_PREFIX)
end

function API.Jerseys.pushAll(groupOrName, options)
	options = options or {}
	local group = findGroup(groupOrName) or state.activeGroup
	if not group then
		return 0
	end
	local pushed = 0
	for _, username in ipairs(group.players) do
		local player = playerByName(username)
		if player then
			pushed = pushed + pushPlayer(player, group, options.prefix or DEFAULT_JERSEY_PREFIX)
		end
	end
	return pushed
end

function API.Jerseys.stop()
	disconnectBucket(state.charConns)
	disconnectBucket(state.watchConns)
	state.charConns = {}
	state.watchConns = {}
	if state.playerAddedConn then
		pcall(function()
			state.playerAddedConn:Disconnect()
		end)
		state.playerAddedConn = nil
	end
	state.activeGroup = nil
end

API.Props = {}

function API.Props.create(shape, options)
	options = options or {}
	shape = tostring(shape or "Block")
	local part
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	elseif shape == "Truss" then
		part = Instance.new("TrussPart")
	else
		part = Instance.new("Part")
		if shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif shape == "Sphere" or shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		end
	end

	part.Name = options.name or ("VybeProp_" .. shape)
	part.Size = options.size or Vector3.new(4, 4, 4)
	part.Anchored = options.anchored ~= false
	part.CanCollide = options.canCollide ~= false
	part.Color = options.color or Color3.fromRGB(180, 180, 180)
	part.Material = options.material or Enum.Material.SmoothPlastic
	part.Transparency = options.transparency or 0
	part.Reflectance = options.reflectance or 0
	if options.cframe then
		part.CFrame = options.cframe
	elseif options.position then
		part.Position = options.position
	else
		local localPlayer = Players.LocalPlayer
		local character = localPlayer and localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			part.CFrame = root.CFrame * CFrame.new(0, 4, -8)
		else
			part.Position = Vector3.new(0, 5, 0)
		end
	end
	part.Parent = options.parent or workspace
	return part
end

function API.Props.paint(part, options)
	options = options or {}
	if options.color then
		part.Color = options.color
	end
	if options.material then
		part.Material = options.material
	end
	if options.transparency ~= nil then
		part.Transparency = math.clamp(options.transparency, 0, 1)
	end
	if options.reflectance ~= nil then
		part.Reflectance = math.clamp(options.reflectance, 0, 1)
	end
	return part
end

function API.Props.duplicate(part, options)
	options = options or {}
	local clone = part:Clone()
	clone.CFrame = part.CFrame + (options.offset or Vector3.new(4, 0, 0))
	clone.Parent = options.parent or part.Parent or workspace
	return clone
end

function API.Props.toModel(parts, name, parent, cloneParts)
	local model = Instance.new("Model")
	model.Name = name or "VybePropDesign"
	for _, part in ipairs(parts) do
		if part and part.Parent then
			local outputPart = cloneParts and part:Clone() or part
			outputPart.Parent = model
		end
	end
	model.Parent = parent or workspace
	setPrimaryPart(model)
	return model
end

API.Remotes = {}

function API.Remotes.find()
	return {
		export = ReplicatedStorage:FindFirstChild("ExportPartsRemote"),
		upload = ReplicatedStorage:FindFirstChild("UploadPartsRemote"),
		download = ReplicatedStorage:FindFirstChild("DownloadPartsRemote"),
	}
end

function API.Remotes.exportModel(modelName)
	local remotes = API.Remotes.find()
	if not remotes.export then
		return nil, "ExportPartsRemote not found"
	end
	local ok, result = pcall(function()
		return remotes.export:InvokeServer(modelName)
	end)
	if not ok then
		return nil, result
	end
	return result
end

function API.Remotes.upload(saveId, json, meta)
	local remotes = API.Remotes.find()
	if not remotes.upload then
		return nil, "UploadPartsRemote not found"
	end
	local ok, result = pcall(function()
		return remotes.upload:InvokeServer(json, saveId, meta or {})
	end)
	if not ok then
		return nil, result
	end
	return result
end

function API.Remotes.download(saveId)
	local remotes = API.Remotes.find()
	if not remotes.download then
		return nil, "DownloadPartsRemote not found"
	end
	local ok, result = pcall(function()
		return remotes.download:InvokeServer(saveId)
	end)
	if not ok then
		return nil, result
	end
	return result
end

function API.configure(options)
	options = options or {}
	if options.collisionGroup then
		ensureCollisionGroup(options.collisionGroup)
	else
		ensureCollisionGroup(state.collisionGroup)
	end
	return API
end

function API.destroy()
	API.Jerseys.stop()
end

ensureCollisionGroup(DEFAULT_COLLISION_GROUP)

return API
