# Public API Reference — Procedural Animation Framework (v1.1.0)

The frozen inventory is `Tools/verify/baseline/api.json` (138 exports / 6 modules) plus the
Phase 8 additions marked **NEW 1.1.0** below. Removing, renaming or changing the shape of any
baseline export fails the api suite; additions are reported, not failed. See
`Documentation/Maintenance.md` §3–4 for the change procedure.

Types at the engine boundary (`Vector3`, `CFrame`, `Motor6D`, player models, ...) are typed
`any` by design; the harness checks names and arity, not Roblox object contracts.

---

## 1. `ProceduralAnimator` — the runtime entry point (16 exports)

Acquire it with `require(...Client.Runtime.ProceduralAnimator)`.

| Export | Signature | What it does |
|---|---|---|
| `Init` | `Init(): ()` | Idempotent startup: sets up Players tracking and the replication listeners. Refuses after `Destroy()`. |
| `IsRunning` | `IsRunning(): boolean` | `true` while the heartbeat loop is connected. |
| `Start` | `Start(): ()` | Reconnects the Heartbeat loop; safe to call when running. |
| `Stop` | `Stop(): ()` | Disconnects the Heartbeat loop; idempotent. |
| `SetupCharacter` | `SetupCharacter(Character: any): any` | Validates the rig (R15, Motor6Ds cached, Animate removed), creates pooled state, returns the state table or `nil` on failure. |
| `TeardownCharacter` | `TeardownCharacter(Character: any): any` | Releases every connection and per-character buffer for the character; idempotent; `true` on first teardown. |
| `SetLocomotionWeight` | `SetLocomotionWeight(Weight: number): ()` | Scales the whole pose output 0..1 (clamped) on every active character. |
| `SetIkTarget` | `SetIkTarget(Limb: string, WorldPosition: any, Weight: number): ()` | `Limb` is `"LeftHand"` or `"RightHand"`; engages/releases two-bone arm IK toward `WorldPosition`. Weight 0 releases. |
| `PlayGesture` | `PlayGesture(GestureId: string, Duration: number?, EasingId: number?): ()` | Fades an additive gesture clip in, holds, fades out. `GestureId` comes from `Config.Gestures`. |
| `StopGesture` | `StopGesture(GestureId: string): ()` | Fades a playing gesture out early. |
| `SetEasingOverride` | `SetEasingOverride(JointIndexValue: number, EasingId: number): ()` | Per-joint easing override (1..16 joints, valid `EasingId`); out-of-range is ignored. |
| `SetJointAmplitude` | **NEW 1.1.0** `SetJointAmplitude(JointIndexValue: number, Scale: number): ()` | Scales one joint's pose-buffer angles 0..3 (clamped; 1 is neutral, 0 silences the joint's channels). Affects clips, IK, waves, FABRIK and look-at. |
| `SetLookAtTarget` | **NEW 1.1.0** `SetLookAtTarget(TargetPosition: any, Weight: number?): ()` | Aims the Neck joint at a world-space point in the root's frame; smooth exponential approach (`Config.LookAt.Smoothing`); `nil` fades the aim out; `Weight` defaults to 1. |
| `SetPreviewMode` | `SetPreviewMode(Enabled: boolean): ()` | Anchors the local root part and zeroes the root offset so poses can be inspected without physics. |
| `BindToEvent` | `BindToEvent(EventName: string, Callback: (any) -> ()): ()` | Subscribes to bus events by `Config.EventId` key: `Setup`, `ClipStart`, `ClipStop`, `Landing`, `GestureStart`. Unknown names are rejected with a log and do nothing. |
| `Destroy` | `Destroy(): ()` | Disconnects heartbeat/players/trackers, releases every state; idempotent and terminal. |

## 2. `AnimationMath` — pure maths, no Roblox objects required at the boundary (28 exports)

