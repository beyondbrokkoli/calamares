
local printJsonObject -- Forward declaration

local function printJsonArray(j, depth)
    depth = depth or 0
    for i, v in ipairs(j) do
        io.write(string.rep("  ", depth))
        if type(v) == "table" then
            print("[" .. i .. "]:")
            if next(v) == 1 then printJsonArray(v, depth + 1)
            else printJsonObject(v, depth + 1) end
        else print("[" .. i .. "]: " .. tostring(v)) end
    end
end

function printJsonObject(j, depth)
    depth = depth or 0
    for k, v in pairs(j) do
        io.write(string.rep("  ", depth))
        if type(v) == "table" then
            print(k .. ":")
            if next(v) == 1 then printJsonArray(v, depth + 1)
            else printJsonObject(v, depth + 1) end
        else print(k .. ": " .. tostring(v)) end
    end
end

if next(json) == 1 then printJsonArray(json)
else printJsonObject(json) end
