# Changelog — Procedural Animation Framework

Append-only history. **Never rewrite, reorder or renumber a historical entry.**

The canonical machine-readable copy lives at
`ReplicatedStorage/ProceduralAnimation/Shared/Changelog.luau`, because runtime code reads
`Changelog.Entries` and `Changelog.Log`. This file is the human-readable mirror. When you add
an entry, add it in **both** places.

---


## 1.0.0

### Initial release: R15 procedural locomotion, jump state machine, additive gestures, two-bone IK and pose replication.

- **Affected:** `All files`
- **Reason:** Requested baseline framework.

### Chest joint treated as optional instead of aborting setup.

- **Affected:** `AnimationConfig, ProceduralAnimator`
- **Reason:** Stock R15 rigs do not ship a Chest Motor6D. Aborting on its absence would make the framework unusable on real avatars; a warning is logged once instead.

### Pose state stored in buffer objects rather than Lua tables.

- **Affected:** `ProceduralAnimator, AnimationNetwork`
- **Reason:** Buffers are fixed size from creation, so the render loop performs zero allocations and zero rehashes.

### Joint rotations are quantised as three 16-bit Euler angles per joint.

- **Affected:** `AnimationNetwork`
- **Reason:** Six bytes per joint keeps a 16-joint packet at 116 bytes, well under the 900 byte unreliable limit, and decoding is branch-free.

### Remote poses are interpolated between the two most recent packets using a configurable jitter buffer delay.

- **Affected:** `AnimationNetwork`
- **Reason:** Render time is shifted back by JitterBufferDepth so a late packet does not produce a snap.

### SlerpCFrame normalises a lerped quaternion instead of slerping when the dot product exceeds 0.9995.

- **Affected:** `AnimationMath`
- **Reason:** slerp divides by sin(theta), which loses precision as theta approaches zero.

### Jump driven by Humanoid.StateChanged plus a FloorMaterial poll.

- **Affected:** `ProceduralAnimator`
- **Reason:** StateChanged alone misses landings triggered by physics (falling off a ledge); the poll is a cheap fallback.

### Ankle alignment uses an axis-angle correction applied through Motor6D.Transform.

- **Affected:** `ProceduralAnimator`
- **Reason:** Convert the world-space foot-to-normal rotation into joint space so all motion still flows through Transform as required.

### Preview mode anchors only HumanoidRootPart and zeroes scripted root offset.

- **Affected:** `ProceduralAnimator`
- **Reason:** Lets the rig be inspected without locomotion drift while every limb stays physically unanchored.

### Remotes and the bindable bus live in a runtime-created Remotes folder.

- **Affected:** `AnimationNetwork`
- **Reason:** The authored layout stays exactly Shared/Client; runtime network objects are grouped separately.

### Zero-weight clips and joints are skipped before any buffer work.

- **Affected:** `ProceduralAnimator`
- **Reason:** A standing character never pays for run sampling or for joints the current pose does not touch.

## 1.0.1

### Phase 0: verified inventory, acyclic require graph and 25 MathLib exports; pre-change snapshot saved to ServerStorage.ZeroScript.BackupsPhase0.

- **Affected:** `(no source change)`
- **Reason:** Establish a verified baseline and a rollback point before any runtime edits.

### Phase 1: AnimationMath split verified complete; FABRIK and waves are top-level and every referenced export resolves.

- **Affected:** `(no source change)`
- **Reason:** Phase 1 had already been completed earlier; re-verified instead of being redone.

### Added the missing local Players service reference.

- **Affected:** `AnimationNetwork`
- **Reason:** ConnectServer called PlayersGetPlayers(Players) with an undefined global, passing nil as self and crashing server Network.Init on startup.

### Forward-declared ApplyWorldDirection above UpdateFabrikChain.

- **Affected:** `ProceduralAnimator`
- **Reason:** The FABRIK call site appeared before the local declaration, so it resolved to a nil global.

### Pose packets are rejected when the buffer is shorter than JointDataOffset + JointCount * BytesPerJoint.

