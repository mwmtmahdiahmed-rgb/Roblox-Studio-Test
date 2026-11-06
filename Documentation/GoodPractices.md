# Good Practices — Procedural Animation Framework

Patterns that are **actually used and verified** in this codebase. Every example here is drawn
from real source in this repository, not invented for the document.

If you are adding code, follow these. If you are reviewing code, cite the relevant section.

---

## 1. Functional, data-oriented architecture

No OOP. No classes. No metatables. No inheritance. No `self`.

State lives in **plain tables** that are passed explicitly. Behaviour lives in **free
functions** that take that state as their first argument.

```lua
-- GOOD: state is a plain table, behaviour is a free function
local function UpdateJump(State, DeltaTime)
    if State.JumpState == JumpStateGrounded then
        return
    end
    State.JumpTime += DeltaTime
end
```

Why: a plain table is trivially inspectable, serialisable, pooled and copied. Methods that
close over `self` hide their data flow, and metatable lookups on a per-frame path cost more
than a direct field read.

### Dependency injection instead of back-references

Extracted modules receive their collaborators through a constructor table, so nothing
requires its parent back and the require graph stays acyclic.

```lua
-- GOOD: explicit dependencies, no cycle
local CharacterJoints = require(script.Parent.CharacterJoints)({
    Config = Config,
    Changelog = Changelog,
})
```

This is what made the 1407 → 448 line split of `ProceduralAnimator` possible without touching
its public API.

---

## 2. The leaf module, to break an apparent cycle

When two modules genuinely need the same primitive, extract the primitive into a module that
depends on nothing. `PoseBuffer` exists for exactly this reason: both `ClientPosePipeline` and
`ClientRigKinematics` write the pose buffer. Without the leaf they would require each other.

```lua
-- ProceduralAnimation/Client/PoseBuffer  (a leaf: depends only on AnimationConfig)
local Config = require(script.Parent.Parent.Shared.AnimationConfig)
local MaxJoints = Config.MaxJoints
local PoseBytesPerJoint = 12
local PoseBufferLength = MaxJoints * PoseBytesPerJoint
local BufferReadF32 = buffer.readf32
local BufferWriteF32 = buffer.writef32

local function WritePoseAdd(PoseBuffer, Joint, X, Y, Z)
    local Offset = (Joint - 1) * PoseBytesPerJoint
    BufferWriteF32(PoseBuffer, Offset, BufferReadF32(PoseBuffer, Offset) + X)
end

return { PoseBytesPerJoint = PoseBytesPerJoint, WritePoseAdd = WritePoseAdd }
```

Rule of thumb: **if you need a `if Injected then` guard to break a cycle, you need a leaf
module instead.**

---

## 3. Dependency injection — but inject *getters* for live state

A subtle and expensive bug class. If a flag is passed **by value** into a constructor, the
module captures a snapshot and never sees later updates.

```lua
-- BAD: the value is copied at construction time
local Pipeline = ClientPosePipeline({
    PreviewMode = PreviewMode,   -- a boolean, frozen forever
})

-- GOOD: pass a getter, so the module always reads the current value
local Pipeline = ClientPosePipeline({
    IsPreviewMode = function()
        return PreviewMode
    end,
})
```

This exact bug silently broke `SetPreviewMode` during the Phase 3 split. The integration suite
caught it; casual inspection did not.

The same rule applies to counters. **Never capture a mutable counter at load time:**

```lua
-- BAD: frozen at 0 if no characters exist yet
local ActiveStateCount = StatePool.Count

-- GOOD: read through the pool on every access
local function GetActiveCount()
    return StatePool.Count
end
```

---

## 4. Preallocated buffers for per-frame data

Allocate once per character. Never allocate inside the frame loop.

```lua
-- Once, in CreateState:
State.Pose = buffer.create(PoseBufferLength)
State.Overlay = buffer.create(PoseBufferLength)
State.Smooth = buffer.create(PoseBufferLength)

-- Every frame: zero allocation
BufferFill(State.Pose, 0, PoseBufferLength, 0)
```

`buffer` is a flat block of bytes: no per-element table overhead, no GC pressure, and
`buffer.readf32` / `buffer.writef32` are cheap.

### Localise buffer functions on the hot path

```lua
local BufferReadF32 = buffer.readf32
local BufferWriteF32 = buffer.writef32
local CFrameAngles = CFrame.fromEulerAnglesXYZ
local Sqrt = math.sqrt
```

Each `math.sqrt` you write is two table lookups (`math`, then `sqrt`). Localising at module
scope turns it into one upvalue read. This is a real, measurable win in a loop that runs
per-joint per-frame.

### Offsets from an integer index, not string keys

```lua
local Offset = (Joint - 1) * PoseBytesPerJoint
```

Joints are integers `1..MaxJoints`. Never key a hot-path table by joint name.

---

## 5. Object pooling and reusable state

The `StatePool` pattern: a **dense array** for iteration plus a **map** for lookup. Iteration
never touches the map, so it is a straight `1..Count` loop with no `pairs`.

```lua
local StatePool = {}
StatePool.States = {}   -- model -> state   (lookup)
StatePool.Active = {}   -- [1..Count]       (iteration)
StatePool.Count = 0

function StatePool.Add(Character, State)
    StatePool.States[Character] = State
    local Count = StatePool.Count + 1
    StatePool.Count = Count
    StatePool.Active[Count] = State
end
```

