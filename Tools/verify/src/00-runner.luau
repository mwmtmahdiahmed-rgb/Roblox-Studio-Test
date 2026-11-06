--[[
    Tools/verify/src/00-runner.luau

    Entry point of the offline verification sandbox. Tools/verify/verify.mjs compiles this
    bundle, runs it once to receive a handle table, and then calls into the handle for every
    test suite.

    The seam is deliberately small:
        Handle.Echo(Text)             -> string   (round-trip smoke test)
        Handle.LoadProject(Root, Map)            (Map: Rojo relative path -> source)
        Handle.RunSuite(Name)         -> string   (JSON results for one suite)
        Handle.ListSuites()           -> string   (JSON array of suite names)

    Everything a suite needs is reachable through Env, which owns module loading, the simulated
    services and the frame pump.
]]

return function(Env)

local Handle = {}

Handle.Env = Env

local Suites = {}
local SuiteOrder = {}

-- The test kit is a factory over Env; suites are factories over (Env, Kit).
local TestKit = nil

-- Suites are plain functions stored on this table by the test files, which are required
-- below. Each returns a table shaped { Name = string, Cases = { { Name, Status, Detail } } }.

function Handle.InitSuites(Kit, SuiteFactories)
    TestKit = Kit
    for Index = 1, #SuiteFactories do
        local Suite = SuiteFactories[Index](Env, Kit)
        SuiteOrder[#SuiteOrder + 1] = Suite
        Suites[Suite.Name] = Suite
    end
    return #SuiteOrder
end

function Handle.RegisterSuite(Suite)
    SuiteOrder[#SuiteOrder + 1] = Suite
    Suites[Suite.Name] = Suite
end

function Handle.Echo(Text)
    return "echo:" .. tostring(Text)
end

function Handle.LoadProject(ProjectFiles)
    Env.LoadProject(ProjectFiles)
    return true
end

function Handle.ListSuites()
    local Names = {}
    for Index = 1, #SuiteOrder do
        Names[Index] = SuiteOrder[Index].Name
    end
    return table.concat(Names, ",")
end

local function JsonEscape(Text)
    Text = tostring(Text)
    Text = string.gsub(Text, "\\", "\\\\")
    Text = string.gsub(Text, '"', '\\"')
    Text = string.gsub(Text, "\n", "\\n")
    Text = string.gsub(Text, "\r", "\\r")
    Text = string.gsub(Text, "\t", "\\t")
    return Text
end

local function ToJson(Value)
    local ValueType = type(Value)
    if ValueType == "nil" then
        return "null"
    elseif ValueType == "boolean" then
        return Value and "true" or "false"
    elseif ValueType == "number" then
        if Value ~= Value or Value == math.huge or Value == -math.huge then
            return "null"
        end
        return string.format("%.17g", Value)
    elseif ValueType == "string" then
        return '"' .. JsonEscape(Value) .. '"'
    elseif ValueType == "table" then
        local IsArray = true
        local Count = 0
        for Key in pairs(Value) do
            Count += 1
            if type(Key) ~= "number" then
                IsArray = false
                break
            end
        end
        if IsArray and Count == #Value then
            local Parts = {}
            for Index = 1, #Value do
                Parts[Index] = ToJson(Value[Index])
            end
            return "[" .. table.concat(Parts, ",") .. "]"
        end
        local Parts = {}
        for Key, Entry in pairs(Value) do
            Parts[#Parts + 1] = '"' .. JsonEscape(tostring(Key)) .. '":' .. ToJson(Entry)
        end
        return "{" .. table.concat(Parts, ",") .. "}"
    end
    return '"<unsupported:' .. ValueType .. '>"' 
end

Handle.ToJson = ToJson

local function RunSuiteByName(Name)
    local Suite = Suites[Name]
    if not Suite then
        return ToJson({ Name = Name, Cases = { { Name = "suite lookup", Status = "BLOCKED", Detail = "unknown suite" } } })
    end
    local Results = { Name = Name, Cases = {} }
    if Suite.Reset then
        local Ok, Err = pcall(Suite.Reset)
        if not Ok then
            Results.Cases[1] = { Name = "reset", Status = "FAIL", Detail = tostring(Err) }
            return ToJson(Results)
        end
    end
    local Ok, Err = pcall(Suite.Body, Results.Cases)
    if not Ok then
        Results.Cases[#Results.Cases + 1] = { Name = "suite body", Status = "FAIL", Detail = tostring(Err) }
    end
    return ToJson(Results)
end

function Handle.RunSuite(Name)
    local Ok, Result = pcall(RunSuiteByName, Name)
    if not Ok then
        return ToJson({ Name = Name, Cases = { { Name = "harness", Status = "FAIL", Detail = tostring(Result) } } })
    end
    return Result
end

return Handle
end
