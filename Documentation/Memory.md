# Project Memory — Procedural Animation Framework

> Read this first, every session. It is the fastest way to learn what exists, what is
> finished, what is broken, and what to do next. If this file and the source disagree,
> **the source wins** — and this file is then wrong and must be corrected.

Last verified: 2026-11-06, branch `arena/53eb14ce-roblox-studio-test`.

---

## 1. What this project is

`Slop Game` (placeId `139066482915692`). A procedural animation framework for Roblox avatars,
supporting R15 today and R6 where practical.

Every animated joint is driven by writing to `Motor6D.Transform`. The `Humanoid` stays alive and
remains in charge of physics, collision and network ownership. We never replace Humanoid
animation with a custom solver that owns character motion — we layer on top of it.

Feature set:

- Locomotion blending: idle / walk / run, weight-blended, driven by horizontal speed.
- Jump state machine: grounded → anticipation → launch → airborne → landing → recovery.
- Additive gestures: wave, point, nod, with fade-in / hold / fade-out.
- Two-bone IK for arms, plus foot raycasting and ground alignment.
- FABRIK chains for multi-bone procedural chains.
- Wave-driven secondary motion.
- Networked pose replication over `UnreliableRemoteEvent`.

---

## 2. Where things live

```
ROJO_OHIO_MUMBAI/                       <- maps to the Roblox DataModel root
├── ReplicatedStorage/
│   └── ProceduralAnimation/
│       ├── Client/
│       │   └── Runtime/                <- 8 client runtime modules
│       └── Shared/
│           ├── AnimationConfig.luau    <- aggregator
│           ├── AnimationMath.luau      <- aggregator
│           ├── AnimationNetwork.luau   <- aggregator
│           ├── Changelog.luau          <- append-only history
│           ├── Config/
│           │   ├── Data/               <- ConfigData, ConfigMotion
│           │   └── Compile/            <- ConfigCompile
│           ├── Math/
│           │   ├── Core/ Curves/ IK/ Waves/
│           └── Networking/
│               ├── Constants/          <- NetworkConstants
│               └── Receive/            <- NetworkReceive
├── ServerScriptService/                <- server bootstrapper
├── ServerStorage/ZeroScript/           <- Memory + backups
└── StarterPlayerScripts/               <- client bootstrapper
```

`Client/Bootstrap` and `Server/` do not exist as folders, deliberately. The bootstrappers live
where Roblox requires them (`StarterPlayerScripts` and `ServerScriptService`); moving them into
`ReplicatedStorage` would stop them running. Priority 4 explicitly does not create empty folders.

### Client modules (`ProceduralAnimation/Client/Runtime/`)

| Module | Lines | Responsibility |
|---|---|---|
| `ProceduralAnimator` | 448 | Entry point, public API, heartbeat loop, player tracking, init wiring |
| `ClientPosePipeline` | 430 | Clip sampling, overlay blending, pose application, locomotion weights, send pacing |
| `ClientRigKinematics` | 378 | FABRIK, waves, two-bone solver, `ApplyWorldDirection`, foot/hand IK |
| `CharacterLifecycle` | 266 | `CreateState` / `SetupCharacter` / `TeardownCharacter`, joint validation |
| `CharacterMotionState` | 152 | Jump state machine, gesture playback |
| `CharacterJoints` | 141 | Motor6D discovery, joint caching, limb-length measurement |
| `StatePool` | 63 | Character registry: lookup map + dense active list + swap-removal |
| `PoseBuffer` | 43 | Leaf module: 12-byte-per-joint stride, `WritePoseAdd` / `WritePoseBlend` |
| `PlayerTracker` | 98 | Player lifecycle: global + per-player connections, all releasable |

### Shared modules (`ProceduralAnimation/Shared/`)

