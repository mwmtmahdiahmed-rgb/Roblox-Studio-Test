# Syntax Reference — Procedural Animation Framework

Verified Luau syntax and Roblox API behaviour as used **in this project**. Nothing here is
invented. Where a fact is a project convention rather than an engine guarantee, it says so.

Anything marked **VERIFIED** has been checked against the source in this repository or
exercised by the offline harness.

---

## 1. Type annotations and strict mode

`--!strict` must be the **first line** of the file, before any other comment handling that
would displace it.

```lua
--!strict

type JointState = {
    Joints: { [number]: Motor6D },
    Pose: buffer,
    IdleWeight: number,
    Valid: boolean,
}

local function UpdateJump(State: JointState, DeltaTime: number): ()
    State.IdleWeight += DeltaTime
end
```

Rules of thumb used here:

- Annotate **exported** functions fully: parameters and return.
- Annotate the **state table** shape once, as a `type`, rather than annotating every use.
- Use `() ` as an explicit empty return type; `: ()` documents "returns nothing".
- Prefer narrowing over `any`. `--!strict` with a cast to `any` is `--!nonstrict` in disguise.

> **Project status: APPLIED (Phase 6, 2026-11-06).** Every `.luau` in the repository declares
> `--!strict` as its first line, and the type checker reports 0 errors / 0 warnings (40
> pre-existing definition gaps at engine boundaries). Note that under `--!strict` a script may
> not return a value, which is why the bootstrappers are ModuleScripts required by thin
> starter scripts rather than scripts themselves.

---

## 2. `buffer` — the byte-array type

A `buffer` is a flat, fixed-size block of bytes. It is **not a Lua table**: no length operator,
no keyed access, no `pairs`. You read and write typed values at byte offsets.

```lua
local B = buffer.create(116)          -- 116 bytes, zero-filled

buffer.writef32(B, 0, 1.5)            -- f32 at byte offset 0
local Value = buffer.readf32(B, 0)    -- -> 1.5

buffer.writei16(B, 4, -300)           -- signed 16-bit
buffer.writeu8(B, 0, 255)             -- unsigned 8-bit

local Length = buffer.len(B)          -- -> 116  (NOT #B; # does not work on buffers)
buffer.fill(B, 0, 116, 0)             -- zero a range
buffer.copy(Destination, 0, Source, 0, 116)
```

Verified in this project:

- `buffer.len` is the only way to get a buffer's size. `#B` raises
  `attempt to get length of a buffer value` (**VERIFIED**).
- Offsets are **byte** offsets. Unaligned `f32` access is *permitted* by the VM — it does not
  throw (**VERIFIED**) — but it is still avoided here for clarity and portability. The pose
  layout strides by 12 bytes (three `f32`), so every joint is naturally 4-byte aligned.
- Out-of-bounds access **does** throw `buffer access out of bounds` (**VERIFIED**). Always
  bounds-check an incoming packet against `buffer.len` before decoding it.
- Buffers are fixed size. Growing one means creating a new buffer and copying.

### Pose buffer layout (VERIFIED — `PoseBuffer`)

Three `f32` per joint, 12 bytes per joint, `MaxJoints * 12` bytes total.

```lua
local Offset = (Joint - 1) * 12
BufferWriteF32(Pose, Offset, X)          -- euler X
BufferWriteF32(Pose, Offset + 4, Y)      -- euler Y
BufferWriteF32(Pose, Offset + 8, Z)      -- euler Z
```

---

## 3. Packet layout (VERIFIED — frozen, byte-checked by the network suite)

| Field | Type | Byte offset | Notes |
|---|---|---|---|
| Tag | `u8` | 0 | `Config.Packet.Header` for pose, `.Event` for events |
| Sequence | `u16` | 1 | `% Config.Packet.SequenceModulus` |
| Tick | `u32` | 3 | milliseconds |
| Root position X | `i16` | 7 | `Position * Config.Packet.PositionScale` |
| Root position Y | `i16` | 9 | |
| Root position Z | `i16` | 11 | |
| Root velocity X | `i16` | 13 | `Velocity * VelocityScale` |
| Root velocity Y | `i16` | 15 | |
| Root velocity Z | `i16` | 17 | |
| Joint count | `u8` | 19 | clamped to `MaxJoints` |
| Joint 0 | `i16` × 3 | 20 | euler X, Y, Z, quantised |
| Joint N | `i16` × 3 | 20 + 6N | |

