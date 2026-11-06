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
        Version = "1.0.5",
        Description = "Measured the --!strict migration (Phase 6): PascalCase is already clean, strict typing is tooling-blocked.",
        File = "Documentation/Memory, Tools/verify",
        Reason = "Phase 6 has two halves. Naming: an AST-level scan of every declaration, parameter, loop variable and assignment target in all 26 product files reports 0 PascalCase violations, so nothing to migrate. Strict typing: mode 'strict' reports 750 errors, but they are two cascades, not 750 problems -- 38 'Unknown require: unsupported path' (this analyser build cannot resolve any require: script.Parent.X, script.X, './X' and FindFirstChild all fail) make every require return unknown, which accounts for 388 unknown-operand and 141 operator errors. Editing product code to chase those would be guesswork. Recorded as BLOCKED pending a require-resolving toolchain rather than reported as a failure or quietly worked around.",
    },
    {
        Version = "1.0.4",
        Description = "Verification harness: Suite.Reset was declared but never invoked; ResetModuleCache dropped modules without running their teardown; script lifecycle handles were discarded.",
        File = "Tools/verify/src/00-runner.luau, src/03-env.luau, src/02-mock-services.luau",
        Reason = "Three harness defects that made lifecycle tests unreliable. Suites silently ran against the previous suite's world, and connections leaked across suites. ResetModuleCache now runs each cached module's Destroy/Shutdown first, and RunScriptFile retains returned handles so teardown can release them.",
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
