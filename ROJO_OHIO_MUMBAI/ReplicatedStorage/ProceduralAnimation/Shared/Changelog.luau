--!strict
-- ProceduralAnimation/Shared/Changelog
-- Append-only record of every fix, change and design decision in this framework.
--
-- IMPORTANT FOR THE DEVELOPER: this module cannot remember anything between sessions and it
-- cannot see your edits. Every time you change the framework, append a new entry here with the
-- version, a one-line description, the affected file and the reason. Future maintainers (and
-- automated assistants) rely on this list to understand why the code looks the way it does.

local Changelog = {}

--=========================================================
-- [1] CONSTANTS
--=========================================================

local MaxRuntimeLogEntries = 64

--=========================================================
-- [2] ENTRIES
--=========================================================

Changelog.Entries = {
    {
        Version = "1.0.0",
        Description = "Initial release: R15 procedural locomotion, jump state machine, additive gestures, two-bone IK and pose replication.",
        File = "All files",
        Reason = "Requested baseline framework.",
    },
    {
        Version = "1.0.0",
        Description = "Chest joint treated as optional instead of aborting setup.",
        File = "AnimationConfig, ProceduralAnimator",
        Reason = "Stock R15 rigs do not ship a Chest Motor6D. Aborting on its absence would make the framework unusable on real avatars; a warning is logged once instead.",
    },
    {
        Version = "1.0.0",
        Description = "Pose state stored in buffer objects rather than Lua tables.",
        File = "ProceduralAnimator, AnimationNetwork",
        Reason = "Buffers are fixed size from creation, so the render loop performs zero allocations and zero rehashes.",
    },
    {
        Version = "1.0.0",
        Description = "Joint rotations are quantised as three 16-bit Euler angles per joint.",
        File = "AnimationNetwork",
        Reason = "Six bytes per joint keeps a 16-joint packet at 116 bytes, well under the 900 byte unreliable limit, and decoding is branch-free.",
    },
    {
        Version = "1.0.0",
        Description = "Remote poses are interpolated between the two most recent packets using a configurable jitter buffer delay.",
        File = "AnimationNetwork",
        Reason = "Render time is shifted back by JitterBufferDepth so a late packet does not produce a snap.",
    },
    {
        Version = "1.0.0",
        Description = "SlerpCFrame normalises a lerped quaternion instead of slerping when the dot product exceeds 0.9995.",
        File = "AnimationMath",
        Reason = "slerp divides by sin(theta), which loses precision as theta approaches zero.",
    },
    {
        Version = "1.0.0",
        Description = "Jump driven by Humanoid.StateChanged plus a FloorMaterial poll.",
        File = "ProceduralAnimator",
        Reason = "StateChanged alone misses landings triggered by physics (falling off a ledge); the poll is a cheap fallback.",
    },
    {
        Version = "1.0.0",
        Description = "Ankle alignment uses an axis-angle correction applied through Motor6D.Transform.",
        File = "ProceduralAnimator",
        Reason = "Convert the world-space foot-to-normal rotation into joint space so all motion still flows through Transform as required.",
    },
    {
        Version = "1.0.0",
        Description = "Preview mode anchors only HumanoidRootPart and zeroes scripted root offset.",
        File = "ProceduralAnimator",
        Reason = "Lets the rig be inspected without locomotion drift while every limb stays physically unanchored.",
    },
    {
        Version = "1.0.0",
        Description = "Remotes and the bindable bus live in a runtime-created Remotes folder.",
        File = "AnimationNetwork",
        Reason = "The authored layout stays exactly Shared/Client; runtime network objects are grouped separately.",
    },
    {
        Version = "1.0.0",
        Description = "Zero-weight clips and joints are skipped before any buffer work.",
        File = "ProceduralAnimator",
        Reason = "A standing character never pays for run sampling or for joints the current pose does not touch.",
    },
    {
        Version = "1.0.1",
        Description = "Phase 0: verified inventory, acyclic require graph and 25 MathLib exports; pre-change snapshot saved to ServerStorage.ZeroScript.BackupsPhase0.",
        File = "(no source change)",
        Reason = "Establish a verified baseline and a rollback point before any runtime edits.",
    },
    {
        Version = "1.0.1",
        Description = "Phase 1: AnimationMath split verified complete; FABRIK and waves are top-level and every referenced export resolves.",
        File = "(no source change)",
        Reason = "Phase 1 had already been completed earlier; re-verified instead of being redone.",
    },
    {
        Version = "1.0.1",
        Description = "Added the missing local Players service reference.",
        File = "AnimationNetwork",
        Reason = "ConnectServer called PlayersGetPlayers(Players) with an undefined global, passing nil as self and crashing server Network.Init on startup.",
    },
    {
        Version = "1.0.1",
        Description = "Forward-declared ApplyWorldDirection above UpdateFabrikChain.",
        File = "ProceduralAnimator",
        Reason = "The FABRIK call site appeared before the local declaration, so it resolved to a nil global.",
    },
    {
        Version = "1.0.1",
        Description = "Pose packets are rejected when the buffer is shorter than JointDataOffset + JointCount * BytesPerJoint.",
        File = "AnimationNetwork, AnimationNetworkReceive",
        Reason = "A truncated packet with a plausible JointCount made the decoders read past the end of the buffer. Packet layout is unchanged.",
    },
    {
        Version = "1.0.1",
        Description = "Animator.Stop disconnects and clears the Heartbeat connection.",
        File = "ProceduralAnimator",
        Reason = "Stop only cleared a flag and left the connection alive across Stop/Start cycles.",
    },
    {
        Version = "1.0.1",
        Description = "Config.RequireOptionalJoints now controls whether optional joints are mandatory.",
        File = "ProceduralAnimator",
        Reason = "The flag existed but was never read, so the optional-joint policy was effectively hardcoded.",
    },
    {
        Version = "1.0.1",
        Description = "Wave presets compile in sorted order (Config.Compiled.WaveOrder), and UpdateWaves iterates that order.",
        File = "AnimationConfigCompile, ProceduralAnimator",
        Reason = "pairs() order is unspecified; a fixed order keeps additive wave results reproducible.",
    },
    {
        Version = "1.0.2",
        Description = "Split ProceduralAnimator (1407 lines) into eight modules; every script is now under the 500-line limit.",
        File = "ProceduralAnimator, ClientPosePipeline, ClientRigKinematics, CharacterLifecycle, CharacterMotionState, CharacterJoints, StatePool, PoseBuffer",
        Reason = "Phase 3 architectural reorganization. The animator now holds only the heartbeat, the public API and init wiring (448 lines). Bodies were relocated unchanged; the extraction targets were chosen so each module owns one concern and none requires the animator back.",
    },
    {
        Version = "1.0.2",
        Description = "Added PoseBuffer as a leaf module owning the 12-byte-per-joint stride and the additive/blend writers.",
        File = "PoseBuffer",
        Reason = "Both the pose pipeline and the kinematics module write the pose buffer. Giving them a shared leaf module avoids a ClientPosePipeline <-> ClientRigKinematics require cycle.",
    },
    {
        Version = "1.0.2",
        Description = "Added StatePool, and replaced the captured ActiveStateCount with a live read.",
        File = "StatePool, ProceduralAnimator, CharacterLifecycle",
        Reason = "The character registry was duplicated across the split. Capturing StatePool.Count into a local froze it at 0, silently disabling SetPreviewMode and SetLocomotionWeight; it is now read through a getter.",
    },
    {
        Version = "1.0.2",
        Description = "Live flags are injected as getters rather than values (IsPreviewMode).",
        File = "ProceduralAnimator, ClientPosePipeline, CharacterLifecycle",
        Reason = "SetPreviewMode mutates a local owned by the animator. Passing the value copied it at construction, so the extracted modules never saw an update.",
    },
    {
        Version = "1.0.2",
        Description = "Added the offline verification harness with six suites and a public-API baseline.",
        File = "Tools/verify/*",
        Reason = "Play mode is not permitted, so correctness is established by a real Luau VM with mocked Roblox types. The api suite compares the exported surface structurally against baseline/api.json (136 exports), so refactors can be proven non-breaking rather than asserted.",
    },
    {
        Version = "1.0.2",
        Description = "The API surface comparison describes arrays by element shape instead of by index.",
        File = "Tools/verify/LuaTests/06-api-suite.luau",
        Reason = "Appending a Changelog entry changed the fingerprint of Changelog.Entries and was reported as an API break. Appending a record is not a contract change; losing or reshaping the record type is, and that is still caught.",
    },
    {
        Version = "1.0.3",
        Description = "Reorganized into the target folder hierarchy: Client/Runtime, Shared/Config/{Data,Compile}, Shared/Math/{Core,Curves,IK,Waves}, Shared/Networking/{Constants,Receive}.",
        File = "ProceduralAnimation (tree), AnimationConfig, AnimationMath, AnimationNetwork, ProceduralAnimator, PoseBuffer, NetworkConstants, NetworkReceive, ConfigCompile, client bootstrapper",
        Reason = "Phase 3 hierarchy. Modules were relocated with git mv so history is preserved, and only require() paths changed; no algorithm was touched. Client/Bootstrap and Server/ were deliberately not created because the bootstrappers must stay in StarterPlayerScripts and ServerScriptService to execute at all, and empty folders are prohibited.",
    },
    {
        Version = "1.0.3",
        Description = "Created Documentation/ with Memory, GoodPractices, BadPractices, SyntaxReference and Changelog.",
        File = "Documentation/*",
        Reason = "Priority 3 requires these before any coding session. They are derived from the actual source, not generated boilerplate; two SyntaxReference claims (buffer # length, math.round) were empirically corrected after testing them in the harness VM.",
    },
    {
        Version = "1.0.4",
        Description = "Added Shared/Utilities/Connections and a real Destroy/Shutdown lifecycle to the client runtime, the network layer and both bootstrappers.",
        File = "Utilities/Connections, ProceduralAnimator, PlayerTracker, AnimationNetwork, ProceduralAnimationClient, ProceduralAnimationServer",
        Reason = "Phase 4. Animator.Init never stored its Players connections and TrackPlayer never stored its per-player connections, so nothing could ever be disconnected; there was no Destroy at all on either side. Connections are now recorded in trackers and released by Destroy/Shutdown, which are idempotent and terminal.",
    },
    {
        Version = "1.0.4",
        Description = "Extracted PlayerTracker from ProceduralAnimator.",
        File = "PlayerTracker",
        Reason = "Keeps the animator under 500 lines after the lifecycle work, and puts every player-level connection decision in one auditable file.",
    },
    {
        Version = "1.0.5",
        Description = "Wrote Tools/verify/roblox-definitions.luau and turned the Luau type checker on by default; a missing or rejected definition file is now a hard failure.",
        File = "Tools/verify/roblox-definitions, Tools/verify/verify",
        Reason = "Phase 3's last exit item. Without the definition file every Roblox global was reported as an unknown global, those were reclassified as 'definition gaps' and filtered out of the failures, so analysis looked green while checking almost nothing. The partial hand-written surface (game, script, Vector3, CFrame, Enum, Instance, task, RaycastParams, RBXScriptConnection) now lets the checker see the project's own code. Diagnostics went from 127 (1 error / 42 warnings / 84 gaps) to 0.",
    },
    {
        Version = "1.0.5",
        Description = "Fixed an uninitialised ApplyWorldDirection upvalue in ClientRigKinematics and an undefined UpperTorso global in the test mock.",
        File = "ClientRigKinematics, Tools/verify/src/02-mock-services",
        Reason = "Found by the newly enabled checker. 'local function ApplyWorldDirection' after 'local ApplyWorldDirection' shadows the forward declaration instead of assigning it, so the FABRIK spine chain called nil on every frame for any rig with a Chest joint. The mock bug (Neck.Part0/Waist.Part1/Chest.Part1 wired from an undefined global) made the rig structurally invalid and hid that path from every existing test. A new setup.withChest integration case now covers it.",
    },
    {
        Version = "1.0.5",
        Description = "Fixed a nil MathLib on the jump path and a bare ReleaseRemotePose call in AnimationNetwork.Shutdown.",
        File = "CharacterMotionState, ClientPosePipeline, AnimationNetwork",
        Reason = "Both found by the checker. MathLib was never passed to CharacterMotionState, so UpdateJump threw on every jump. ReleaseRemotePose lives on Network, so the shutdown loop called nil; it was masked only because the harness's server player list is empty at shutdown. Also fixed two vacuous jump tests that called Humanoid.SetState with a dot, leaving NewState nil so no StateChanged ever fired.",
    },
    {
        Version = "1.0.5",
        Description = "Removed 36 dead locals left behind by the Phase 3 module split and annotated QuaternionFromCFrame's return contract.",
        File = "ProceduralAnimator, ClientPosePipeline, CharacterMotionState, ClientRigKinematics, CharacterLifecycle, AnimationNetwork, ConfigData, MathCore",
        Reason = "Lint warnings from the enabled checker: re-bound pipeline thunks and constants that nothing called, a self-assignment (local Enum = Enum), duplicate shadowing Locomotion pairs, and unused service/require locals. Annotating QuaternionFromCFrame as returning four numbers also removes the last type error: the checker inferred the unannotated parameter as unknown rather than any, which poisoned the Dot product fed to Acos(Clamp(...)). Behaviour is unchanged; packet layout and public API are untouched.",
    },
    {
        Version = "1.0.4",
        Description = "Verification harness: Suite.Reset was declared but never invoked; ResetModuleCache dropped modules without running their teardown; script lifecycle handles were discarded.",
        File = "Tools/verify/src/00-runner.luau, src/03-env.luau, src/02-mock-services.luau",
        Reason = "Three harness defects that made lifecycle tests unreliable. Suites silently ran against the previous suite's world, and connections leaked across suites. ResetModuleCache now runs each cached module's Destroy/Shutdown first, and RunScriptFile retains returned handles so teardown can release them.",
    },
    {
        Version = "1.0.6",
        Description = "Extracted the bootstrap lifecycle logic out of the StarterPlayer/ServerScriptService scripts into ModuleScripts that return lifecycle handles.",
        File = "Client/Bootstrap/ClientBootstrap, Server/Bootstrap/ServerBootstrap, ProceduralAnimationClient, ProceduralAnimationServer",
        Reason = "Scripts may not return values, and the verification harness and embedders need a real ModuleScript return for the destroy path. The starter scripts are now thin require wrappers; all lifecycle logic type-checks as a module and exposes Destroy().",
    },
    {
        Version = "1.0.6",
        Description = "Migrated every script in the repository to --!strict.",
        File = "All files",
        Reason = "Phase 6. All 28 scripts declare --!strict as their first line; analysis reports 0 errors and 0 warnings (40 pre-existing definition gaps at engine boundaries remain, documented, not regressions). Script-may-not-return-values is exactly what forced the 1.0.6 bootstrap extraction. No behaviour change intended; all suites and the API baseline remain green.",
    },
    {
        Version = "1.0.6",
        Description = "Harness: LuaTests bootstrap and lifecycle suites retargeted to the two extracted Bootstrap modules.",
        File = "Tools/verify/LuaTests/05-bootstrap-suite.luau, Tools/verify/LuaTests/07-lifecycle-suite.luau",
        Reason = "Source assertions pointed at the starter scripts, which no longer contain the lifecycle code. Assertions now read ClientBootstrap.luau / ServerBootstrap.luau by RojoPath.",
    },
    {
        Version = "1.0.7",
        Description = "StatePool.Compact early-outs when no removals are pending, via a PendingRemovals counter incremented by Remove.",
        File = "StatePool",
        Reason = "Phase 7. Steady-state frames (the common case) paid an O(n) scan to compact nothing. Measured ~1021 ns -> ~67 ns per Compact call on a full 16-state pool; Remove remains correct and the Animator.Destroy Remove-then-Clear path resets the counter.",
    },
    {
        Version = "1.0.7",
        Description = "ApplyPose root-joint write fast path: writes a pure CFrameAngles when the vertical offset is below 0.0002.",
        File = "ClientPosePipeline",
        Reason = "Phase 7. Avoids composing CFrame.new(0, y, 0) * angles every frame for rigs with no vertical root motion. The composition is only built when the offset is live. (Side effect of this change: it made explicit that Motor6D.Transform honours translation, contradicting the docs' earlier rotation-only claim; SyntaxReference 4 was corrected.)",
    },
    {
        Version = "1.0.7",
        Description = "FABRIK chains reuse per-chain TargetScratch tables instead of allocating a Vector3 per frame; FootRayDirection is cached once at state creation.",
        File = "ClientRigKinematics, CharacterLifecycle",
        Reason = "Phase 7. Two per-frame allocations removed from the hot loop. TargetScratch is created in the chain init next to the chain definition and lazily recreated if absent; FootRayDirection is the constant (0, -Config.FootRayLength, 0) cached on the state.",
    },
    {
        Version = "1.0.7",
        Description = "Added Tools/verify/bench.mjs, a machine-dependent comparative micro-benchmark of the math hot paths.",
        File = "Tools/verify/bench.mjs",
        Reason = "Phase 7. Numbers are recorded in Memory.md; they are for same-machine comparison only and prove nothing about runtime behaviour on a live rig.",
    },
    {
        Version = "1.1.0",
        Description = "Horizontal speed low-pass: the locomotion blend now uses an exponentially filtered speed (Config.VelocityFilterRate, default 12.0) instead of raw AssemblyLinearVelocity.",
        File = "ConfigData, ClientPosePipeline, CharacterLifecycle",
        Reason = "AssemblyLinearVelocity jitters frame to frame, which shimmered the idle/walk/run blend. Rate 0 disables the filter (previous behaviour). Filtered value persisted on State.FilteredSpeed; new top-level config key, no existing config changed.",
    },
    {
        Version = "1.1.0",
        Description = "Spline arc-length lookup tables: CompileSpline precomputes 64-segment chord arc lengths along the (Time, Value) graph; new exports GetSplineLength and SampleSplineAtDistance for constant-speed sampling.",
        File = "MathCurves, AnimationMath",
        Reason = "Keyframe animation needs constant-speed playback; sampling at equal time offsets over a non-uniform curve is not constant-speed. The table is built once at compile time, is shared by all three compile paths (Count==0, Count==1, Natural, Catmull-Rom via AttachArcLengths), and SampleSplineAtDistance binary-searches it allocation-free. Guard: Empty/single-key splines report zero length safely.",
    },
    {
        Version = "1.1.0",
        Description = "MathLib.StepSpring: configurable damped spring integrated with semi-implicit Euler; caller-owned State, mutated in place, zero allocation.",
        File = "MathCore, AnimationMath",
        Reason = "Springs drive the new squash & stretch root offset and are available to consumers for secondary motion. Semi-implicit Euler is stable for the shipped stiffness range (170) at frame rates down to ~15 Hz; the integration clamps dt to 0.0667s in the one runtime caller.",
    },
    {
        Version = "1.1.0",
        Description = "Squash & stretch: landing kicks a damped spring mounted on the root vertical offset, impulse scaled by fall speed (clamped 0.5-2.0x) and Config.SquashStretch.Strength.",
        File = "CharacterMotionState, ClientPosePipeline, CharacterLifecycle, ConfigData",
        Reason = "Landings read as weighty. Enabled by default (Strength 2.4, Stiffness 170, Damping 14); set Config.SquashStretch.Enabled = false to opt out. Impulse rides the same root-offset path as the idle/walk/run bob, so no new pose write path was created. Falls back to no-op when previewing or when the spring is disabled.",
    },
    {
        Version = "1.1.0",
        Description = "Head look-at: Animator.SetLookAtTarget(Vector3?, Weight?) steers the Neck joint toward a world-space target in the root's frame; exponentially smoothed (Config.LookAt.Smoothing), angle-limited by Config.IkAngleLimitMin/Max; nil fades the aim out instead of snapping.",
        File = "ProceduralAnimator, ClientRigKinematics (ApplyLookAt), ClientPosePipeline, CharacterLifecycle, ConfigData",
        Reason = "Common avatar behaviour (gaze at the object the player is interacting with) with no new engine surface: implemented as an additive yaw/pitch blend into the existing pose buffer, applied after IK and before ApplyPose. Smoothing and the fade-out behaviour mean targets can appear/disappear without pops. Default weight is 0; the feature costs one table read + an Exp() per frame when unused.",
    },
    {
        Version = "1.1.0",
        Description = "Per-joint amplitude: Animator.SetJointAmplitude(JointIndexValue, Scale) scales a joint's desired angles before smoothing.",
        File = "ProceduralAnimator, ClientPosePipeline, CharacterLifecycle",
        Reason = "Lets consumers damp or exaggerate any channel (e.g. reduce hand noise, emphasise head motion) without authoring new clips. Clamped 0..3; preallocated 16-slot table on the state; one read + compare per joint per frame when unset. Affects clips, IK, waves, FABRIK and look-at alike because it applies at the pose buffer.",
    },
    {
        Version = "1.1.0",
        Description = "Version bump to 1.1.0: new top-level config keys only (VelocityFilterRate, SquashStretch, LookAt); Config.Version = 1.1.0; packet layout and all pre-existing exports unchanged.",
        File = "ConfigData, Documentation/Changelog.md, Shared/Changelog.luau",
        Reason = "Minor release for Phase 8 feature completion. The API baseline (Tools/verify/baseline/api.json, frozen) permits added exports; nothing existing changed shape. 1.0.6 and 1.0.7 are changelog-only phases (no runtime Version bump); this entry records the release.",
    },
    {
        Version = "1.1.1",
        Description = "Added ProceduralAnimation.project.json (Rojo 7 build) and Tools/verify/rojo-check.mjs; .gitignore covers build artifacts.",
        File = "ProceduralAnimation.project.json (root, new), Tools/verify/rojo-check.mjs (new), .gitignore, Documentation/Memory.md, Maintenance.md, Audit.md",
        Reason = "Close the long-open audit item O3. The project file maps ROJO_OHIO_MUMBAI/ onto the DataModel for placeId 139066482915692; the two harness-suffixed starter entries force $className LocalScript/Script via tree keys, so the .local/.legacy harness conventions stay untouched. rojo-check.mjs statically enforces path existence, full coverage of the source tree, repository containment and the harness conventions (28/28 files mapped; negative cases verified). 'rojo build' itself was not executed in this sandbox (Rojo release assets redirect to object storage the sandbox cannot reach); the build must be validated on a network that can reach GitHub releases before publishing the place. No framework code changed; Config.Version stays 1.1.0.",
    },
    {
        Version = "1.1.2",
        Description = "Docs accuracy pass and CI: GoodPractices/BadPractices corrected, Tools/verify/README.md added, GitHub Actions Verify workflow, Maintenance/Memory docs synced.",
        File = "Documentation/GoodPractices.md, Documentation/BadPractices.md, Tools/verify/README.md (new), .github/workflows/verify.yml (new), Documentation/Maintenance.md, Documentation/Memory.md",
        Reason = "Keep the documentation as rigorous as the code after Phases 6-10 and the project-file work. GoodPractices: the Compact example now shows the Phase 7 PendingRemovals early-out and the PoseBuffer require path resolves correctly; BadPractices: the config example cites keys that exist (Locomotion.BlendRate, IkBlendRate) and the 'exports preserved' claim no longer cites a stale count; CI runs the same gate we run locally (npm ci + verify.mjs + rojo-check.mjs) so a regression cannot merge quietly. No framework code changed; Config.Version stays 1.1.0.",
    },
}

--=========================================================
-- [3] RUNTIME LOG
--=========================================================

Changelog.RuntimeLog = {}
Changelog.RuntimeLogCount = 0

--=========================================================
-- [4] PUBLIC API
--=========================================================

function Changelog.Log(Message)
    if Changelog.RuntimeLogCount >= MaxRuntimeLogEntries then
        return
    end
    Changelog.RuntimeLogCount += 1
    Changelog.RuntimeLog[Changelog.RuntimeLogCount] = Message
    warn("[ProceduralAnimation] " .. tostring(Message))
end

return Changelog