| Export | Signature | What it does |
|---|---|---|
| `Pi` / `TwoPi` | `number` | Constants. |
| `Ease` | `Ease(EasingId: number, Alpha: number): number` | 30 named easings; `EasingId` indexes `Config.EasingFunctions` (1..`EasingCount`). |
| `EasingFunctions` | table | The easing lookup backing `Ease` (id → function). |
| `EasingCount` | `number` | Number of registered easings. |
| `Clamp01` | `Clamp01(Value: number): number` | Clamp to [0, 1]. |
| `SmoothFactor` | `SmoothFactor(Rate: number, DeltaTime: number): number` | `1 - exp(-Rate*dt)`; frame-rate independent exponential smoothing factor. |
| `ShortestAngle` | `ShortestAngle(From: number, To: number): number` | Wraps the signed delta to (-π, π]. |
| `LerpNumber` | `LerpNumber(From: number, To: number, Alpha: number): number` | Linear interpolation. |
| `LerpVector3` | `LerpVector3(From: any, To: any, Alpha: number): any` | Component-wise vector lerp. |
| `SlerpCFrame` | `SlerpCFrame(From: any, To: any, Alpha: number): any` | Quaternion slerp (+position); normalised-lerp fallback above `dot > 0.9995`. |
| `LerpCFrame` | `LerpCFrame(From: any, To: any, Alpha: number): any` | CFrame lerp. |
| `BezierQuadratic` / `BezierCubic` | `(P0: number, P1: number, P2(: number), Alpha: number): number` | De Casteljau evaluation. |
| `BezierQuadraticDerivative` / `BezierCubicDerivative` | as above | First derivatives. |
| `RegisterBezierCurve` | `RegisterBezierCurve(Kind: number, P0: number, P1: number, P2: number?, P3: number?): number` | Registers a named bezier sampler; returns the sampler id (feeding `Config.EasingId`-style lookups). |
| `GetSamplerCount` | `GetSamplerCount(): number` | Number of registered bezier samplers. |
| `CompileSpline` | `CompileSpline(Kind: string, Times: { number }, Values: { number }): any` | Compiles knots to segment coefficients (`"Natural"` cubic or Catmull-Rom), **plus compile-time arc-length tables**. Empty/single-key input is valid. |
| `SampleSpline` | `SampleSpline(Spline: any, Time: number): number` | Allocation-free evaluation with time clamping. |
| `GetSplineLength` | **NEW 1.1.0** `GetSplineLength(Spline: any): number` | Total arc length of the compiled (Time, Value) graph; `0` for degenerate splines. |
| `SampleSplineAtDistance` | **NEW 1.1.0** `SampleSplineAtDistance(Spline: any, Distance: number): number` | Constant-speed sampling: finds the parameter at `Distance` along the curve (binary search over a 64-chord table). Clamped to the curve ends. |
| `StepSpring` | **NEW 1.1.0** `StepSpring(State: any, Target: number, Stiffness: number, Damping: number, DeltaTime: number): number` | Damped oscillator, semi-implicit Euler; `State = { Position, Velocity }` mutated in place; zero allocation; caller clamps dt (the runtime clamps to 0.0667 s). |
| `CompileWave` | `CompileWave(Wave: any): any` | Compiles a harmonic description into a zero-allocation sampler. |
| `SampleWave` | `SampleWave(Wave: any, Time: number): number` | Non-compiled harmonic sampling. |
| `SampleCompiledWave` | `SampleCompiledWave(Compiled: any, Time: number): number` | The hot-path wave sampler. |
| `Noise1D` | `Noise1D(X: number): number` | Deterministic 1D value noise (`[-1, 1]`). |
| `SolveFabrik` | `SolveFabrik(ChainPositions: { any }, Lengths: { number }, TargetPosition: any, Tolerance: number, MaxIterations: number): ()` | FABRIK multi-bone IK; positions mutated in place. |

## 3. `AnimationNetwork` — replication (12 exports)

Server: `Init()` creates the `UnreliableRemoteEvent`s under `ProceduralAnimation/Remotes`;
`IsReady()`/`Shutdown()` gate and dispose everything; `RegisterPlayer`/`UnregisterPlayer`
manage the relay registry; `FireBus(EventId, Value)` broadcasts bus events;
`SendPose(...)`/`SendEvent(...)` encode into the frozen packet (see §6). `Shutdown()` is
idempotent and terminal — connections are released and the registry cleared.

