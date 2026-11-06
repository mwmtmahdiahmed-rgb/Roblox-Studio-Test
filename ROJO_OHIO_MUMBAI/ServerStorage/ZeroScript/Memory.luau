return [==[
# Project memory
## Overview
Slop Game (placeId 139066482915692). Procedural animation framework for R15 avatars: locomotion (idle/walk/run), jump state machine, additive gestures, two-bone IK, FABRIK chains, wave-driven secondary motion, and networked pose replication via UnreliableRemoteEvent. All motion through Motor6D.Transform; Humanoid stays in charge of physics.

## Where things live
- ReplicatedStorage.ProceduralAnimation.Shared — all shared modules (Config, Math, Network, Changelog)
- ReplicatedStorage.ProceduralAnimation.Client.ProceduralAnimator — client runtime entry point, public API, heartbeat, state wiring (448 lines)
- ReplicatedStorage.ProceduralAnimation.Client.ClientPosePipeline — per-frame pose pipeline: clip sampling, overlay blending, pose application, locomotive weight blending, remote send pacing (430 lines)
- ReplicatedStorage.ProceduralAnimation.Client.ClientRigKinematics — FABRIK chains, waves, two-bone solver, ApplyWorldDirection, foot/hand IK (378 lines)
- ReplicatedStorage.ProceduralAnimation.Client.CharacterLifecycle — CreateState / SetupCharacter / TeardownCharacter, joint validation, connection ownership (266 lines)
- ReplicatedStorage.ProceduralAnimation.Client.CharacterMotionState — jump state machine + gesture playback (152 lines)
- ReplicatedStorage.ProceduralAnimation.Client.CharacterJoints — Motor6D discovery, joint caching, limb-length measurement (141 lines)
- ReplicatedStorage.ProceduralAnimation.Client.StatePool — shared character registry (map + dense active list + swap-removal compaction) (63 lines)
- ReplicatedStorage.ProceduralAnimation.Client.PoseBuffer — leaf module: 12-byte-per-joint stride, WritePoseAdd / WritePoseBlend (43 lines)
- ServerScriptService.ProceduralAnimationServer — server bootstrap (42 lines)
- ServerStorage.ZeroScript.BackupsPhaseA — Phase A backups (StringValue snapshots)
- ServerStorage.ZeroScript.Memory — this file

- StarterPlayer.StarterPlayerScripts.ProceduralAnimationClient — client bootstrapper (30 lines): Animator.Init(), then CharacterAdded/CharacterRemoving wiring
- ServerStorage.ZeroScript.BackupsPhase0 — Phase 0 source snapshot (15 StringValues of pre-Phase-0 source)

## Conventions
- PascalCase for all identifiers (locals, functions, fields)
- Factory pattern: sub-modules return a function(MathLib, Private) that populates the aggregator table
- Aggregator pattern: AnimationMath and AnimationConfig are thin loaders; real code lives in sub-modules
- Integer-indexed joint lookups (Config.JointIndex); no string keys in hot paths
- Buffer-based pose storage (buffer.create, buffer.readf32/writef32); zero allocation per frame
- Require graph is acyclic: Math sub-modules require nothing; Config.Compile requires Math; Network requires Config + Math

## Key systems
- AnimationMath: 4 sub-modules (Core 458L, Curves 242L, Ik 109L, Waves 120L) — easing, lerping, slerp, bezier, splines, FABRIK, waves/noise
- AnimationConfig: 3 sub-modules (Data 473L, Motion 119L, Compile 95L) — constants, clip authoring, wave/FABRIK/gesture data, compile pass
- AnimationNetwork: 2 sub-modules (Constants 130L, Receive 141L) + main 430L — remotes, server relay, client jitter buffer, buffer quantization
- ProceduralAnimator: split in Phase 3 into 8 modules (see Where things live). The animator keeps only what needs the animator's own state: the heartbeat loop, the public API surface, player tracking and init/teardown wiring. Every extracted module is constructed with a dependency table, so none requires the animator back and the require graph stays acyclic.

## Decisions & gotchas
- BLOCKER (verified live in Play, Phase 2): the default player character in this place is a SKINNED-MESH R15 rig with ZERO Motor6D. Joints are 15 AnimationConstraints (Root, Waist, Neck, Left/Right Shoulder, Elbow, Wrist, Hip, Knee, Ankle) plus BallSocket/RigidConstraints and 54 Attachments; the character has no Animator instance. The framework writes Motor6D.Transform throughout, so CacheJoints finds no Motor6D and setup aborts with 'missing R15 joint Waist'. Supporting this rig is a separate architectural decision (drive AnimationConstraint.Transform, or force a Motor6D rig) and is NOT part of the Phase 2 defect list.
- Chest joint is optional (stock R15 has no Chest Motor6D); framework warns but continues
- Config.RequireOptionalJoints now gates the optional-joint policy in CacheJoints (previously dead code)
- SlerpCFrame uses normalised-lerp fallback when dot > 0.9995 to avoid sin(theta) precision loss
- Jump uses Humanoid.StateChanged + FloorMaterial poll (StateChanged alone misses ledge falls)
- Ankle alignment via axis-angle correction through Motor6D.Transform
- Preview mode anchors only HumanoidRootPart
- Remotes created at runtime under ProceduralAnimation/Remotes folder
- Zero-weight clips and joints skipped before buffer work
- Packet: 6 bytes per joint (3x i16 Euler), 116 bytes for 16 joints, under 900-byte unreliable limit

## User preferences
- Strict 500-line limit per script
- Phased development with mandatory checkpoints
- No unrelated fixes mixed into current phase
- Verification evidence required before marking completion
- GoodPractices, BadPractices, SyntaxReference documents required (Phase 5)

## Phase status
- Phase 0 Discovery: PASS. Framework inventory = 16 scripts (14 under ReplicatedStorage.ProceduralAnimation, 1 server Script, 1 StarterPlayer LocalScript). Require graph verified acyclic. MathLib export audit: 25 exports defined across 4 Math sub-modules, 0 missing, 0 orphaned. Pre-Phase-0 snapshot saved to ServerStorage.ZeroScript.BackupsPhase0.
- Phase 1 AnimationMath repair: VERIFIED COMPLETE, no changes needed. MathCore 459L, MathCurves 243L, MathIk 110L, MathWaves 121L; all top-level, no nesting, all sub-modules load (require blocked in Edit datamodel by plugin sandbox only).
- Phase 2 Critical defects: FIXES APPLIED and server bootstrap verified in Play ('ProceduralAnimationServer ready' now prints; it previously crashed at Network.Init). Fixes: (1) AnimationNetwork — added the missing local Players service; the undefined global made PlayersGetPlayers(Players) pass nil as self. (2) ProceduralAnimator — forward-declared local ApplyWorldDirection above UpdateFabrikChain and demoted its body to a plain function assignment, so the FABRIK call site no longer creates a global. (3) AnimationNetwork + AnimationNetworkReceive — payload bounds check (BufferLen < JointDataOffset + JointCount * BytesPerJoint) before decoding joints. (4) Animator.Stop now Disconnects and nils HeartbeatConnection. (5) Config.RequireOptionalJoints wired into CacheJoints. (6) Deterministic waves: AnimationConfigCompile emits Config.Compiled.WaveOrder (sorted) and UpdateWaves walks it instead of pairs().
- Phase 2 DISPROVED — do NOT re-fix: the reported ApplyWorldDirection BoneAxis shadowing and Bezier argument misalignment do not exist (no enclosing BoneAxis local in that scope; every Bezier/Ease call site matches its signature). Locomotion velocity filtering is not a defect either — velocity is read raw with a MoveDirection fallback, nothing to filter.
- Phase 2 REMAINS BLOCKED on the AnimationConstraint rig issue above: character setup cannot succeed on the current default rig regardless of these fixes.
- Note: requiring modules from execute_luau always fails with a Capabilities/Network error even in Play — that is the plugin thread sandbox, NOT a project defect. Use the Studio console for real load evidence.

- Phase 3 Architectural reorganization: PASS (source + harness verified). ProceduralAnimator 1407L -> 448L by extracting 7 modules (ClientPosePipeline 430, ClientRigKinematics 378, CharacterLifecycle 266, CharacterMotionState 152, CharacterJoints 141, StatePool 63, PoseBuffer 43). All scripts now <=500L. Public API unchanged: the api suite compares the live export surface against baseline/api.json (136 exports across 6 modules) and reports 0 removed / 0 changed. Packet layout untouched (byte-verified by the network suite).

## Verification harness (offline, no Play)
- Tools/verify/verify.mjs drives a real Luau VM (@luau-rs/luau 0.739.0) with mocked Roblox value types + services. Run `node verify.mjs` from Tools/verify; add `--no-analysis` to skip type checking, `--only=<suite>` to focus, `--snapshot-baseline` to re-record the API surface.
- Suites: math 80, config 62, network 67, integration 54, bootstrap 26, api 2. Latest run: PASS 325 | FAIL 0.
- Analysis (type checking) is not yet wired up: needs roblox-definitions.luau. That is the remaining Phase 3 item.

## Split-specific gotchas (learned the hard way)
- Cross-module extraction turns upvalues into nils. Every "attempt to call a nil value" during the Phase 3 split was a constant or helper left behind in the old module. Check the new module for every free identifier before running.
- Never capture a mutable counter at load time. `local ActiveStateCount = StatePool.Count` froze at 0 and silently disabled SetPreviewMode / SetLocomotionWeight. Read through a getter (`StatePool.Count`) instead.
- Live flags must be passed as getters, not values. SetPreviewMode mutates the animator's local; the extracted modules read it through `IsPreviewMode()`.
- Function declarations referenced by an earlier constructor closure must be declared before the constructor. Use `local Fn` then `function Fn(...)`, not `local function Fn`.

## Open questions / TODO
- Analysis (type checker) still disabled: add roblox-definitions.luau, then work the reported definition gaps.
- No Documentation/ folder yet: GoodPractices, BadPractices, SyntaxReference (Phase 5).
- Phase 0 inventory/defect report as a standalone document still outstanding.
- Phases 6-10 (PascalCase/strict migration, performance, animation features, regression pass, maintenance guide) not started.
]==]