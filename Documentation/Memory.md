# Project Memory — Procedural Animation Framework

> Read this first, every session. It is the fastest way to learn what exists, what is
> finished, what is broken, and what to do next. If this file and the source disagree,
> **the source wins** — and this file is then wrong and must be corrected.

Last verified: 2026-11-06, `main` @ `5109f27` (PR #6 `5cda17d`, PR #7 `5109f27`); re-verified on branch `arena/eca5694a-roblox-studio-test`.

---

## 1. What this project is

`Slop Game` (placeId `139066482915692`). A procedural animation framework for Roblox avatars,
supporting R15 today and R6 where practical.

Every animated joint is driven by writing to `Motor6D.Transform`. The `Humanoid` stays alive and
remains in charge of physics, collision and network ownership. We never replace Humanoid
animation with a custom solver that owns character motion — we layer on top of it.

Feature set:

- Locomotion blending: idle / walk / run, weight-blended, driven by horizontal speed
  (smoothed with an exponential low-pass, `Config.VelocityFilterRate`).
- Jump state machine: grounded → anticipation → launch → airborne → landing → recovery.
- Squash & stretch: damped spring on the root vertical offset, kicked by a fall-speed-scaled
  impulse on landing (`Config.SquashStretch`).
- Additive gestures: wave, point, nod, with fade-in / hold / fade-out.
- Two-bone IK for arms, plus foot raycasting and ground alignment.
- FABRIK chains for multi-bone procedural chains.
- Wave-driven secondary motion.
- Head look-at: neck aims toward a world target, exponentially smoothed
  (`Animator.SetLookAtTarget`, `Config.LookAt`).
- Per-joint amplitude control (`Animator.SetJointAmplitude`).
- Constant-speed spline sampling via compile-time arc-length tables
  (`MathLib.GetSplineLength`, `MathLib.SampleSplineAtDistance`).
- Configurable damped springs (`MathLib.StepSpring`).
- Networked pose replication over `UnreliableRemoteEvent`.

---

## 2. Where things live

```
ROJO_OHIO_MUMBAI/                       <- maps to the Roblox DataModel root
├── ReplicatedStorage/
│   └── ProceduralAnimation/
│       ├── Client/
│       │   ├── Runtime/                <- 10 client runtime modules
│       │   └── Bootstrap/              <- ClientBootstrap ModuleScript (require-time init)
│       ├── Server/
│       │   └── Bootstrap/              <- ServerBootstrap ModuleScript
│       └── Shared/
│           ├── AnimationConfig.luau    <- aggregator
│           ├── AnimationMath.luau      <- aggregator
│           ├── AnimationNetwork.luau   <- aggregator
│           ├── Changelog.luau          <- append-only history
│           ├── Config/Data/            <- ConfigData, ConfigMotion
│           ├── Config/Compile/         <- ConfigCompile
│           ├── Math/{Core,Curves,IK,Waves}/
│           ├── Networking/{Constants,Receive}/
│           └── Utilities/              <- Connections
└── ServerScriptService/                <- server entry (thin, harness-suffixed name)
├── ServerStorage/ZeroScript/           <- Memory + backups
└── StarterPlayerScripts/               <- client entry (thin, harness-suffixed name)
```

The `.luau` extension suffixes (`.local` → LocalScript, `.legacy` → Script) are harness
conventions read by `Tools/verify/verify.mjs`; the Rojo build in `ProceduralAnimation.project.json`
instead forces instance classes explicitly via tree keys. Both must stay in sync — `rojo-check.mjs`
enforces the link statically.

The StarterPlayer / ServerScriptService entries are **thin harness-legal scripts** (a LocalScript
may not return values, and scripts may not return values in `--!strict`); they `require` the
`Client/Bootstrap` / `Server/Bootstrap` ModuleScripts inside `ProceduralAnimation`, which contain
all lifecycle logic and expose `Destroy`.

### Client modules (`ProceduralAnimation/Client/Runtime/`)

| Module | Lines | Responsibility |
|---|---|---|
| `ProceduralAnimator` | 468 | Entry point, public API (15 methods), heartbeat loop, player tracking, init wiring |
| `ClientPosePipeline` | 475 | Clip sampling, overlay blending, pose application (+ per-joint amplitude), locomotion weights (+ velocity filter), jump integration, squash spring, look-at call |
| `ClientRigKinematics` | 443 | FABRIK, waves, two-bone solver, `ApplyWorldDirection`, `ApplyLookAt`, foot/hand IK |
| `CharacterLifecycle` | 280 | `CreateState` / `SetupCharacter` / `TeardownCharacter`, joint validation |
| `CharacterMotionState` | 171 | Jump state machine (+ landing squash impulse), gesture playback |
| `CharacterJoints` | 142 | Motor6D discovery, joint caching, limb-length measurement |
| `StatePool` | 74 | Character registry: lookup map + dense active list + swap-removal + `PendingRemovals` early-out |
| `PoseBuffer` | 44 | Leaf module: 12-byte-per-joint stride, `WritePoseAdd` / `WritePoseBlend` |
| `PlayerTracker` | 98 | Player lifecycle: global + per-player connections, all releasable |

### Shared modules (`ProceduralAnimation/Shared/`)

| Module | Lines | Responsibility |
|---|---|---|
| `Config/Data/ConfigData` | 494 | Constants, joint indices, clip authoring, gesture/FABRIK/wave data, `VelocityFilterRate` / `SquashStretch` / `LookAt` (all new top-level keys) |
| `Math/Core/MathCore` | 485 | Easing, lerp, slerp, shortest-angle, smoothing, `StepSpring` |
| `AnimationNetwork` | 472 | Remotes, server relay, client jitter buffer, quantization, send/receive |
| `Math/Curves/MathCurves` | 336 | Bezier, spline compilation/sampling, compile-time arc-length tables |
| `Changelog` | 249 | Append-only change history + capped runtime log |
| `Config/Data/ConfigMotion` | 120 | Clip authoring helpers, motion curves |
| `Networking/Receive/NetworkReceive` | 149 | Packet decoding into the jitter buffer |
| `Networking/Constants/NetworkConstants` | 131 | Packet layout, buffer/math aliases, quantization constants |
| `Math/Waves/MathWaves` | 121 | `Noise1D`, `SampleWave`, `CompileWave`, `SampleCompiledWave` |
| `Math/IK/MathIK` | 110 | `SolveFabrik` |
| `Config/Compile/ConfigCompile` | 106 | Compile pass: turns authored data into runtime clip tables |
| `Utilities/Connections` | 65 | Connection tracker: `New`/`Add`/`DisconnectAll`/`Count` |

All files declare `--!strict` and are analysed clean (0 errors / 0 warnings; 40 pre-existing
"definition gaps" on engine-typed edges, documented in §6). Every script ≤ 500 lines.

### Documentation (`Documentation/`)

`Memory.md` (this file), `API.md` (public API reference), `Maintenance.md` (Phase 10 maintenance),
`Audit.md` (Phase 9 regression audit), `SyntaxReference.md`, `GoodPractices.md`, `BadPractices.md`,
`Changelog.md` (mirror of `Shared/Changelog.luau`). The harness does not install these; they are
for humans. `Tools/verify/README.md` orients contributors to the harness; CI lives in
`.github/workflows/verify.yml`.

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
  No per-frame allocation in the pose path (look-at builds one `Vector3` per frame, same as IK).
- **Config centralised.** Every tunable lives in `AnimationConfig`. No magic numbers in the
  runtime. New tunables are **new top-level keys** — existing config sub-tables are frozen.
- **Preallocated state.** `State.JointAmplitude`, `State.SquashSpring`, per-chain
  `State.TargetScratch`, `State.FootRayDirection` are allocated once at `CreateState`.

---

## 4. Key systems

### AnimationMath — 28 exports

Spec exports: `CompileWave`, `SampleWave`, `SampleCompiledWave`, `Noise1D`, `SolveFabrik`.

`Ease`, `EasingFunctions`, `EasingCount`, `Clamp01`, `SmoothFactor`, `ShortestAngle`,
`LerpNumber`, `LerpVector3`, `SlerpCFrame`, `LerpCFrame`, `BezierQuadratic`, `BezierCubic`,
`BezierQuadraticDerivative`, `BezierCubicDerivative`, `RegisterBezierCurve`, `GetSamplerCount`,
`CompileSpline`, `SampleSpline`, `Pi`, `TwoPi`, plus **Phase 8 additions**
`GetSplineLength`, `SampleSplineAtDistance`, `StepSpring`.

### AnimationNetwork — 12 exports

`Init`, `IsReady`, `BindLocal`, `FireBus`, `SendPose`, `SendEvent`, `RegisterPlayer`,
`UnregisterPlayer`, `SampleRemotePose`, `HasRemotePose`, `ReleaseRemotePose` + baseline entry.

> Full signature-and-semantics reference for every public export: **`API.md`**.

### ProceduralAnimator — 16 exports

`Init`, `IsRunning`, `Start`, `Stop`, `SetupCharacter`, `TeardownCharacter`,
`SetLocomotionWeight`, `SetIkTarget`, `PlayGesture`, `StopGesture`, `SetEasingOverride`,
`SetPreviewMode`, `BindToEvent`, **plus Phase 8 additions `SetJointAmplitude`, `SetLookAtTarget`**.

Public API is locked by `Tools/verify/baseline/api.json` (**138 exports baseline, 6 modules**).
The api suite fails if an existing export is removed or changes shape; **added exports are
reported, not failed**. Config fingerprint: only new top-level keys may be added.

### Lifecycle (Phase 4)

| Owner | Hook | Releases |
|---|---|---|
| `ProceduralAnimator` | `Destroy()` | heartbeat, player tracker, every character state, state pool, event callbacks |
| `AnimationNetwork` | `Shutdown()` | remote event handlers, server player registry |
| client bootstrapper module | `Destroy()` | local player's `CharacterAdded` / `CharacterRemoving` |
| server bootstrapper module | `Destroy()` | `PlayerAdded` / `PlayerRemoving`, then `Network.Shutdown()` |

- `Destroy` / `Shutdown` are **idempotent** and **terminal** — `Init` refuses to run afterwards.
- Every `:Connect` in the project is retained by a tracker or a state field.

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
Its joints are `AnimationConstraint` instances plus `BallSocketConstraint` / `RigidConstraint`
and attachments. The character has no `Animator` instance.

The framework writes `Motor6D.Transform` throughout, so `CacheJoints` finds no Motor6D and
setup aborts with `missing R15 joint Waist`.

Supporting this rig is an **architectural decision that has not been taken**. Two options:

1. Drive `AnimationConstraint.Transform` instead of `Motor6D.Transform`.
2. Force a `Motor6D` rig (e.g. load a classic rig, or convert on spawn).

**Character setup cannot succeed on the current default rig regardless of any other fix.**
Do not report the framework as functional until this is resolved. It is explicitly out of
scope and must not be silently "fixed" inside an unrelated phase.

### Other verified behaviour

- Chest joint is optional — stock R15 has no Chest `Motor6D`. The framework warns and continues.
- `Config.RequireOptionalJoints` gates the optional-joint policy in `CacheJoints`.
- `SlerpCFrame` falls back to normalised lerp when `dot > 0.9995`, to avoid `sin(theta)`
  precision loss.
- Jump detection uses `Humanoid.StateChanged` plus a `FloorMaterial` poll, because
  `StateChanged` alone misses ledge falls.
- Ankle alignment is applied as an axis-angle correction through `Motor6D.Transform`.
- Preview mode anchors only `HumanoidRootPart`.
- Remotes are created at runtime under a `ProceduralAnimation/Remotes` folder.
- Zero-weight clips and joints are skipped before any buffer work.
- `Motor6D.Transform` **carries a full 6-DOF CFrame, translation included** — writing a
  vertical bob translation into `Transform` is honoured at runtime (vertical root bob flows
  through it). Early versions of this document claimed rotation-only; that was wrong.
  **Measure pose via `Transform:ToEulerAnglesXYZ()`** and remember its `Position` may be
  non-zero by design.
- Velocity low-pass: `Config.VelocityFilterRate` (per second) smooths the horizontal speed
  that drives the locomotion blend; `0` disables the filter.
- `State.FilteredSpeed` persists the filtered value per character.

### Defects found by switching the type checker on (2026-11-06)

1. **`ClientRigKinematics` — uninitialised function upvalue.** `local ApplyWorldDirection` was
   followed later by `local function ApplyWorldDirection`, shadowing instead of assigning.
   Fix: drop the second `local`.
2. **`Tools/verify/src/02-mock-services.luau` — undefined global `UpperTorso`.** (The rig builder since moved to `02b-mock-rig.luau` in the 2026-11-06 split.) Mock rig was
   structurally invalid and hid the real FABRIK path.
3. **`CharacterMotionState` — nil `MathLib` on the jump path.** Injected from
   `ClientPosePipeline`.
4. **`AnimationNetwork.Shutdown` — bare `ReleaseRemotePose(Player)`.** Now `Network.ReleaseRemotePose`.

Also fixed: two vacuous jump tests (`Humanoid.SetState` with a dot swallowed the argument).
**Lesson:** to inspect a value inside a test, put it in a `Kit.Pass(name, detail)` or a failing
assertion — not a `print`.

---

## 6. How to verify anything

Play mode is **prohibited** unless explicitly authorised. Never claim a runtime result.

```bash
cd Tools/verify
npm install          # first time only
node verify.mjs      # full run (compile + analysis + runtime suites + API baseline)
node verify.mjs --no-analysis          # skip the type checker
node verify.mjs --only=integration     # one suite
node verify.mjs --snapshot-baseline    # re-record the public API surface
node bench.mjs                          # micro-benchmarks (machine-dependent, comparative only)
```

The harness runs a real Luau VM (`@luau-rs/luau` 0.739.0) with mocked Roblox value types and
services. It is not a mock of Lua — it is actual Luau, so syntax, semantics and `--!strict`
analysis are genuine.

| Suite | Cases | What it proves |
|---|---|---|
| `math` | 95 | Easing, bezier, spline (+ arc length), waves, noise, FABRIK, springs, lerp/slerp |
| `config` | 62 | Joint tables, clip compilation, gesture data, packet constants |
| `network` | 67 | Packet layout byte-by-byte, quantization round-trip, bounds rejection |
| `integration` | 65 | Boot, setup, pose actually changes, IK, gestures, throttling, look-at, joint amplitude, teardown |
| `bootstrap` | 26 | Both bootstrappers execute, lifecycle, require graph acyclic, size rule |
| `api` | 2 | Frozen surface vs `baseline/api.json` (additions reported, not failed) |
| `lifecycle` | 50 | Connection tracker, `Destroy`/`Shutdown`, player tracking, no bare connects |

**Latest result (2026-11-06, `main` @ `5109f27` via PR #7; re-verified on branch arena/eca5694a-roblox-studio-test): PASS 437 | FAIL 0 |
BLOCKED 0, 28/28 files compile, analysis 0 errors / 0 warnings / 40 pre-existing definition
gaps. (On branch arena/4e24aa26-roblox-studio-test: PASS 433.)**

Analysis classifications: **0 errors / 0 warnings / 40 definition gaps.** The definition file is
**partial by design** (it declares only the surface the framework touches with loose types), so
engine-boundary expressions are classified as definition gaps rather than proven. They are not
failures; a missing or rejected definition file is a hard FAIL. Gaps accepted so far are all in
engine-object `:Methods`/indexing positions — do not "fix" them by widening types to `any`.

`--!strict` migration (Phase 6): every framework script declares `--!strict` and the analysis is
clean. The verification harness chunks declare `--!strict` too (added 2026-11-06 on
arena/e0507aaf-roblox-studio-test, after the 500-line split — see §7 Tooling).
Note: scripts may not return values under strict; the bootstrappers return handles through the
required ModuleScripts instead. `any` remains only at engine-object boundaries
(86 explicit `: any` sites, documented rationale: engine userdata and dependency-injection
tables have no precise Luau type).

---

## 7. Open issues

### Phase 3 — COMPLETE

**PASS.** Target hierarchy, every script ≤ 500 lines, no duplicate modules, documentation
present, static analysis clean. Shipped in two PRs: #2 (architecture + documentation) and the PR
that closed the typing item.

Scope caveat, carried forward: this certifies *structure and analysis*, not that animation runs
on a real character. The AnimationConstraint rig blocker is untouched.

### Phase 4 — COMPLETE

**PASS (source + harness verified).** Lifecycle, duplicate-init protection and full cleanup on
both sides, covered by 50 assertions.

### Phase 5 — COMPLETE (bootstrap extraction)

Scripts may not return values, so lifecycle logic moved into `Client/Bootstrap/ClientBootstrap`
and `Server/Bootstrap/ServerBootstrap` ModuleScripts (require-time init, `Destroy()` handles).
The StarterPlayer / ServerScriptService entries are now thin require wrappers.

### Phase 6 — COMPLETE (`--!strict` migration)

Every script declares `--!strict`; analysis clean; all suites green; bootstrap extraction is
covered by the bootstrap suite (26 assertions).

### Phase 7 — COMPLETE (performance)

Measured with `node bench.mjs` (comparative, same machine):

- `StatePool.Compact` early-out via `PendingRemovals` counter: ~1021 ns → ~67 ns/call on a
  full 16-entry pool (≈15×), and steady-state frames skip the O(n) scan entirely.
- `ClientPosePipeline` root-joint write fast path (pure `CFrameAngles` when the root offset is
  immaterial): skips one CFrame composition per frame.
- FABRIK targetScratch tables (no per-frame `Vector3.new` for chain targets).
- `State.FootRayDirection` cached at state creation (raycast direction is constant).
- `Bench: SampleSpline ≈ 630 ns/op, SampleCompiledWave ≈ 1433 ns/op, Ease ≈ 224–596 ns/op`.
- Phase 8 paths benched (2026-11-06): `GetSplineLength` 136 ns/op (field read),
  `SampleSplineAtDistance` ≈ 1787 ns/op (constant-speed spline sampling; binary search +
  evaluation, ~2.8× `SampleSpline`'s cost — the price of constant speed),
  `StepSpring` ≈ 373 ns/op (semi-implicit Euler, allocation-free).

Binary search for spline segment lookup was considered and rejected: the array is ≤ 8 keys and a
linear scan measured faster and simpler.

### Phase 8 — COMPLETE (feature completion, additive only)

Version `1.1.0`. Public API gains: `Animator.SetLookAtTarget`, `Animator.SetJointAmplitude`,
`MathLib.GetSplineLength`, `MathLib.SampleSplineAtDistance`, `MathLib.StepSpring`. Config gains
three new top-level keys: `VelocityFilterRate`, `SquashStretch`, `LookAt`. **No existing export,
packet field or config sub-table changed.** Arc-length sampling is constant-speed along the
(Time, Value) graph; `StepSpring` is semi-implicit Euler (stable for the shipped stiffnesses);
look-at aims the neck in the root's frame and fades out via `SetLookAtTarget(nil)`.

### Phase 9 — COMPLETE (regression audit)

Adversarial re-read of Phases 6–8 found one real defect (look-at neck write replaced the clip
pose instead of blending toward the aim — fixed, covered by `lookat.turnsNeck/fadesOut`) and one
Natural-spline arc-length defect (missing `AttachArcLengths` on the Natural compile exit — fixed,
covered by `spline.arcLength.lineTotal`). Findings and accepted risks are in `Audit.md`,
including the one behaviour not visually verified (look-at axis signs).

### Phase 10 — COMPLETE (maintenance procedures)

`Maintenance.md` documents: the verify gate, the 500-line/placement rules, how to add a Public
API export (additions reported, baseline untouched), config-key rules (new top-level keys only),
hot-path allocation rules, the frozen packet policy, the dual changelog procedure, the release
checklist, forbidden shortcuts, and GitHub-vs-Studio reality checks.

### Tooling harness hardening — 2026-11-06 (branch arena/e0507aaf-roblox-studio-test)

The verification harness now honours the same limits as the framework. All harness `.luau`
sources open with `--!strict`, and `verify.mjs` compile-checks all of `src/` (the `MockFiles`
list, previously only 4 of 7 chunks — `04-testkit.luau` was silently uncompiled).

- **`src/01-mock-value-types.luau` split** → `01b-mock-containers.luau` (Signals, Instance mock,
  Enum). 414 + 439 lines. The 01b chunk receives the Part A mock table and extends it in place.
- **`src/02-mock-services.luau` split** → `02b-mock-rig.luau` (stock R15 rig builder). 445 +
  232 + verify wiring; `02b` receives `(Mock, HumanoidClass, MockHelpers)` and assigns
  `CreateR15Character` onto the same table (`Game.__Mock`); the `02` factory return therefore
  gained `HumanoidClass` on top of the original exports (harness-internal, additive).
- **`src/03-env.luau` split** → `03b-env-simulation.luau` (globals installation, virtual clock,
  heartbeat pump, deferred queue, mock passthroughs, script introspection). 432 + 335 lines.
  The core chunk stashes `Env.__Context` (module registry, require stack, host-compiler
  getter); the simulation chunk consumes it. `Env.RecordLog` is exposed for its logger use.
- **`LuaTests/04-integration-suite.luau`** — the always-true assertion
  `lifecycle.stopHaltsUpdates` is now the real `Transform`-identity check (same technique as the
  teardown case); the dead `BeforeStoppedFrames` placeholder removed.
- **`LuaTests/*.luau` are documented-exempt from the 500-line cap** (only
  `04-integration-suite.luau` exceeds it, at 655): they are test specifications closing over
  stateful world-setup; splitting would duplicate fragile setup for zero behaviour gain.
  Framework stays 100% ≤ 500 (max: ConfigData.luau, 495). See `Tools/verify/README.md`.
- **Comment accuracy (framework, comment-only, no runtime change):** head look-at clamps
  pitch/yaw symmetrically to ±`Config.IkAngleLimitMax`; the `SetLookAtTarget` doc, the
  `ApplyLookAt` header and the `Config.LookAt` comment said `IkAngleLimitMin/Max` — corrected.
  The `IkAngleLimitMin` key is now documented as used only by IK world-direction limits.
- Gate after the work: **PASS 437 | FAIL 0** (was 433 on the previous branch tip), Compilation
  28/28, Analysis 0/0/40, `rojo-check.mjs` OK. Both tooling commits (`dd92f40`, `26881a5`)
  merged to `main` as `5109f27` via PR #7 (2026-11-06T06:38Z); CI green on the PR and on `main`.
- **`Tools/verify/changelog-check.mjs` (2026-11-06, 1.1.8)** — permanent parity gate between the two
  changelog copies; asserts no duplicate version headers, ascending order, non-empty sections,
  identical version sets and equal per-version entry counts (55/55). Wired into the CI gate and
  `npm run changelog-check`; negative cases verified (exit 1 with precise messages).

### Verification / tooling

- **Studio MCP is BLOCKED** in this environment; GitHub-vs-Studio parity is **BLOCKED**, not
  verified. All work is on the local clone. The AnimationConstraint blocker requires a playtest,
  which is prohibited without explicit authorization.
- **CI**: `.github/workflows/verify.yml` runs `verify.mjs` + `rojo-check.mjs` on push/PR to
  `main` and `arena/**` (node 22, `npm ci`). No secrets. The harness is the test signal.
- **`ProceduralAnimation.project.json` exists** (repo root, Rojo 7 format). It maps
  `ROJO_OHIO_MUMBAI/` onto the DataModel for placeId 139066482915692 via explicit tree keys;
  the two starter entries force `$className LocalScript` / `Script` (the `.local`/`.legacy`
  suffixes remain harness-only conventions). `node Tools/verify/rojo-check.mjs` statically
  verifies coverage, path existence and conventions. `rojo build` was never executed here —
  Rojo release assets are unreachable from this sandbox — so validate the build on a network
  that can reach GitHub releases before publishing.
- **R6 support:** not implemented (clip data is R15-only). Deferred.

---

## 8. Session start checklist

1. Read `Memory.md`, `GoodPractices.md`, `BadPractices.md`, `SyntaxReference.md`, `Changelog.md`.
2. `cd Tools/verify && node verify.mjs` — establish the real baseline.
   **Do not trust the numbers in this file; run it.**
3. `wc -l` every script; confirm the 500-line rule still holds.
4. Read the source of any module you intend to touch.
5. Check the API surface is still intact: `baseline/api.json` is never edited by hand.

## 9. Session end checklist

1. Re-run the full suite (`node verify.mjs`) and `node Tools/verify/rojo-check.mjs` if files moved.
2. Update this file with the new state and any new gotcha.
3. **Append** to `Shared/Changelog.luau` — never overwrite, never renumber historical entries.
4. Mirror the entry into `Documentation/Changelog.md` and bump `Config.Version` if releasing.
5. Re-read both, and follow `Maintenance.md` §8 for a release.