| Module | Lines | Responsibility |
|---|---|---|
| `Config/Data/ConfigData` | 473 | Constants, joint indices, clip authoring, gesture/FABRIK/wave data |
| `Math/Core/MathCore` | 467 | Easing, lerp, slerp, shortest-angle, smoothing |
| `AnimationNetwork` | 441 | Remotes, server relay, client jitter buffer, quantization, send/receive |
| `Math/Curves/MathCurves` | 242 | Bezier, spline compilation and sampling |
| `Changelog` | 194 | Append-only change history + capped runtime log |
| `Networking/Receive/NetworkReceive` | 148 | Packet decoding into the jitter buffer |
| `Networking/Constants/NetworkConstants` | 130 | Packet layout, buffer/math aliases, quantization constants |
| `Math/Waves/MathWaves` | 120 | `Noise1D`, `SampleWave`, `CompileWave`, `SampleCompiledWave` |
| `Config/Data/ConfigMotion` | 119 | Clip authoring helpers, motion curves |
| `Math/IK/MathIK` | 109 | `SolveFabrik` |
| `Config/Compile/ConfigCompile` | 105 | Compile pass: turns authored data into runtime clip tables |
| `Utilities/Connections` | 71 | Connection tracker: `New`/`Add`/`DisconnectAll`/`Count` |
| `AnimationMath` | 15 | Thin aggregator loader |
| `AnimationConfig` | 13 | Thin aggregator loader |

### Bootstrappers

| Script | Lines | Role |
|---|---|---|
| `StarterPlayerScripts/ProceduralAnimationClient.local.luau` | 66 | `Animator.Init()`, local-character wiring, aborts cleanly if the folder never replicates; returns a `Bootstrap` handle with `Destroy` |
| `ServerScriptService/ProceduralAnimationServer.legacy.luau` | 62 | `Network.Init()`, relay setup, tracked player signals; returns a `Server` handle with `Destroy` |

> **Naming caveat.** These two `.luau` extension suffixes are *harness conventions* that tell
> `Tools/verify/verify.mjs` what instance class to mock (`.local` → `LocalScript`,
> `.legacy` → `Script`). They are not Rojo filename conventions, and no `*.project.json`
> currently exists in the repository. See §7.

### Documentation

`Documentation/` holds `Memory.md`, `GoodPractices.md`, `BadPractices.md`,
`SyntaxReference.md`, `Changelog.md`. The Canonical `Changelog` is also still maintained as a
Luau module at `Shared/Changelog.luau`, because runtime code reads `Changelog.Entries` and
`Changelog.Log`.

---

## 3. Conventions

- **PascalCase** for every identifier: locals, functions, fields, parameters.
- **Functional, data-oriented.** No OOP, no classes, no metatables, no inheritance, no `self`.
  Behaviour is free functions over plain tables.
- **Aggregator + factory pattern.** `AnimationMath` and `AnimationConfig` are thin loaders;
  the real code lives in focused sub-modules. Sub-modules are called as
  `require(script.Parent.X)(Aggregator, Private)` and populate the aggregator table.
- **Dependency injection for the client split.** Extracted modules are constructed with a
  dependency table. None of them requires `ProceduralAnimator` back, which is what keeps the
  require graph acyclic.
- **Integer-indexed joints.** `Config.JointIndex` provides named access; hot paths use the
  integer directly. No string keys per frame.
- **Buffer-based pose storage.** One `buffer` per character; `buffer.readf32` / `writef32`.
  No per-frame allocation in the pose path.
- **Config centralised.** Every tunable lives in `AnimationConfig`. No magic numbers in the
  runtime.

---

## 4. Key systems

### AnimationMath — 25 exports

Required by the phase spec and **all present and verified**:

`CompileWave`, `SampleWave`, `SampleCompiledWave`, `Noise1D`, `SolveFabrik`.

Supporting: `Ease`, `EasingFunctions`, `EasingCount`, `Clamp01`, `SmoothFactor`,
`ShortestAngle`, `LerpNumber`, `LerpVector3`, `SlerpCFrame`, `LerpCFrame`, `BezierQuadratic`,
`BezierCubic`, `BezierQuadraticDerivative`, `BezierCubicDerivative`, `RegisterBezierCurve`,
`GetSamplerCount`, `CompileSpline`, `SampleSpline`, `Pi`, `TwoPi`.

### AnimationNetwork — 11 exports

`Init`, `IsReady`, `BindLocal`, `FireBus`, `SendPose`, `SendEvent`, `RegisterPlayer`,
`UnregisterPlayer`, `SampleRemotePose`, `HasRemotePose`, `ReleaseRemotePose`.

### ProceduralAnimator — 13 exports

`Init`, `IsRunning`, `Start`, `Stop`, `SetupCharacter`, `TeardownCharacter`,
`SetLocomotionWeight`, `SetIkTarget`, `PlayGesture`, `StopGesture`, `SetEasingOverride`,
`SetPreviewMode`, `BindToEvent`.