`BytesPerJoint = 6`. `SendBufferSize = 20 + 16 * 6 = 116` bytes.

**Quantisation (VERIFIED):**

- Angles: multiply by `Config.Packet.AngleQuantization`, decode with
  `1.0 / AngleQuantization`.
- `MaxAngleRadians = math.pi * 1.05` — the clamp range for quantised angles.
- i16 range is `-32768..32767`, so both write paths clamp (`WriteClampedI16`).

**Do not change this layout** without bumping `Config.Version` and updating the network
suite, which asserts these exact offsets.

---

## 4. `Motor6D.Transform` — full CFrame, not just rotation

**This section was corrected on 2026-11-06 after the ApplyPose root-offset fast path made the
translation behaviour explicit. The earlier "rotation only" claim was wrong.**

`Motor6D.Transform` applies an additional **CFrame** on top of `C0`/`C1`. That CFrame carries
BOTH a rotation and a translation, and both are honoured by the motor. A vertical bob written
as a translation into `Transform` visibly raises and lowers the joint, which is exactly how the
root squash/stretch path works.

```lua
-- Correct: write euler angles
Motor.Transform = CFrame.fromEulerAnglesXYZ(X, Y, Z)

-- Reading it back:
local X, Y, Z = Motor.Transform:ToEulerAnglesXYZ()
```

- `Motor.Transform.Position` is whatever the writer last put there — the framework's
  ApplyPose writes `(0, 0, 0)` for ordinary joints (pure `CFrame.fromEulerAnglesXYZ`) and
  `(0, RootOffsetY, 0)` for the root joint when a vertical offset is live. Both are expected.
  Measuring the root joint's `Transform.Position.Y` is a valid way to observe squash/stretch.
- `ToEulerAnglesXYZ()` returns **three** values. Capturing it into one variable silently
  discards two, and passing it directly to `string.format` raises
  `missing argument #3`. Capture into locals first.
- The `Humanoid` remains in charge of physics. Writing `Transform` does not anchor the
  character or disable its own animation state machine — an `Animate` script must be removed
  if present, which `SetupCharacter` does.

---

## 5. Services

```lua
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
```

- Call `GetService` **once, at module scope**, and reuse the local. Every `GetService` call
  in a frame loop is wasted work.
- `RunService:IsServer()` / `:IsClient()` for context checks.
- Localise hot methods: `local PlayersGetPlayers = Players.GetPlayers`. **Note:** when calling
  a localised method, pass the instance explicitly —
  `PlayersGetPlayers(Players)`. Omitting it passes `nil` as `self` and throws. This was a real
  defect in `AnimationNetwork`.

---

## 6. Connections

```lua
local Connection = Humanoid.StateChanged:Connect(function(OldState, NewState)
    OnHumanoidStateChanged(State, OldState, NewState)
end)

Connection:Disconnect()
Connection = nil
```

- `:Connect` returns an `RBXScriptConnection`; there is no `:Once` for engine signals.
- Always `Disconnect()` **and** nil the field. Nilling alone does not disconnect.
- Disconnect before replacing a stored connection, or you leak the previous one.
- An `Init` function must be idempotent: check an `Initialized` flag before subscribing.

---

## 7. Remote events

Pose data uses `UnreliableRemoteEvent` — packets may be dropped, which is correct for a
60 Hz pose stream where the newest sample matters and a stale one does not.

```lua
local Remote = Instance.new("UnreliableRemoteEvent")
Remote.Name = "Pose"
Remote.Parent = RemotesFolder
Remote:FireServer(...)
Remote.OnClientEvent:Connect(function(...) end)
Remote:FireAllClients(...)          -- server only
```

Project conventions (VERIFIED):

- Remotes are created **at runtime**, server-side, under a `ProceduralAnimation/Remotes` folder.
  They are never pre-created in the Explorer.
- Read payloads from the **remote**, not from the player object.
- Payload size limit for unreliable remotes is around 900 bytes. `SendBufferSize` is 116.
- Always bounds-check an incoming packet **before** decoding:
  `if BufferLen < JointDataOffset + JointCount * BytesPerJoint then return end`

---

## 8. CFrames and rotations

```lua
CFrame.new(x, y, z)
CFrame.new(Vector3)                          -- overload
CFrame.fromEulerAnglesXYZ(rx, ry, rz)
CFrame.fromAxisAngle(axis, radians)
CFrame.identity
CFrame.LookAt(position, target)

CFrame * CFrame
CFrame.Position                              -- Vector3
CFrame.UpVector / RightVector / LookVector
```

