return [==[
# Project memory
## Overview
Slop Game (placeId 139066482915692). Procedural animation framework for R15 avatars: locomotion (idle/walk/run), jump state machine, additive gestures, two-bone IK, FABRIK chains, wave-driven secondary motion, and networked pose replication via UnreliableRemoteEvent. All motion through Motor6D.Transform; Humanoid stays in charge of physics.

## Where things live
- ReplicatedStorage.ProceduralAnimation.Shared — all shared modules (Config, Math, Network, Changelog)
- ReplicatedStorage.ProceduralAnimation.Client.ProceduralAnimator — client runtime (1385 lines, OVER 500-line limit)
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
- ProceduralAnimator: monolithic client module — joint caching, locomotion blending, jump state machine, clip playback, two-bone IK, FABRIK, waves, gesture system, pose smoothing, network send

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

## Open questions / TODO
- ProceduralAnimator is 1385 lines — must be split in Phase 3 (Architectural Reorganization)
- Phase 1 (AnimationMath repair) appears already complete from Phase A — verify exports
- Phase 2 defects need verification against actual source
- No GoodPractices/BadPractices/SyntaxReference modules yet
- Bootstrappers already exist (client 30L + server 42L); Phase 4 is hardening (Destroy, duplicate-init guard, lifecycle), not building from scratch
]==]