Public API is locked by `Tools/verify/baseline/api.json`: **138 exports across 6 modules**.
The `api` suite fails if any export is removed or changes shape.

### Lifecycle (Phase 4)

Both sides now have a real shutdown path, and every engine connection is retained:

| Owner | Hook | Releases |
|---|---|---|
| `ProceduralAnimator` | `Destroy()` | heartbeat, player tracker, every character state, state pool, event callbacks |
| `AnimationNetwork` | `Shutdown()` | remote event handlers, server player registry |
| client bootstrapper | `Bootstrap.Destroy()` | local player's `CharacterAdded` / `CharacterRemoving` |
| server bootstrapper | `Server.Destroy()` | `PlayerAdded` / `PlayerRemoving`, then `Network.Shutdown()` |

Rules that follow from this:

- `Destroy` / `Shutdown` are **idempotent** (safe to call twice) and **terminal** — `Init` refuses
  to run afterwards. Reviving would need every pooled buffer rebuilt; reloading the module is safer.
- Every `:Connect` in the project is retained by a tracker or a state field. The `lifecycle` suite
  asserts this mechanically by scanning the source for unretained `:Connect` calls.

### Packet layout (frozen — do not change without a version bump)

20-byte header then 6 bytes per joint:

| Field | Type | Offset |
|---|---|---|
| Tag | `u8` | 0 |
| Sequence | `u16` | 1 |
| Tick | `u32` | 3 |
| Root position | `i16` × 3 | 7 |
| Root velocity | `i16` × 3 | 13 |
| Joint count | `u8` | 19 |
| Joint data | `i16` × 3 per joint | 20 |

`SendBufferSize = 116` bytes for 16 joints. Comfortably under the ~900-byte unreliable limit.

---

## 5. Decisions and gotchas

### The AnimationConstraint blocker (UNRESOLVED, by design)

**This is the single most important thing to know.**

The default player character in this place is a **skinned-mesh R15 rig with zero `Motor6D`**.
Its joints are 15 `AnimationConstraint` instances (Root, Waist, Neck, Left/Right Shoulder,
Elbow, Wrist, Hip, Knee, Ankle) plus `BallSocketConstraint` / `RigidConstraint` and 54
attachments. The character has no `Animator` instance.

The framework writes `Motor6D.Transform` throughout, so `CacheJoints` finds no Motor6D and
setup aborts with `missing R15 joint Waist`.

Supporting this rig is an **architectural decision that has not been taken**. Two options:

1. Drive `AnimationConstraint.Transform` instead of `Motor6D.Transform`.
2. Force a `Motor6D` rig (e.g. load a classic rig, or convert on spawn).

**Character setup cannot succeed on the current default rig regardless of any other fix.**
Do not report the framework as functional until this is resolved. It is explicitly out of
scope for the defect list in Phase 2 and must not be silently "fixed" inside an unrelated phase.

### Other verified behaviour

- Chest joint is optional — stock R15 has no Chest `Motor6D`. The framework warns and continues.
- `Config.RequireOptionalJoints` gates the optional-joint policy in `CacheJoints`.
  It used to be dead code.
- `SlerpCFrame` falls back to normalised lerp when `dot > 0.9995`, to avoid `sin(theta)`
  precision loss.
- `SlerpCFrame` originally discarded translation. Fixed: it now interpolates position into the
  quaternion result. Regression-guarded.
- Jump detection uses `Humanoid.StateChanged` plus a `FloorMaterial` poll, because
  `StateChanged` alone misses ledge falls.
- Ankle alignment is applied as an axis-angle correction through `Motor6D.Transform`.
- Preview mode anchors only `HumanoidRootPart`.
- Remotes are created at runtime under a `ProceduralAnimation/Remotes` folder.
- Zero-weight clips and joints are skipped before any buffer work.
- `Motor6D.Transform` carries **rotation only**. `ApplyPose` writes
  `CFrame.fromEulerAnglesXYZ(X, Y, Z)`; translation stays in `C0`, so
  `Transform.Position` remains `(0,0,0)` even when animation is working perfectly.
  **Measure pose via `Transform:ToEulerAnglesXYZ()`.** Never report a zero `Position` as
  "animation is broken".

---

## 6. How to verify anything

Play mode is **prohibited** unless explicitly authorised. Never claim a runtime result.

