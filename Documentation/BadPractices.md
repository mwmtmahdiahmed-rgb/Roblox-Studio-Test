# Bad Practices — Procedural Animation Framework

Real problems, each tied to a **defect that actually occurred in this project** or to a
pattern that is structurally dangerous here. Every entry states the consequence and the
preferred alternative.

Read this before reviewing or writing code. Most of these are cheap to avoid and expensive
to diagnose.

---

## 1. Capturing mutable state by value

**Occurred:** Phase 3 split. `SetPreviewMode` and `SetLocomotionWeight` silently stopped
working; both were caught only by the integration suite.

```lua
-- BAD: frozen at 0 at load time, because no characters exist yet
local ActiveStateCount = StatePool.Count
for Index = 1, ActiveStateCount do   -- never runs
    ...
end

-- BAD: the boolean is copied into the constructor and never updated
Pipeline = ClientPosePipeline({ PreviewMode = PreviewMode })
Animator.SetPreviewMode(true)        -- mutates the animator's local, pipeline never sees it
```

**Why it is dangerous:** it fails *silently*. No error, no warning — the loop simply does
zero iterations and the feature appears implemented.

**Instead:** read live, or inject a getter.

```lua
local function GetActiveCount()
    return StatePool.Count
end

Pipeline = ClientPosePipeline({
    IsPreviewMode = function()
        return PreviewMode
    end,
})
```

---

## 2. Forward references that resolve to globals

**Occurred twice.** `ApplyWorldDirection` was called from the FABRIK section before its
`local` declaration, so the call site compiled to a **global** lookup and resolved to `nil`
at runtime.

```lua
-- BAD: UpdateFabrikChain closes over a global named ApplyWorldDirection
local function UpdateFabrikChain(...)
    ApplyWorldDirection(State, ...)   -- nil at runtime
end

function ApplyWorldDirection(...)     -- creates a GLOBAL, not the local
end
```

**Why it is dangerous:** Luau does not error at compile time. You get
`attempt to call a nil value` at run time, possibly only on one code path.

**Instead:** declare the local before any closure that uses it, then assign.

```lua
local ApplyWorldDirection        -- forward declaration

local function UpdateFabrikChain(...)
    ApplyWorldDirection(State, ...)
end

function ApplyWorldDirection(...)  -- assigns the local declared above
end
```

Or, if the function is defined later in a different module, inject it — which is what the
Phase 3 split does.

**Related:** extracting a function into another module turns every one of its former upvalues
into a free identifier that resolves to a global. When you split a module, **re-check every
free identifier in the moved body.** This caused the majority of the errors during the split.

---

## 3. OOP, classes, metatables, inheritance, `self`

**Prohibited by project rules**, and technically a poor fit here anyway.

```lua
-- BAD
local Character = {}
Character.__index = Character

function Character.new(model)
    local self = setmetatable({}, Character)
    self.Model = model
    return self
end

function Character:Update(dt)
    self.Energy -= dt       -- hidden data flow, metatable lookup per call
end
```

**Consequences:** `__index` adds a metatable lookup to every field access — and this framework
touches joint state hundreds of times per frame. Hidden state makes the data un-inspectable,
un-serialisable and hard to pool. Inheritance hierarchies in Luau become deep `__index` chains
that are painful to debug.

**Instead:** plain tables passed explicitly, free functions.

```lua
local function UpdateCharacter(State, DeltaTime)
    State.Energy -= DeltaTime
end
```

---

## 4. Unbounded per-frame allocation

**The cardinal sin in this codebase.** Anything that allocates inside the frame loop creates
GC pressure, which produces frame spikes that are extremely hard to attribute.

```lua
-- BAD: a new table every frame, per character
local function UpdatePose(State)
    local Offsets = {}                                  -- allocation
    for Joint = 1, MaxJoints do
        Offsets[Joint] = ComputeOffset(Joint)           -- more allocation
    end
    return Vector3.new(0, 0, 0)                         -- allocation
end
```

```lua
-- GOOD: preallocated, reused, no allocation
local function UpdatePose(State)
    BufferFill(State.Pose, 0, PoseBufferLength, 0)
    for Joint = 1, MaxJoints do
        WritePoseAdd(State.Pose, Joint, X, Y, Z)        -- writes into an existing buffer
    end
end
```

Also watch for: string concatenation in a loop, `table.create` inside a frame, closures
created per frame, `{...}` varargs tables, and `:GetChildren()` in a hot path.

---

## 5. Repeated lookups instead of caching

```lua
-- BAD: two lookups per call, per joint, per frame
local Speed = math.sqrt(X)
local Angle = math.acos(Y)

-- BAD: FindFirstChild walks the instance tree every frame
local Joint = Character:FindFirstChild("Waist", true)
```

**Instead:** localise library functions at module scope, and resolve `Motor6D` references
**once** during setup, storing them in `State.Joints`.

```lua
local Sqrt = math.sqrt
local Acos = math.acos

-- Once, in setup:
State.Joints[JointIndex] = Motor   -- cached; never re-searched
```

Cached today: services, `Motor6D` references, rest `C0`/`C1` derived lengths, joint indices.

---