### Swap-removal, not `table.remove`

`table.remove` shifts every later element — O(n) per removal, and it invalidates indices
mid-iteration. Swap-removal is O(1):

```lua
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
```

Trade-off, accepted and documented in the module: **iteration order is not stable** across
removals. Nothing in this framework depends on order.

### Preallocate fixed-size sub-tables up front

```lua
-- In CreateState, not in the frame loop:
for Slot = 1, MaxGestures do
    State.Gestures[Slot] = { Active = false, Clip = nil, Time = 0.0, Weight = 0.0 }
end
for Joint = 1, MaxJoints do
    State.EasingOverride[Joint] = 0
end
```

---

## 6. Skinning the hot path

Order work so that free rejections happen first. `SampleClip` and `ApplyPose` both do this:

```lua
-- Skip zero-weight work before touching the buffer at all
if Weight <= 0.0001 then
    return
end

-- Skip joints that contribute nothing
if Abs(X) + Abs(Y) + Abs(Z) > 0.00001 then
    WritePoseAdd(PoseBuffer, Joint, X, Y, Z)
end
```

A comparison costs a fraction of a `buffer.writef32`. Reject early.

### Distance-based LOD

Remote characters outside `Config.LodDistance` keep their last pose and are not recomputed.
IK is dropped at `Config.LodIkDistance`. Both thresholds are in `AnimationConfig`, not hardcoded.

---

## 7. Centralised configuration

**Every** tunable lives in `AnimationConfig`. A number in the runtime is a bug.

Good, because it can be tuned per character, per joint or per preset without touching logic:

```lua
local LocomotionIdleMax = Config.Locomotion.IdleMax
local LocomotionWalkMax = Config.Locomotion.WalkMax
local LocomotionRunMax = Config.Locomotion.RunMax
local LocomotionBlendRate = Config.Locomotion.BlendRate
```

Covered by config today: animation speeds and weights, joint offsets and amplitudes, damping,
interpolation and easing, IK parameters and angle limits, ground alignment, locomotion and
stride, secondary motion, wave and curve parameters, packet constants.

---

## 8. Frame-rate independent smoothing

Never blend by a raw constant per frame — that makes behaviour depend on frame rate.

```lua
-- GOOD: exponential smoothing, frame-rate independent
local Factor = MathLib.SmoothFactor(State.SmoothRate, DeltaTime)
State.Value += (Target - State.Value) * Factor
```

`SmoothFactor` computes `1 - exp(-Rate * DeltaTime)`. At 30 fps and 144 fps the same value
converges in the same wall-clock time.

---

## 9. Rotation-only Transform, and how to read a pose

`Motor6D.Transform` carries **rotation only**. Translation stays in the joint's `C0`.

```lua
-- Writing: euler angles, no position
Motor.Transform = CFrameAngles(X, Y, Z)

-- Reading a pose back (in a test or debug view):
local X, Y, Z = Motor.Transform:ToEulerAnglesXYZ()
```

`Transform.Position` will always be `(0,0,0)`. That is correct, not a bug. **Never** conclude
"the animation is broken" from a zero position.

---

## 10. Connection ownership and teardown

Every connection created for a character is stored **on that character's state** and
disconnected in teardown. Nothing is stored in a module-level list that can leak.

```lua
State.StateChangedConnection = Humanoid.StateChanged:Connect(function(OldState, NewState)
    OnHumanoidStateChanged(State, OldState, NewState)
end)
```

```lua
-- Teardown:
if State.StateChangedConnection then
    State.StateChangedConnection:Disconnect()
    State.StateChangedConnection = nil
end
```

Always `Disconnect()` **and** nil the field, so a second teardown is a no-op and the callback
closure becomes collectable.

---

## 11. Fail fast on an invalid rig

`SetupCharacter` returns `false` immediately rather than half-initialising:

```lua
local Success, MissingName = CacheJoints(State, Character)
if not Success then
    Changelog.Log("Setup aborted: missing R15 joint " .. tostring(MissingName))
    return false
end
```

A partially-built state is far worse than no state: it produces zeros, NaNs or silent
no-ops that look like animation bugs.

---

## 12. Append-only changelog

`Changelog.Entries` is append-only. History is never rewritten or renumbered. It is a Luau
module so it ships with the code and is readable at runtime, and it is mirrored into
`Documentation/Changelog.md` for humans.

---

## 13. Verify, don't assume

Every claim of "works" must be backed by one of: a passing harness suite, a byte-level packet
comparison, a line-count check, an export enumeration, or a source quotation.

The harness compares the exported API surface against `baseline/api.json`. If you remove or
rename an export, the `api` suite fails. That is the point of it — it caught the false
"API unchanged" assumption during the split.

Verification language is explicit and honest:

- **PASS** — verified, with evidence.
- **PARTIAL** — some aspects verified.
- **FAIL** — verified failure.
- **NOT TESTED** — no evidence either way.
- **BLOCKED** — cannot proceed in this environment.

---

## 14. Keep modules small and single-purpose

Hard limit: **500 lines per script**. Prefer ~200–400.

The limit is not bureaucracy. `ProceduralAnimator` grew to 1407 lines and became
un-reviewable, un-testable and impossible to reason about. It was split into eight cohesive
modules with no behaviour change. Every split target was chosen by asking *"what does this
own?"* — not by cutting at line 500.

When a module approaches the limit, extract **a cohesive concern**, never an arbitrary slice.
