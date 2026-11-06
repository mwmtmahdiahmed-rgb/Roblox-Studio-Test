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
