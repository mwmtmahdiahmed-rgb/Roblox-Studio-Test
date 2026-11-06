# Changelog — Procedural Animation Framework

Append-only history. **Never rewrite, reorder or renumber a historical entry.**

The canonical machine-readable copy lives at
`ReplicatedStorage/ProceduralAnimation/Shared/Changelog.luau`, because runtime code reads
`Changelog.Entries` and `Changelog.Log`. This file is the human-readable mirror. When you add
an entry, add it in **both** places.

Regenerate this mirror with the script in `Documentation/` if the two ever drift.

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

---

## Entry format

```
{
    Version = "1.0.4",
    Description = "One line. What changed.",
    File = "Module, Module",
    Reason = "Why it was necessary. What was broken or missing.",
}
```

Bump the patch number for fixes, the minor number for new framework features.
