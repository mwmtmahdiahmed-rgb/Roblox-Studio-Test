-- ProceduralAnimation/Client/StatePool
-- The registry of live character animation states: the map used for lookups by model, plus the
-- dense array the heartbeat iterates. Keeping them together here is what lets the heartbeat and
-- the character lifecycle live in different modules without either owning the other's data.
--
-- The active array is compacted with swap-removal, so iteration order is not stable across
-- removals. Nothing depends on order.

local StatePool = {}

StatePool.States = {}
StatePool.Active = {}
StatePool.Count = 0

-- Registers a freshly created state. Called once per character setup.
function StatePool.Add(Character, State)
    StatePool.States[Character] = State
    local Count = StatePool.Count + 1
    StatePool.Count = Count
    StatePool.Active[Count] = State
end

function StatePool.Get(Character)
    return StatePool.States[Character]
end

-- Marks a state invalid and drops it from the lookup map. The heartbeat calls Compact() once per
-- frame; removal is deferred so a teardown during iteration can never disturb the loop.
function StatePool.Remove(Character)
    local State = StatePool.States[Character]
    if not State then
        return nil
    end
    State.Valid = false
    StatePool.States[Character] = nil
    return State
end

-- Drops every invalid entry from the active array with swap-removal, preserving density.
function StatePool.Compact()
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
end

-- Used by teardown paths that clear everything (player removal, module re-init).
function StatePool.Clear()
    StatePool.States = {}
    StatePool.Active = {}
    StatePool.Count = 0
end

return StatePool
