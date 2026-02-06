--[[
  SYSTEM: CachyOS Advanced Mounting Logic
  MODULE: mount.lua
  PURPOSE: Partition mounting with UUID validation.
--]]

local libJson = require("dkjson")

---------------------------------------------------------
-- 1. UTILITIES (The Engine Room)
---------------------------------------------------------

-- State-safe table replication
local function deep_copy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do res[deep_copy(k)] = deep_copy(v) end
    return res
end

-- Structural state comparison
local function deep_compare(t1, t2)
    if type(t1) ~= type(t2) then return false end
    if type(t1) ~= "table" then return t1 == t2 end
    for k, v in pairs(t1) do
        if not deep_compare(v, t2[k]) then return false end
    end
    for k in pairs(t2) do
        if t1[k] == nil then return false end
    end
    return true
end

-- Merges defaults with partition-specific overrides
local function deep_merge(base, overlay)
    if not overlay then return deep_copy(base) end
    local res = deep_copy(base)
    for k, v in pairs(overlay) do
        if type(v) == "table" and type(res[k]) == "table" then
            res[k] = deep_merge(res[k], v)
        else
            if res[k] ~= nil then
                print(string.format("[AUDIT]: Key '%s' override: %s -> %s", k, tostring(res[k]), tostring(v)))
            end
            res[k] = deep_copy(v)
        end
    end
    return res
end

-- Recursive visualization for data auditing
local function walkJson(data, f, depth)
    depth = depth or 0
    local isArray = next(data) == 1
    for k, v in (isArray and ipairs or pairs)(data) do
        if type(v) == "table" then
            f(k, nil, depth, true, isArray)
            walkJson(v, f, depth + 1)
        else f(k, v, depth, false, isArray) end
    end
end

-- Extract parent block device string
local function get_block_device(dev)
    return dev:gsub("p?%d+$", "")
end

---------------------------------------------------------
-- 2. LOGIC (Validation & Friction Tracing)
---------------------------------------------------------

-- Verify hardware identity via blkid
local function verify_uuid(dev, expected_uuid)
    local handle = io.popen(string.format("blkid -s UUID -o value %q", dev))
    local actual_uuid = handle:read("*a"):gsub("%s+", "")
    handle:close()

    if actual_uuid ~= expected_uuid then
        print(string.format("[WARNING]: UUID Mismatch! Dev: %s | Expected: %s | Actual: %s", dev, expected_uuid, actual_uuid))
        return false
    end
    print("  |- Identity: UUID verified.")
    return true
end

-- Legacy trace function (retained for reference)
local function old_preflight_check(p)
    local block = get_block_device(p.device)
    print(string.format("\n[LOG]: Examining %s", p.mountPoint or "Unknown"))
    print(string.format("  |- Physical Device: %s -> Parent: %s", p.device, block))
    
    if p.device:find("mapper") then
        print("  |- Security: LUKS active. Trusting mapper node.")
    end
    
    if p.subvolume then
        print(string.format("  |- Btrfs Logic: Targeted Subvolume: %s", p.subvolume))
    end
end

-- Core validation before execution
local function preflight_check(p)
    local block = get_block_device(p.device)
    print(string.format("\n[LOG]: Examining %s", p.mountPoint or "Unknown"))
    
    if p.uuid then
        verify_uuid(p.device, p.uuid)
    end

    if p.device:find("mapper") then
        print("  |- Security: LUKS active. Trusting mapper node.")
    end
end

-- Create target directory paths
local function prepare_target(dest)
    os.execute("mkdir -p " .. dest)
end

-- Final mount execution with symlink protection
local function safe_mount(sub, opt, dev, dest)
    if os.execute("test -L " .. dest) == 0 then
        print("SECURITY ALERT: " .. dest .. " is a symlink!")
        return false
    end
    local cmd = string.format("mount -o subvol=%q,%s %q %q", sub, opt, dev, dest)
    print("[PLAN]: " .. cmd)
    --prepare_target(dest) --comment out until we have the directories figured out
    -- os.execute(cmd) 
end

---------------------------------------------------------
-- 3. WORKFLOW (Execution Bridge)
---------------------------------------------------------

local f = io.open(arg[1], "r")
if not f then os.exit(1) end
local content = f:read("*all")
f:close()

local json, _, err = libJson.decode(content)
if err then 
    print("[FATAL]: JSON error: " .. err)
    os.exit(1) 
end

-- Hierarchy sort: parents before children
table.sort(json, function(a, b)
    local _, d1 = (a.mountPoint or ""):gsub("/", "")
    local _, d2 = (b.mountPoint or ""):gsub("/", "")
    return d1 < d2
end)

local sys_defaults = { flags = "defaults,noatime" }

-- Process partition queue
for _, p in ipairs(json) do
    local success, err = pcall(function()
        if p.device and p.mountPoint then
            preflight_check(p)
            local target = "/tmp/root" .. p.mountPoint
            local opts = deep_merge(sys_defaults, { flags = p.options })
            safe_mount(p.subvolume or "@", opts.flags, p.device, target)
        end
    end)
    if not success then print("[CRITICAL ERROR]: " .. tostring(err)) end
end

-- Structural Audit for terminal review
print("\n--- POST-EXECUTION STRUCTURE AUDIT ---")
local test_data = {}
--for i=1, math.min(3, #json) do test_data[i] = json[i] end
for i=1, #json do test_data[i] = json[i] end
walkJson(test_data, function(k, v, depth, isTable, isArrayElem)
    local indent = string.rep("  ", depth)
    local keyStr = isArrayElem and ("[" .. k .. "]:") or (k .. ":")
    if isTable then print(indent .. keyStr)
    else print(indent .. keyStr .. " " .. tostring(v)) end
end)
