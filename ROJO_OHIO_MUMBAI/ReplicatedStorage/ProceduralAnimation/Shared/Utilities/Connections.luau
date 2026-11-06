-- ProceduralAnimation/Shared/Utilities/Connections
-- A tiny, allocation-free-by-default connection tracker.
--
-- Every module in this framework that connects to an engine signal has the same two problems:
--  1. it must be able to disconnect everything on teardown, and
--  2. it must not leak when the same lifecycle runs twice (Init called again, player rejoins,
--     character respawns).
--
-- Both are solved by keeping the RBXScriptConnections in a plain array and draining it in one
-- place. This is intentionally not a class: the tracker is an ordinary table the caller owns, and
-- the functions take it as their first argument.
--
-- Functional usage:
--
--   local Tracker = Connections.New()
--   Connections.Add(Tracker, Players.PlayerAdded:Connect(OnPlayerAdded))
--   ...
--   Connections.DisconnectAll(Tracker)   -- safe to call twice, safe to call when empty
--
-- The tracker is drained in reverse order, so teardown unwinds in the opposite order to setup.

local Connections = {}

-- Creates an empty tracker. Cheap: one table per owner, created once at Init.
function Connections.New(): { RBXScriptConnection }
    return {}
end

-- Records a connection. Returns the connection so it can be used inline:
--   Connections.Add(Tracker, Signal:Connect(Fn)):Disconnect()
function Connections.Add(Tracker: { RBXScriptConnection }, Connection: RBXScriptConnection): RBXScriptConnection
    if Connection then
        Tracker[#Tracker + 1] = Connection
    end
    return Connection
end

-- Disconnects everything and empties the tracker. Idempotent: a second call is a no-op, and a
-- tracker containing an already-disconnected connection is handled by pcall because
-- RBXScriptConnection:Disconnect does not raise in Studio but is not guaranteed repeatable here.
function Connections.DisconnectAll(Tracker: { RBXScriptConnection }): ()
    for Index = #Tracker, 1, -1 do
        local Connection = Tracker[Index]
        if Connection then
            local Success = pcall(function()
                Connection:Disconnect()
            end)
            if not Success then
                -- Nothing useful to do: a failed disconnect on a dead connection is harmless.
                -- Swallowing it keeps teardown from aborting halfway through.
            end
        end
        Tracker[Index] = nil
    end
    table.clear(Tracker)
end

-- Returns how many live connections a tracker holds. Used by the verification harness to assert
-- that teardown actually released everything.
function Connections.Count(Tracker: { RBXScriptConnection }): number
    return #Tracker
end

return Connections