```bash
cd Tools/verify
npm install          # first time only
node verify.mjs      # full run
node verify.mjs --no-analysis          # skip the type checker
node verify.mjs --only=integration     # one suite
node verify.mjs --snapshot-baseline    # re-record the public API surface
```

The harness runs a real Luau VM (`@luau-rs/luau` 0.739.0) with mocked Roblox value types and
services. It is not a mock of Lua — it is actual Luau, so syntax, semantics and `--!strict`
analysis are genuine.

| Suite | Cases | What it proves |
|---|---|---|
| `math` | 80 | Easing, bezier, spline, waves, noise, FABRIK, lerp/slerp numerics |
| `config` | 62 | Joint tables, clip compilation, gesture data, packet constants |
| `network` | 67 | Packet layout byte-by-byte, quantization round-trip, bounds rejection |
| `integration` | 54 | Boot, setup, pose actually changes, IK, gestures, throttling, teardown |
| `bootstrap` | 26 | Both bootstrappers execute, lifecycle, require graph acyclic, size rule |
| `api` | 2 | 138 exports unchanged vs `baseline/api.json` |
| `lifecycle` | 50 | Connection tracker, `Destroy`/`Shutdown`, player tracking, no bare connects |

**Latest result: PASS 377 | FAIL 0 | BLOCKED 0, 26/26 files compile.**

Known harness limitations:

- Type checking (`--analysis`) is wired but the Roblox definitions file is not yet written,
  so it is run with `--no-analysis` and does not currently verify strict-mode cleanliness.
- Verification is source-level. It cannot prove Studio behaviour, rendering, or physics
  interaction.
- A passing suite proves the tested property, not the absence of all defects.

---

## 7. Open issues

### Phase 4 result

**PASS (source + harness verified).** Lifecycle, duplicate-init protection and full cleanup are
in place on both sides and covered by 50 assertions. Note this is *lifecycle* verification, not
proof that animation runs on a real character — see the rig blocker above.

### Verification / tooling

- **Analysis (type checker) disabled.** Needs `roblox-definitions.luau`. This is the last
  outstanding item of the Phase 3 exit criteria that concerns typing.
- **No `*.project.json`.** The repository has no Rojo project file, so the
  `ROJO_OHIO_MUMBAI/` → DataModel mapping is a convention enforced only by the harness
  (filename suffixes and directory names). Worth adding a real project file.
- **Studio comparison never performed.** Studio MCP tools are unavailable in this environment.
  GitHub-vs-Studio parity is therefore **BLOCKED**, not verified.

### Structure

- **Phase 3 hierarchy: DONE** (2026-11-06). `Client/Runtime/`, `Shared/Config/{Data,Compile}`,
  `Shared/Math/{Core,Curves,IK,Waves}` and `Shared/Networking/{Constants,Receive}` now match the
  target. `Client/Bootstrap` and `Server/` were deliberately not created — see the structure note
  above. Verified: 18 require edges, 0 load errors, no cycles, 325/325 cases.
- **`AnimationNetwork` is 441 lines and mixes four responsibilities:** remote creation,
  server relay, send path and client jitter buffer. The target structure calls for
  `Networking/{Constants,Send,Receive}`. This is the sharpest remaining structural problem.
- **`ProceduralAnimationServer.legacy.luau`** — the `legacy` suffix is a harness artifact, not
  a rename of the live script. Needs a decision before any Rojo project file is added. (Known
  issue: this is why `Server/Runtime` does not exist yet.)

### Features

- R6 support: **not implemented.** All joint tables and clip data are R15.
- Phases 6–10 not started: strict typing migration, performance pass, feature completion,
  regression audit, maintenance procedures.

---

## 8. Session start checklist

1. Read `Memory.md`, `GoodPractices.md`, `BadPractices.md`, `SyntaxReference.md`, `Changelog.md`.
2. `cd Tools/verify && node verify.mjs --no-analysis` — establish the real baseline.
   **Do not trust the numbers in this file; run it.**
3. `wc -l` every script; confirm the 500-line rule still holds.
4. Read the source of any module you intend to touch.
5. Verify the API surface is still 136 exports.

## 9. Session end checklist

1. Re-run the full suite.
2. Update this file with the new state and any new gotcha.
3. **Append** to `Shared/Changelog.luau` — never overwrite, never renumber historical entries.
4. Mirror the entry into `Documentation/Changelog.md`.
5. Re-read both.