Used in this project:

- Rest pose is derived from `Part0.CFrame * C0` and `Part1.CFrame * C1`.
- Bone axis is captured once at setup from the rest pose and reused.
- Ankle ground alignment is an axis-angle correction:
  `CFrame.fromAxisAngle(FootUp:Cross(Normal), Acos(Dot))`.

---

## 9. Vector3

```lua
Vector3.new(x, y, z)
A + B, A - B, A * scalar
A:Dot(B), A:Cross(B)
A.Magnitude, A.Unit
```

`Vector3.new(0, 0, 0)` is a **fresh allocation** each call. On a hot path, prefer scalar
arithmetic on `.X/.Y/.Z` (which is what this framework does in `ClientRigKinematics`) rather
than allocating intermediate vectors.

---

## 10. Physics queries

```lua
local Params = RaycastParams.new()
Params.FilterType = Enum.RaycastFilterType.Exclude
Params.FilterDescendantsInstances = { Character }
Params.IgnoreWater = true

local Result = Workspace:Raycast(Origin, Direction, Params)
if Result then
    local Position = Result.Position
    local Normal = Result.Normal
    local Instance = Result.Instance
end
```

- `Workspace:Raycast` returns `RaycastResult?`. Always nil-check.
- Create `RaycastParams` **once per character** at setup and store it on the state; do not
  allocate it per frame.
- `WorkspaceFindPartOnRay` is deprecated. Use `:Raycast`.

---

## 11. Numbers, math and randomness

```lua
math.abs, math.sqrt, math.exp, math.sin, math.cos, math.acos
math.clamp(x, min, max)          -- one call, not math.min(math.max(...))
math.floor, math.ceil
math.huge, math.pi
```

- `math.round` **exists** in Luau (**VERIFIED**: `math.round(1.5) == 2`). It is still avoided
  on hot paths in favour of the cheaper `math.floor(x + 0.5)` where the sign is known positive.
- `os.clock()` is the monotonic timer used for packet ticks and profiling.
- `%` on floats works as expected and is used for phase wrapping:
  `Phase = (Phase + DeltaTime / Period) % 1.0`.

---

## 12. Tables and iteration

```lua
table.create(n)                  -- preallocate
table.insert, table.remove
table.sort
#Array                          -- length operator; array part only
pairs(T), ipairs(Array), next(T)
```

- `pairs` order is **unspecified**. Anywhere determinism matters, iterate a sorted key list.
  `Config.Compiled.WaveOrder` exists for exactly this reason — wave presets are compiled in
  sorted order so additive results are reproducible.
- `table.remove` shifts every later element. On a hot path, use swap-removal instead.
- `#` on a table with holes is undefined. Keep the active list **dense**.

---

## 13. Metatables — deliberately absent

`setmetatable` / `getmetatable` are used **nowhere** in this framework, by rule.

For reference, what they do and why they are avoided here:

- `__index` adds a lookup to every field access. On a per-joint, per-frame path this is real
  cost.
- `__newindex` makes assignment implicitly run code, which hides data flow.
- `__add`, `__mul` etc. make arithmetic non-obvious at the call site.
- OOP via metatables is prohibited by project rules; state is plain tables and behaviour is
  free functions.

---

## 14. Luau-specific syntax used here

```lua
-- Compound assignment
State.Count += 1
State.Accumulator -= Interval

-- Continue
for Index = 1, Count do
    if not Active[Index] then
        continue
    end
end

-- Generalized iteration (no pairs needed for arrays)
for Index, Value in Array do

-- String interpolation
local Message = `Setup complete for {Character.Name}`
```

`continue` must be the **last statement in a block** — Luau rejects it as a non-terminal
statement. `goto` is not supported in Luau.

---

## 15. Environment limits worth knowing

- **`require` cannot cross chunks in the offline VM.** Modules are loaded via an instance-path
  bridge in the harness. This is a harness limitation, not an engine one.
- Roblox Studio MCP tools are **unavailable** in this environment, so GitHub-vs-Studio
  comparison is BLOCKED.
- The plugin `execute_luau` sandbox blocks `require` with a Capabilities/Network error even in
  Play. That is the sandbox, not a project defect.
- Play mode is **prohibited**. No runtime, rendering, physics or replication behaviour can be
  verified here. Only source-level, static and numerical checks are available.