Client: `BindLocal(EventId, Callback)` subscribes to bus events;
`SampleRemotePose(Player, PoseBuffer)` decodes the next jitter-buffered packet into a pose
buffer (time-shifted by `Config.JitterBufferDepth`); `HasRemotePose(Player)` tests for arrival;
`ReleaseRemotePose(Player)` drops a player's buffer.

## 4. `AnimationConfig` — compiled constants only (37 exports)

Read-only tables. The most important groups:

- **Joints**: `JointIndex`, `JointNames`, `JointAliases`, `LegJointIndex`, `ArmJointIndex` —
  R15 joint id ↔ name mapping (+ Chest optional via `OptionalJoints` / `RequireOptionalJoints`).
- **Packet**: `Packet`, `SendRate`, `JitterBufferDepth`, `MaxJoints` (=16).
- **Locomotion/jump**: `Locomotion`, `Jump`, `Gestures`, `MaxGestures`.
- **IK**: `IkAngleLimitMin`, `IkAngleLimitMax`, `IkReachClamp`, `IkBlendRate`,
  `FootRayHeight`, `FootRayLength`, `FootAlignWeight`, `LodIkDistance`, `LodDistance`.
- **Waves/FABRIK**: `Waves`, `FabrikChains`.
- **Events**: `EventId`, `MaxEventId`.
- **Compiled output**: `Compiled` (clips/waves/smoothed data), `Clips`, `EasingId`.
- **Misc**: `Version` (currently `"1.1.0"`), `LocalSmoothRate`, `RemoteSmoothRate`,
  `SanityRootThreshold`, `PreviewAnchorRoot`, `ProfilingEnabled`, `MaxGestures`,
  `FootRayLength`.
- **NEW 1.1.0 top-level keys** (new additions, not part of any frozen sub-table):
  `VelocityFilterRate` (horizontal-speed low-pass; `0` disables),
  `SquashStretch` (`{ Enabled, Strength, Stiffness, Damping }` — landing spring on the root
  vertical offset), `LookAt` (`{ Smoothing }` for `SetLookAtTarget`).

## 5. `NetworkConstants` — the frozen wire layout in code (46 exports)

Grouped: buffer helper aliases (`Abs`-style thin wrappers used by the decoder — `BufferLen`, `BufferCreate`, `BufferCopy`, `BufferReadU8`, `BufferReadU16`, `BufferReadU32`, `BufferReadI16`, `BufferReadF32`, `BufferWriteU8`, `BufferWriteU16`, `BufferWriteU32`, `BufferWriteI16`, `BufferWriteF32`, `ReadClampedI16`, `WriteClampedI16`), layout offsets (`HeaderOffset`, `SequenceOffset`, `TickOffset`,
`RootPositionOffset`, `RootVelocityOffset`, `JointCountOffset`, `JointDataOffset`,
`BytesPerJoint`=6, `PoseFloatLength`, `SendBufferSize`=116, `SequenceModulus`), quantization
(`PositionScale`, `PositionInverse`, `VelocityScale`, `AngleQuantization`,
`AngleDequantization`, `MaxAngleRadians`, `ReadClampedI16`, `WriteClampedI16`), environment
detection (`IsClient`, `IsServer`), instance aliases (`InstanceNew`, `Vector3New`,
`PlayersGetPlayers`, `TypeOf`), math aliases (`Abs`, `Sqrt`, `Clamp`, `Floor`, `Clock`),
`MaxJoints`, `PacketPose`, `PacketEvent`.

**Changing any of these is a breaking protocol change** — see Maintenance.md §6.

## 6. `Changelog` — append-only history in-module (4 exports)

`Entries` (array of `{ Version, Description, File, Reason }`), `RuntimeLog` (capped at 64),
`RuntimeLogCount`, `Log(Message)` — warns and appends to the runtime log. Never rewrite,
reorder or renumber entries.

---

### Compatibility contract

- Baseline exports: no removal, rename, narrowing, or shape change — ever, without a major
  version bump and explicit protocol review.
- Additions: allowed at any minor bump; they must not alter the meaning of existing exports.
- Packet: frozen until an explicitly authorized protocol revision.
- Behaviour changes made for correctness are documented in `Changelog.luau` with the reason —
  additive entries, never renumbered history.