## 6. String keys in hot paths

```lua
-- BAD: hashing a string on every joint, every frame
Motor.Transform = CFrameAngles(Pose["Waist"].X, Pose["Waist"].Y, Pose["Waist"].Z)
```

**Instead:** integer joint indices from `Config.JointIndex`, and an integer offset into a
flat buffer.

```lua
local Offset = (JointIndex.Waist - 1) * PoseBytesPerJoint
BufferWriteF32(Pose, Offset, X)
```

---

## 7. Magic numbers scattered through the runtime

```lua
-- BAD: what is 14.0? Why 0.05?
local Blend = 1.0 - math.exp(-14.0 * DeltaTime)
if Speed < 0.05 then
    ...
end
```

**Consequences:** untunable without editing logic, different modules drift to different
values, and per-character presets become impossible.

**Instead:** centralise in `AnimationConfig` and read it once at module scope.

```lua
local JumpBlendRate = Config.Jump.BlendRate
local SpeedEpsilon = Config.Locomotion.SpeedEpsilon
```

---

## 8. Frame-rate dependent smoothing

```lua
-- BAD: converges twice as fast at 120 fps as at 60 fps
State.Value += (Target - State.Value) * 0.1
```

**Instead:**

```lua
local Factor = MathLib.SmoothFactor(Rate, DeltaTime)   -- 1 - exp(-Rate * DeltaTime)
State.Value += (Target - State.Value) * Factor
```

---

## 9. Unmanaged connections

```lua
-- BAD: disconnected nowhere; captures State and Character forever
Humanoid.StateChanged:Connect(function(Old, New)
    OnHumanoidStateChanged(State, Old, New)
end)
```

**Consequences:** leaks on respawn, the callback fires against a destroyed character, and
memory grows every respawn cycle. The `Animator.Stop` connection leak was a real defect of
exactly this shape.

**Instead:** store on the state, disconnect **and** nil in teardown.

```lua
State.StateChangedConnection = Humanoid.StateChanged:Connect(...)

-- teardown:
State.StateChangedConnection:Disconnect()
State.StateChangedConnection = nil
```

Also: disconnect a *previous* connection before replacing a field, and make `Init`
idempotent so a second call cannot double-subscribe.

---

## 10. Oversized modules

```lua
-- BAD: ProceduralAnimator.luau, 1407 lines
-- joint caching + locomotion + jump + gestures + IK + FABRIK + waves + networking + API
```

**Consequences:** unreviewable, untestable in pieces, merge conflicts on every change, and
require-time cost grows for every consumer even if they need one function.

**Instead:** split by **concern**, not by line count. The target is under 500 lines, but the
real goal is one clear responsibility per module. Proof that it is safe: the 1407 → 448 line
split changed no behaviour, and the `api` suite confirmed all 136 exports were preserved.

---

## 11. Weak typing, `--!nocheck`, excessive `any`, warning suppression

```lua
-- BAD
local function Update(state: any, dt: any): any
    return state.Value + dt
end
```

**Consequences:** a typo in a field name becomes a silent `nil` instead of a compile error.
`--!nocheck` and `--!nonstrict` at the top of a file disable the tool that would have caught
half the defects in this document.

**Instead:** `--!strict` plus explicit types on exported functions and state tables. No
`--!nocheck`, no blanket `any`, no `--!nolint` comments.

> **Status (2026-11-06): APPLIED.** Every `.luau` declares `--!strict` and the analysis is
> clean (0 errors / 0 warnings; 40 pre-existing definition gaps at engine boundaries).
> Keep it that way: new files must declare `--!strict` on line 1, and new type gaps must be
> justified at the engine boundary, not papered over with `any`.

---

## 12. Duplicating a constant instead of importing it

```lua
-- BAD: three modules each define their own stride; they will drift
local PoseBytesPerJoint = 12    -- in PoseBuffer
local BytesPerJoint = 12        -- in NetworkConstants
local JointStride = 12          -- invented later
```

**Instead:** one owner. `PoseBuffer` owns the pose stride, `AnimationNetworkConstants` owns
the packet stride, and anything that needs a value requires the owner.

If two modules need the same primitive and requiring one from the other creates a cycle,
extract a **leaf module** (see GoodPractices §2) — do not copy the value.

---

## 13. Trusting a previous session's completion claim

**Occurred:** `Memory.md` recorded "Phase 3: PASS", while the actual tree was still flat and
did not satisfy the phase's own exit criteria. Both were true by different definitions, and
the ambiguity cost time.

**Instead:** verify against **exit criteria and source**, not against a status word. Run the
suite, `wc -l` the files, enumerate exports. Report `PARTIAL` when only part of an exit
criterion is met.

---

## 14. Reporting success without evidence

Never write "works", "fixed" or "optimised" without one of:

- a passing harness suite,
- byte-level packet comparison,
- line counts,
- export enumeration,
- a quoted source line.

**Never fabricate** profiling numbers, Play-mode results, or benchmark timings. If something
was not measured, say **NOT TESTED**. If this environment cannot test it, say **BLOCKED** and
explain what would be needed.

Play mode is prohibited here. "Verified in Play" is not available as evidence and must never
be claimed.
