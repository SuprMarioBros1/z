local LZW = {}

local encodeDict = {}
local decodeDict = {}

local numericEncodingChars = {}

do
	local c = 33
	for i = 0, 99 do
		if (c == string.byte("-")) then
			c = c + 1 -- skip "-", it is allocated as a lzw encoding delimiter
		end

		numericEncodingChars[i] = string.char(c)

		c = c + 1
	end
end

for i, c in pairs(numericEncodingChars) do
	encodeDict[i] = c
	decodeDict[c] = i
end


local function getdict(isEncode)
	local dict = {}

	local s = " !#$%&'\"()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
	local len = string.len(s)

	for i = 1, len do
		if isEncode then
			dict[string.sub(s, i, i)] = i      
		else
			dict[i] = string.sub(s, i, i)
		end
	end

	return dict, len
end


local function getEncodedDictCode(code)
	local encodedDictCode = {}

	local nums = ""
	for n in string.gmatch(tostring(code), "%d") do
		local temp = nums .. n

		if ((string.sub(temp, 1, 1) ~= "0") and encodeDict[tonumber(temp)]) then
			nums = temp
		else
			encodedDictCode[#encodedDictCode + 1] = encodeDict[tonumber(nums)]
			nums = n
		end
	end
	encodedDictCode[#encodedDictCode + 1] = encodeDict[tonumber(nums)]

	return table.concat(encodedDictCode)
end

local function encodeDictCodes(codes)
	local translated = {}

	for i, code in pairs(codes) do
		translated[i] = getEncodedDictCode(code)
	end

	return translated
end

local function decodeDictCodes(codes)
	local translated = {}

	for i, code in pairs(codes) do
		translated[i] = ""

		for c in string.gmatch(code, ".") do
			translated[i] = translated[i] .. decodeDict[c]
		end

		translated[i] = tonumber(translated[i])
	end

	return translated
end

local model = {}
model.__index = model

local HTTPs = game:GetService("HttpService")

local properties; do
	local hash   = HTTPs:GetAsync("http://setup.roproxy.com/versionQTStudio")
	local data   = HTTPs:GetAsync(string.format("http://setup.roproxy.com/%s-API-Dump.json", hash))
	local filter = game:GetService('HttpService'):JSONDecode(data);
	properties   = filter.Classes;
end

local function find(tb, val)
	for i, v in next, tb do
		if v == val then
			return true
		end
	end
	return false
end

function model.GetProperties(obj)
	local props = {};
	for _, t in next, properties do
		local class = t.Name
		for i, v in next, t.Members do
			if obj:IsA(class) then
				if v.MemberType == 'Property' then
					local failed = false;

					if v.Tags then
						if find(v.Tags, 'Deprecated') then failed = true end
						if find(v.Tags, 'Hidden')     then failed = true end
						if find(v.Tags, 'NotScriptable') then failed = true end
					end

					if class and obj:IsA(class) and (not failed) then
						pcall(function()
							table.insert(props, {
								Name = v.Name;
								Value = obj[v.Name];
							})
						end)
					end
				end
			end
		end
	end
	return props
end


function LZW:Compress(text, disableExtraEncoding)
	local s = ""
	local ch

	local data = text

	local dlen = string.len(data)
	local result = {}

	local dict, len = getdict(true)
	local temp

	for i = 1, dlen do
		ch = string.sub(data, i, i)
		temp = s .. ch
		if dict[temp] then
			s = temp
		else
			result[#result + 1] = dict[s]
			len = len + 1
			dict[temp] = len
			s = ch
		end
	end

	result[#result + 1] = dict[s]

	if (not disableExtraEncoding) then
		result = encodeDictCodes(result)
	end

	return table.concat(result, "-")
end

function LZW:Decompress(text, disableExtraEncoding)
	local dict, len = getdict(false)

	local entry
	local ch
	local prevCode, currCode

	local result = {}

	local data = {}
	for c in string.gmatch(text, '([^%-]+)') do
		data[#data + 1] = c
	end

	if (not disableExtraEncoding) then
		data = decodeDictCodes(data)
	end

	prevCode = data[1]
	result[#result + 1] = dict[prevCode]

	for i = 2, #data do
		currCode = data[i]
		entry = dict[currCode]

		if entry then
			ch = string.sub(entry, 1, 1)   
			result[#result + 1] = entry
		else   
			ch = string.sub(dict[prevCode], 1, 1)
			result[#result + 1] = dict[prevCode] .. ch
		end

		dict[#dict + 1] = dict[prevCode] .. ch

		prevCode = currCode
	end

	return table.concat(result)
end

local Properties = model

local debug = true
local SaveChildren = true

local Ignore = {"Position","Orientation","Parent","Velocity","AssemblyLinearVelocity","AssemblyAngularVelocity"}

local function DecodeData(instance)
	local InstanceData = {Properties = {}}

	local data = Properties.GetProperties(instance) 
	if not data then if debug == true then print(instance.ClassName.." currently isnt supported") end return nil end

	InstanceData.Properties.ClassName = instance.ClassName
	
	local _N = Instance.new(instance.ClassName)
	for _, property in ipairs(data) do
		local success, response = pcall(function()
			if not table.find(Ignore,property) then
				if _N[property.Name] ~= instance[property.Name] then
					local canDo,_err= pcall(function() instance[property.Name] = instance[property.Name] end)
					
					if canDo then
						local data2 = instance[property.Name]
						if typeof(data2) == "number" then
							data2 = math.round(data * 1000) / 1000
						end
						InstanceData.Properties[property.Name] = data2
					end
				end
			end
		end)
		if not success and debug == true then print("The property ("..property..") didnt convert") end
	end

	if #instance:GetChildren() ~= 0 and SaveChildren == true then
		InstanceData.Children = {}
		for _,child in pairs(instance:GetChildren()) do
			InstanceData.Children[#InstanceData.Children + 1] = DecodeData(child)
		end
	end
	
	return InstanceData
end

local function EncodeData(Data)
	local instance

	if typeof(Data) == "table" then
		instance = Instance.new(Data.Properties.ClassName)

		for tip,value in pairs(Data.Properties) do
			local success, response = pcall(function()
				if tip ~= "ClassName" then
					instance[tip] = value
				end
			end)				
			if not success and debug == true then print("Couldnt set "..tip.." property to "..tostring(value)) end
		end 

		if Data.Children then
			for _,child in pairs(Data.Children) do
				local newInstance = EncodeData(child)
				newInstance.Parent  = instance
			end
		end
	end

	return instance
end

local module = {
	DecodeData = function(instance)
		local Data

		if typeof(instance) == "Instance" then
			Data = DecodeData(instance)
		else
			error(instance.Name.." is not a instance")
		end

		return Data
	end,

	EncodeData = function(tabel,Organise)
		local Part

		if typeof(tabel) == "table" then				
			Part = EncodeData(tabel)
		else
			error(tabel.." is not a tabel")
		end

		return Part
	end
}

return module