- **Affected:** `AnimationNetwork, AnimationNetworkReceive`
- **Reason:** A truncated packet with a plausible JointCount made the decoders read past the end of the buffer. Packet layout is unchanged.

### Animator.Stop disconnects and clears the Heartbeat connection.

- **Affected:** `ProceduralAnimator`
- **Reason:** Stop only cleared a flag and left the connection alive across Stop/Start cycles.

### Config.RequireOptionalJoints now controls whether optional joints are mandatory.

- **Affected:** `ProceduralAnimator`
- **Reason:** The flag existed but was never read, so the optional-joint policy was effectively hardcoded.

### Wave presets compile in sorted order (Config.Compiled.WaveOrder), and UpdateWaves iterates that order.

- **Affected:** `AnimationConfigCompile, ProceduralAnimator`
- **Reason:** pairs() order is unspecified; a fixed order keeps additive wave results reproducible.

## 1.0.2

### Split ProceduralAnimator (1407 lines) into eight modules; every script is now under the 500-line limit.

- **Affected:** `ProceduralAnimator, ClientPosePipeline, ClientRigKinematics, CharacterLifecycle, CharacterMotionState, CharacterJoints, StatePool, PoseBuffer`
- **Reason:** Phase 3 architectural reorganization. The animator now holds only the heartbeat, the public API and init wiring (448 lines). Bodies were relocated unchanged; the extraction targets were chosen so each module owns one concern and none requires the animator back.

### Added PoseBuffer as a leaf module owning the 12-byte-per-joint stride and the additive/blend writers.

- **Affected:** `PoseBuffer`
- **Reason:** Both the pose pipeline and the kinematics module write the pose buffer. Giving them a shared leaf module avoids a ClientPosePipeline <-> ClientRigKinematics require cycle.

### Added StatePool, and replaced the captured ActiveStateCount with a live read.

- **Affected:** `StatePool, ProceduralAnimator, CharacterLifecycle`
- **Reason:** The character registry was duplicated across the split. Capturing StatePool.Count into a local froze it at 0, silently disabling SetPreviewMode and SetLocomotionWeight; it is now read through a getter.

### Live flags are injected as getters rather than values (IsPreviewMode).

- **Affected:** `ProceduralAnimator, ClientPosePipeline, CharacterLifecycle`
- **Reason:** SetPreviewMode mutates a local owned by the animator. Passing the value copied it at construction, so the extracted modules never saw an update.

### Added the offline verification harness with six suites and a public-API baseline.

- **Affected:** `Tools/verify/*`
- **Reason:** Play mode is not permitted, so correctness is established by a real Luau VM with mocked Roblox types. The api suite compares the exported surface structurally against baseline/api.json (136 exports), so refactors can be proven non-breaking rather than asserted.

### The API surface comparison describes arrays by element shape instead of by index.

- **Affected:** `Tools/verify/LuaTests/06-api-suite.luau`
- **Reason:** Appending a Changelog entry changed the fingerprint of Changelog.Entries and was reported as an API break. Appending a record is not a contract change; losing or reshaping the record type is, and that is still caught.

## 1.0.3

### Reorganized into the target folder hierarchy: Client/Runtime, Shared/Config/{Data,Compile}, Shared/Math/{Core,Curves,IK,Waves}, Shared/Networking/{Constants,Receive}.

- **Affected:** `ProceduralAnimation (tree), AnimationConfig, AnimationMath, AnimationNetwork, ProceduralAnimator, PoseBuffer, NetworkConstants, NetworkReceive, ConfigCompile, client bootstrapper`
- **Reason:** Phase 3 hierarchy. Modules were relocated with git mv so history is preserved, and only require() paths changed; no algorithm was touched. Client/Bootstrap and Server/ were deliberately not created because the bootstrappers must stay in StarterPlayerScripts and ServerScriptService to execute at all, and empty folders are prohibited.

### Created Documentation/ with Memory, GoodPractices, BadPractices, SyntaxReference and Changelog.

