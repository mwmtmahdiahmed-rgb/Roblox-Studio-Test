--!strict
--[[
    Tools/verify/src/04-testkit.luau

    Small assertion kit shared by the Lua test suites. A case is recorded as PASS, FAIL or
    BLOCKED; a FAIL carries the exact expectation and the observed value so the report is
    evidence, not a claim.
]]

return function(Env)
local Kit = {}

local CurrentCases = nil
local CurrentPrefix = ""

function Kit.Begin(Cases, Prefix)
    CurrentCases = Cases
    CurrentPrefix = Prefix or ""
end

local function Add(Name, Status, Detail)
    if not CurrentCases then
        error("TestKit used outside a suite", 2)
    end
    CurrentCases[#CurrentCases + 1] = {
        Name = CurrentPrefix .. Name,
        Status = Status,
        Detail = Detail,
    }
    return Status
end

function Kit.Pass(Name, Detail)
    return Add(Name, "PASS", Detail or "")
end

function Kit.Fail(Name, Detail)
    return Add(Name, "FAIL", Detail or "")
end

function Kit.Blocked(Name, Detail)
    return Add(Name, "BLOCKED", Detail or "")
end

function Kit.Check(Name, Condition, Detail)
    if Condition then
        return Kit.Pass(Name, Detail)
    end
    return Kit.Fail(Name, Detail)
end

local function Show(Value)
    local ValueType = type(Value)
    if ValueType == "number" then
        return string.format("%.10g", Value)
    elseif ValueType == "string" then
        return string.format("%q", Value)
    elseif ValueType == "table" then
        return "<table>"
    end
    return tostring(Value)
end

function Kit.Near(Name, Actual, Expected, Tolerance, Detail)
    local Target = Tolerance or 1e-6
    local Ok = type(Actual) == "number" and math.abs(Actual - Expected) <= Target
    if Ok then
        return Kit.Pass(Name, Detail)
    end
    return Kit.Fail(Name, string.format("expected %s (+/- %s), got %s%s",
        Show(Expected), Show(Target), Show(Actual), Detail and (" [" .. Detail .. "]") or ""))
end

function Kit.Equal(Name, Actual, Expected, Detail)
    if Actual == Expected then
        return Kit.Pass(Name, Detail)
    end
    return Kit.Fail(Name, string.format("expected %s, got %s%s",
        Show(Expected), Show(Actual), Detail and (" [" .. Detail .. "]") or ""))
end

function Kit.True(Name, Value, Detail)
    return Kit.Equal(Name, Value, true, Detail)
end

function Kit.False(Name, Value, Detail)
    return Kit.Equal(Name, Value, false, Detail)
end

function Kit.NotNil(Name, Value, Detail)
    if Value ~= nil then
        return Kit.Pass(Name, Detail)
    end
    return Kit.Fail(Name, "expected a value, got nil" .. (Detail and (" [" .. Detail .. "]") or ""))
end

function Kit.Nil(Name, Value, Detail)
    if Value == nil then
        return Kit.Pass(Name, Detail)
    end
    return Kit.Fail(Name, "expected nil, got " .. Show(Value) .. (Detail and (" [" .. Detail .. "]") or ""))
end

function Kit.Greater(Name, Actual, Bound, Detail)
    if type(Actual) == "number" and Actual > Bound then
        return Kit.Pass(Name, Detail)
    end
    return Kit.Fail(Name, string.format("expected > %s, got %s", Show(Bound), Show(Actual)))
end

function Kit.Less(Name, Actual, Bound, Detail)
    if type(Actual) == "number" and Actual < Bound then
        return Kit.Pass(Name, Detail)
    end
    return Kit.Fail(Name, string.format("expected < %s, got %s", Show(Bound), Show(Actual)))
end

-- Calls Callback through pcall and records the failure text, so a thrown error in one case
-- does not abort the whole suite.
function Kit.Guard(Name, Callback)
    local Results = table.pack(pcall(Callback))
    if Results[1] then
        return Results[2]
    end
    Kit.Fail(Name, "threw: " .. tostring(Results[2]))
    return nil
end

-- Deep structural comparison used by the public API diff.
function Kit.Describe(Value, Depth, Seen)
    Depth = Depth or 0
    Seen = Seen or {}
    local ValueType = type(Value)
    if ValueType ~= "table" then
        if ValueType == "function" then
            return "function"
        elseif ValueType == "number" then
            return "number"
        elseif ValueType == "string" then
            return "string"
        elseif ValueType == "boolean" then
            return "boolean"
        elseif ValueType == "buffer" then
            return "buffer:" .. tostring(buffer.len(Value))
        end
        return ValueType
    end
    if Seen[Value] then
        return "<cycle>"
    end
    if Depth > 6 then
        return "<deep>"
    end
    Seen[Value] = true
    local Keys = {}
    for Key in pairs(Value) do
        Keys[#Keys + 1] = Key
    end
    table.sort(Keys, function(A, B)
        return tostring(A) < tostring(B)
    end)
    local Parts = {}
    for Index = 1, #Keys do
        local Key = Keys[Index]
        Parts[Index] = tostring(Key) .. ":" .. Kit.Describe(Value[Key], Depth + 1, Seen)
    end
    Seen[Value] = nil
    return "{" .. table.concat(Parts, ",") .. "}"
end

return Kit
end
