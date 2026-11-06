--!strict
return [==[
# Project memory (as of 2026-11-06, branch arena/4e24aa26-roblox-studio-test)
## Overview
Slop Game (placeId 139066482915692). Procedural animation framework for R15 avatars: locomotion (idle/walk/run, velocity-filtered), jump state machine (with squash & stretch spring), additive gestures, two-bone IK, FABRIK chains, wave-driven secondary motion, head look-at, per-joint amplitude, and networked pose replication via UnreliableRemoteEvent. All motion through Motor6D.Transform; Humanoid stays in charge of physics. Docs are in Documentation/ (Memory.md is the fastest orientation); this file is the in-place snapshot for engineers reading inside Studio.

## Where things live
- ReplicatedStorage.ProceduralAnimation.Shared — all shared modules (Config, Math, Network, Changelog)
- ReplicatedStorage.ProceduralAnimation.Client.Runtime — client runtime modules (ProceduralAnimator 468, ClientPosePipeline 475, ClientRigKinematics 443, CharacterLifecycle 280, CharacterMotionState 171, CharacterJoints 142, StatePool 74, PoseBuffer 44, PlayerTracker 98)
- ReplicatedStorage.ProceduralAnimation.Client.Bootstrap.ClientBootstrap — require-time client bootstrap ModuleScript (thin LocalScript entry remains in StarterPlayerScripts)
- ReplicatedStorage.ProceduralAnimation.Server.Bootstrap.ServerBootstrap — require-time server bootstrap ModuleScript (thin legacy Script entry remains in ServerScriptService)
- ReplicatedStorage.ProceduralAnimation.Server — exists (Bootstrap subfolder only)
- StarterPlayer.StarterPlayerScripts.ProceduralAnimationClient (thin wrapper), ServerScriptService.ProceduralAnimationServer (thin wrapper)
- ServerStorage.ZeroScript.BackupsPhase0/BackupsPhaseA — historical source snapshots

## Conventions
- PascalCase for all identifiers
- Functional, data-oriented; no OOP/metatables/inheritance/self; free functions over plain tables
- Aggregator + factory pattern for AnimationMath/AnimationConfig; dependency injection for the client split (no require cycles)
- Integer-indexed joint lookups (Config.JointIndex); no string keys in hot paths
- Buffer-based pose storage; zero allocation in the pose path (preallocated State.JointAmplitude / SquashSpring / TargetScratch / FootRayDirection)
- Config centralised; new tunables are new top-level keys only (existing config sub-tables are frozen)
- ALL files declare --!strict; analysis clean (0 err / 0 warn; 40 pre-existing definition gaps at engine boundaries)
- Every script ≤ 500 lines

## Key systems
- AnimationMath (28 exports): 4 sub-modules (Core 485 with StepSpring, Curves 336 with arc-length tables, Ik 110, Waves 121)
- AnimationConfig (37 baseline exports): Data 494, Motion 120, Compile 106
- AnimationNetwork (12 exports): main 472, Constants 130, Receive 149 — remotes, server relay, client jitter buffer, frozen 20-byte-header/6-bytes-per-joint packet (116 B @ 16 joints)
- Public API: frozen at 138 baseline exports (Tools/verify/baseline/api.json); added exports are reported, not failed. Phase 8 added SetLookAtTarget, SetJointAmplitude (Animator), GetSplineLength, SampleSplineAtDistance, StepSpring (MathLib). Config fingerprint untouched except Version 1.1.0.
- Lifecycle: Destroy/Shutdown idempotent + terminal; every :Connect retained (lifecycle suite asserts this mechanically)

## Decisions & gotchas
- BLOCKER (unresolved, never silently fix): the default player character is a SKINNED-MESH R15 rig with ZERO Motor6D (AnimationConstraint rig). CacheJoints finds no Motor6D; setup aborts with 'missing R15 joint Waist'. Supporting it is an architectural decision (drive AnimationConstraint.Transform, or force a Motor6D rig) gated on explicit authorization; requires a playtest, which is prohibited without authorization.
- Chest joint is optional; RequireOptionalJoints gates the policy
- Jump uses Humanoid.StateChanged + FloorMaterial poll; landings also kick SquashSpring (fall-speed scaled, clamped 0.5-2.0x) integrated into the root vertical offset
- Motor6D.Transform carries a FULL CFrame (rotation AND translation); vertical bob flows through it — the earlier rotation-only claim was corrected 2026-11-06 (SyntaxReference §4)
- Velocity low-pass (Config.VelocityFilterRate, 0 disables) feeds the locomotion blend; State.FilteredSpeed persists it
- Arc-length tables: precomputed at CompileSpline (64 chord segments, (Time, Value) graph); SampleSplineAtDistance is constant-speed sampling
- Look-at is additive yaw/pitch on the neck in the root's frame, after IK, before ApplyPose; nil fades out
- Studio MCP is BLOCKED in this environment; all verification is the local harness (Tools/verify, PASS 437 | FAIL 0, 28/28 compile). Harness chunks (src/0Nb-*.luau) were split 2026-11-06 to fit the 500-line rule and all carry --!strict; LuaTests specs are documented-exempt from the 500-line cap.
- GitHub is the source of truth for code; Memory.md documents Studio-side observations only

## Phase status
- Phases 0-10 COMPLETE: discovery, math repair, critical defects, typing/checker, lifecycle, bootstrap extraction, --!strict migration, performance (StatePool early-out ~15x, root-write fast path, allocation removal), feature completion (velocity filter, arc length, springs, squash & stretch, look-at, joint amplitude), regression audit (Audit.md), maintenance docs (Maintenance.md, API.md).
- ProceduralAnimation.project.json exists (repo root): Rojo 7 build mapping ROJO_OHIO_MUMBAI/ -> DataModel for placeId 139066482915692; starter entries forced to LocalScript/Script via tree keys (.local/.legacy suffixes remain harness conventions). rojo-check.mjs statically verifies coverage + conventions; rojo build NOT executed in this sandbox (assets unreachable) — validate on a network that reaches GitHub releases before publishing.
- Remaining: nothing in-scope. R6 deferred (no R6 clip data). AnimationConstraint rig blocker and Studio parity require explicit authorization / Studio access.
- 2026-11-06 (arena/e0507aaf-roblox-studio-test): harness hardening (changelog 1.1.4). Mock chunks split (01b containers, 02b rig, 03b simulation; shared tables passed as arguments, identity preserved); --!strict on all harness .luau; verify.mjs now compile-checks every src/ chunk incl. 04-testkit; the always-true integration 'lifecycle.stopHaltsUpdates' assertion replaced with a real Transform-identity check; look-at comments corrected to symmetric +/-IkAngleLimitMax (no runtime change). Gate: PASS 437 | FAIL 0. Changelog appended (1.1.4) in both copies; Config.Version unchanged (1.1.0).
]==]