- **Affected:** `Documentation/*`
- **Reason:** Priority 3 requires these before any coding session. They are derived from the actual source, not generated boilerplate; two SyntaxReference claims (buffer # length, math.round) were empirically corrected after testing them in the harness VM.

## 1.0.4

### Added Shared/Utilities/Connections and a real Destroy/Shutdown lifecycle to the client runtime, the network layer and both bootstrappers.

- **Affected:** `Utilities/Connections, ProceduralAnimator, PlayerTracker, AnimationNetwork, ProceduralAnimationClient, ProceduralAnimationServer`
- **Reason:** Phase 4. Animator.Init never stored its Players connections and TrackPlayer never stored its per-player connections, so nothing could ever be disconnected; there was no Destroy at all on either side. Connections are now recorded in trackers and released by Destroy/Shutdown, which are idempotent and terminal.

### Extracted PlayerTracker from ProceduralAnimator.

- **Affected:** `PlayerTracker`
- **Reason:** Keeps the animator under 500 lines after the lifecycle work, and puts every player-level connection decision in one auditable file.

### Verification harness: Suite.Reset was declared but never invoked; ResetModuleCache dropped modules without running their teardown; script lifecycle handles were discarded.

- **Affected:** `Tools/verify/src/00-runner.luau, src/03-env.luau, src/02-mock-services.luau`
- **Reason:** Three harness defects that made lifecycle tests unreliable. Suites silently ran against the previous suite's world, and connections leaked across suites. ResetModuleCache now runs each cached module's Destroy/Shutdown first, and RunScriptFile retains returned handles so teardown can release them.

### Type checker enabled: `roblox-definitions.luau` written, analysis now on by default.

- **Affected:** `Tools/verify/roblox-definitions.luau (new), Tools/verify/verify.mjs`
- **Reason:** Phase 3's last exit item. Without the definition file every Roblox global was reported as an unknown global; those were reclassified as "definition gaps" and filtered out of the failures, so analysis looked green while checking almost nothing. A missing or rejected definition file is now a hard failure. Diagnostics went 127 (1 error / 42 warnings / 84 gaps) → 0.

---

### Fixed an uninitialised `ApplyWorldDirection` upvalue and an undefined `UpperTorso` in the test mock.

- **Affected:** `ClientRigKinematics, Tools/verify/src/02-mock-services.luau, Tools/verify/LuaTests/04-integration-suite.luau`
- **Reason:** Found by the newly enabled checker. `local function ApplyWorldDirection` after `local ApplyWorldDirection` shadows the forward declaration instead of assigning it, so the FABRIK spine chain called `nil` every frame on any rig with a Chest joint. The mock bug — `Neck.Part0`/`Waist.Part1`/`Chest.Part1` wired from an undefined global — made the rig structurally invalid and hid that path from every existing test. A new `setup.withChest` case now covers it.

---

### Fixed a nil `MathLib` on the jump path and a bare `ReleaseRemotePose` call in shutdown.

- **Affected:** `CharacterMotionState, ClientPosePipeline, AnimationNetwork`
- **Reason:** Both found by the checker. `MathLib` was never passed to `CharacterMotionState`, so `UpdateJump` threw on every jump. `ReleaseRemotePose` lives on `Network`, so the shutdown loop called `nil`; it was masked only because the harness's server player list is empty at shutdown. Two vacuous jump tests were also fixed: they called `Humanoid.SetState` with a dot, leaving `NewState` nil so no `StateChanged` ever fired.

---

### Removed 36 dead locals from the Phase 3 split; annotated `QuaternionFromCFrame`'s return contract.

- **Affected:** `ProceduralAnimator, ClientPosePipeline, CharacterMotionState, ClientRigKinematics, CharacterLifecycle, AnimationNetwork, ConfigData, MathCore`
- **Reason:** Lint warnings from the enabled checker: re-bound pipeline thunks and constants nothing called, a self-assignment (`local Enum = Enum`), duplicate shadowing `Locomotion` pairs, unused service locals. The return annotation removes the last type error — the checker infers an unannotated parameter as `unknown` rather than `any`, poisoning the `Dot` product fed to `Acos(Clamp(...))`. Behaviour unchanged; packet layout and public API untouched.


---

## 1.0.6

### Extracted the bootstrap lifecycle logic out of the StarterPlayer/ServerScriptService scripts into ModuleScripts that return lifecycle handles.

- **Affected:** `Client/Bootstrap/ClientBootstrap, Server/Bootstrap/ServerBootstrap, ProceduralAnimationClient, ProceduralAnimationServer`
- **Reason:** Scripts may not return values, and the verification harness and embedders need a real ModuleScript return for the destroy path. The starter scripts are now thin require wrappers; all lifecycle logic type-checks as a module and exposes `Destroy()`.

### Migrated every script in the repository to `--!strict`.

- **Affected:** `All files`
- **Reason:** Phase 6. All 28 scripts declare `--!strict` as their first line; analysis reports 0 errors and 0 warnings (40 pre-existing definition gaps at engine boundaries remain, documented). Script-may-not-return-values is exactly what forced the bootstrap extraction. No behaviour change intended; all suites and the API baseline remain green.

### Harness: bootstrap and lifecycle suites retargeted to the two extracted Bootstrap modules.

- **Affected:** `Tools/verify/LuaTests/05-bootstrap-suite.luau, Tools/verify/LuaTests/07-lifecycle-suite.luau`
- **Reason:** Source assertions pointed at the starter scripts, which no longer contain the lifecycle code. Assertions now read `ClientBootstrap.luau` / `ServerBootstrap.luau` by RojoPath.

---

## 1.0.7

### StatePool.Compact early-outs when no removals are pending, via a PendingRemovals counter incremented by Remove.

- **Affected:** `StatePool`
- **Reason:** Phase 7. Steady-state frames paid an O(n) scan to compact nothing. Measured ~1021 ns → ~67 ns per Compact call on a full 16-state pool; Remove remains correct and the Destroy Remove-then-Clear path resets the counter.

### ApplyPose root-joint write fast path: pure CFrameAngles when the vertical offset is below 0.0002.

- **Affected:** `ClientPosePipeline`
- **Reason:** Phase 7. Avoids composing `CFrame.new(0, y, 0) * angles` every frame for rigs with no vertical root motion. (Side effect: made explicit that `Motor6D.Transform` honours translation, contradicting the docs' earlier rotation-only claim; SyntaxReference §4 was corrected.)

### FABRIK per-chain TargetScratch tables; FootRayDirection cached at state creation.

- **Affected:** `ClientRigKinematics, CharacterLifecycle`
- **Reason:** Phase 7. Two per-frame allocations removed from the hot loop. TargetScratch is created in the chain init; FootRayDirection caches the constant (0, -FootRayLength, 0) once per character.

### Added Tools/verify/bench.mjs — a machine-dependent comparative micro-benchmark.

- **Affected:** `Tools/verify/bench.mjs`
- **Reason:** Phase 7. Numbers recorded in Memory.md; same-machine comparison only; proves nothing about runtime behaviour on a live rig.

---

## 1.1.0

### Horizontal speed low-pass: the locomotion blend now uses an exponentially filtered speed.

- **Affected:** `ConfigData, ClientPosePipeline, CharacterLifecycle`
- **Reason:** `AssemblyLinearVelocity` jitters frame to frame, shimmering the idle/walk/run blend. `Config.VelocityFilterRate` (default 12.0/s) smooths it; `0` disables the filter (previous behaviour). Filtered value persisted on `State.FilteredSpeed`. New top-level config key; no existing config changed.

### Spline arc-length lookup tables with constant-speed sampling.

- **Affected:** `MathCurves, AnimationMath`
- **Reason:** Keyframe animation needs constant-speed playback; equal time offsets over a non-uniform curve are not constant-speed. `CompileSpline` precomputes 64 chord segments along the (Time, Value) graph for all compile paths; new exports `MathLib.GetSplineLength` and `MathLib.SampleSplineAtDistance` (binary search, allocation-free). Empty/single-key splines report zero length safely.

### Configurable damped springs (`MathLib.StepSpring`).

- **Affected:** `MathCore, AnimationMath`
- **Reason:** Springs drive the new squash & stretch and are available for consumer secondary motion. Semi-implicit Euler, stable for the shipped stiffness range at frame rates down to ~15 Hz; the one runtime caller clamps dt to 0.0667 s. Caller-owned state mutated in place — zero allocation.

### Squash & stretch: landings kick a damped spring on the root vertical offset.

- **Affected:** `CharacterMotionState, ClientPosePipeline, CharacterLifecycle, ConfigData`
- **Reason:** Landings read as weighty. Impulse is fall-speed scaled (clamped 0.5–2.0×) and applied on the `FloorMaterial` landing poll, integrated in `ComputeRootOffset`. `Config.SquashStretch = { Enabled = true, Strength = 2.4, Stiffness = 170.0, Damping = 14.0 }`; disable to opt out. Rides the same root-offset path as the locomotion bob; no new pose write path.

### Head look-at: `Animator.SetLookAtTarget(TargetPosition?, Weight?)` aims the Neck joint.

- **Affected:** `ProceduralAnimator, ClientRigKinematics (ApplyLookAt), ClientPosePipeline, CharacterLifecycle, ConfigData`
- **Reason:** Gaze-at-target is common avatar behaviour. Implemented as an additive yaw/pitch blend into the existing pose buffer, applied after IK and before ApplyPose, measured in the root part's frame (body-relative). `Config.LookAt = { Smoothing = 8.0 }` exponential approach; angle limits reuse `Config.IkAngleLimitMin/Max`. Pass `nil` to fade the aim out — no pops. Default weight 0; unused cost is one table read and an `Exp()` per frame.

### Per-joint amplitude control: `Animator.SetJointAmplitude(JointIndexValue, Scale)`.

- **Affected:** `ProceduralAnimator, ClientPosePipeline, CharacterLifecycle`
- **Reason:** Scale any channel's desired angles (0 freezes influence, 1 neutral, 3 clamp) on top of clips, IK, waves, FABRIK and look-at alike — it applies at the pose buffer before smoothing. Preallocated 16-slot table; one read + compare per joint per frame when unset.

### Version bump to 1.1.0: new top-level config keys only; packet layout and all pre-existing exports unchanged.

- **Affected:** `ConfigData, Documentation/Changelog.md, Shared/Changelog.luau`
- **Reason:** Minor release for Phase 8. The frozen API baseline (`Tools/verify/baseline/api.json`) permits added exports; nothing existing changed shape. 1.0.6/1.0.7 are changelog-only phases (no runtime Version bump).


---

## 1.1.1

### Added `ProceduralAnimation.project.json` (Rojo 7 build) and `Tools/verify/rojo-check.mjs`; `.gitignore` covers build artifacts.

- **Affected:** `ProceduralAnimation.project.json (new), Tools/verify/rojo-check.mjs (new), .gitignore, Documentation/Memory.md, Maintenance.md, Audit.md`
- **Reason:** Closes audit item O3. The project file maps `ROJO_OHIO_MUMBAI/` onto the DataModel for placeId `139066482915692`; the two harness-suffixed starter entries force `$className LocalScript` / `Script` via tree keys, so the `.local`/`.legacy` harness conventions stay untouched. `rojo-check.mjs` statically enforces path existence, full coverage of the source tree, repository containment and the harness conventions (28/28 files mapped; negative cases verified). `rojo build` itself was not executed in this sandbox (Rojo release assets redirect to object storage the sandbox cannot reach); validate the build on a network that reaches GitHub releases before publishing. Framework code unchanged; `Config.Version` stays `1.1.0`.

---

## 1.1.2

### Docs accuracy pass and CI: corrected examples, harness README, GitHub Actions gate.

- **Affected:** `Documentation/GoodPractices.md, Documentation/BadPractices.md, Tools/verify/README.md (new), .github/workflows/verify.yml (new), Documentation/Maintenance.md, Documentation/Memory.md`
- **Reason:** Keep the documentation as rigorous as the code after Phases 6–10 and the project-file work. GoodPractices: the `Compact` example now shows the Phase 7 `PendingRemovals` early-out and the PoseBuffer require path is correct; BadPractices: the config example cites keys that exist (`Locomotion.BlendRate`, `IkBlendRate`) and the "exports preserved" claim no longer cites a stale count. CI runs the same gate we run locally (`npm ci` + `verify.mjs` + `rojo-check.mjs`) on push/PR to `main` and `arena/**` so a regression cannot merge quietly. No framework code changed; `Config.Version` stays `1.1.0`.

---

## 1.1.3

### `bench.mjs` extended: `GetSplineLength`, `SampleSplineAtDistance`, `StepSpring` measured.

- **Affected:** `Tools/verify/bench.mjs, Documentation/Memory.md`
- **Reason:** Phase 8 added public hot-path math without benchmark coverage (number inconsistency found during the docs-accuracy pass). `SampleSplineAtDistance` ≈ 1787 ns/op (~2.8× `SampleSpline` — the price of constant-speed sampling), `GetSplineLength` 136 ns/op (pure field read), `StepSpring` ≈ 373 ns/op. Machine-dependent, comparative only. Framework code unchanged; `Config.Version` stays `1.1.0`.

---

## 1.1.4

### Harness hardening: `--!strict` everywhere, 500-line compliance for the harness, look-at docs corrected, one fake assertion replaced by the real check.

- **Affected:** Tools/verify/src/01-mock-value-types.luau, Tools/verify/src/01b-mock-containers.luau (new), Tools/verify/src/02-mock-services.luau, Tools/verify/src/02b-mock-rig.luau (new), Tools/verify/src/03-env.luau, Tools/verify/src/03b-env-simulation.luau (new), Tools/verify/src/00-runner.luau, Tools/verify/src/04-testkit.luau, Tools/verify/roblox-definitions.luau, Tools/verify/LuaTests/*.luau, Tools/verify/verify.mjs, Tools/verify/README.md, Tools/verify/LuaTests/04-integration-suite.luau, ProceduralAnimator.luau, ClientRigKinematics.luau, ConfigData.luau (comment-only), Documentation/Memory.md
- **Reason:** The 500-line and strict-typing rules were enforced only on the framework; the verification harness (tooling, never ships into the place) violated both (four chunks > 500 lines, 13 files without --!strict). The mock chunks are split by responsibility and combined by verify.mjs through shared table handles so identity of mock classes is preserved; LuaTests specs are documented-exempt from the 500-line cap (they close over stateful world-setup). The integration suite's always-true 'lifecycle.stopHaltsUpdates' assertion is now the real Transform-identity check. Framework comment blocks said the head look-at clamps to IkAngleLimitMin/Max; it does not (symmetric +/-IkAngleLimitMax) - comments corrected, no runtime change; IkAngleLimitMin is now documented as used only by IK world-direction limits. Also fixes two previously unreleased nits: 02-mock-services return now exposes HumanoidClass for the rig chunk, and verify.mjs compile-checks all harness src chunks (04-testkit.luau was never compiled). No framework behaviour changed, public API frozen, Config.Version stays 1.1.0. Gate: PASS 437 | FAIL 0.

---

## 1.1.5

### Documentation consistency sweep after the harness split: living docs synced; historical records untouched.

- **Affected:** `Documentation/Audit.md (appended addendum only), Documentation/Maintenance.md, Documentation/Memory.md, ROJO_OHIO_MUMBAI/ServerStorage/ZeroScript/Memory.luau`
- **Reason:** After the 1.1.4 split the living docs still cited pre-split paths and the pre-split gate count. Audit.md's "Current gate" block and all historical changelog entries are append-only and were left byte-identical; the addendum records the post-split state (PASS 437 | FAIL 0). Maintenance.md now expects 437 and points at the harness's own rule note; Memory.md flags that the `UpperTorso` fix lives in `02b-mock-rig.luau`. No framework or harness code changed; the gate is unchanged; `Config.Version` stays `1.1.0`.

---

## Entry format

```
{
    Version = "1.0.5",
    Description = "One line. What changed.",
    File = "Module, Module",
    Reason = "Why it was necessary. What was broken or missing.",
}
```

Bump the patch number for fixes, the minor number for new framework features.
