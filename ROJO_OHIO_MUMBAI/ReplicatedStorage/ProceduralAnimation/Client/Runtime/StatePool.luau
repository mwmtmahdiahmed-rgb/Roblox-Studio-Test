--!strict
-- ProceduralAnimation/Client/StatePool
-- The registry of live character animation states: the map used for lookups by model, plus the
-- dense array the heartbeat iterates. Keeping them together here is what lets the heartbeat and
-- the character lifecycle live in different modules without either owning the other's data.
--
-- The active array is compacted with swap-removal, so iteration order is not stable across
-- removals. Nothing depends on order.

local StatePool = {}

StatePool.States = {} :: { [any]: any }
StatePool.Active = {} :: { [number]: any }
StatePool.Count = 0
-- Number of states awaiting compaction. Compact() runs every frame; without a dirty flag it
-- paid a full pass over the active list on frames where nothing was removed. Only Remove()
-- invalidates entries, so a zero counter means the scan would change nothing.
StatePool.PendingRemovals = 0

-- Registers a freshly created state. Called once per character setup.
function StatePool.Add(Character: any, State: any): ()
    StatePool.States[Character] = State
    local Count = StatePool.Count + 1
    StatePool.Count = Count
    StatePool.Active[Count] = State
end

function StatePool.Get(Character: any): any
    return StatePool.States[Character]
end

-- Marks a state invalid and drops it from the lookup map. The heartbeat calls Compact() once per
-- frame; removal is deferred so a teardown during iteration can never disturb the loop.
function StatePool.Remove(Character: any): any
    local State = StatePool.States[Character]
    if not State then
        return nil
    end
    State.Valid = false
    StatePool.States[Character] = nil
    StatePool.PendingRemovals += 1
    return State
end

-- Drops every invalid entry from the active array with swap-removal, preserving density.
function StatePool.Compact(): ()
    if StatePool.PendingRemovals == 0 then
        return
    end
    local Active = StatePool.Active
    local Index = 1
    local Count = StatePool.Count
    while Index <= Count do
        if Active[Index].Valid then
            Index += 1
        else
            Active[Index] = Active[Count]
            Active[Count] = nil
            Count -= 1
        end
    end
    StatePool.Count = Count
    StatePool.PendingRemovals = 0
end

-- Used by teardown paths that clear everything (player removal, module re-init).
function StatePool.Clear(): ()
    StatePool.States = {} :: { [any]: any }
    StatePool.Active = {} :: { [number]: any }
    StatePool.Count = 0
    StatePool.PendingRemovals = 0
end

return StatePool
