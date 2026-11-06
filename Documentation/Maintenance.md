# Maintenance Procedures — Procedural Animation Framework

Audience: the engineer who changes this next. Read `Memory.md` first (state, blockers), then this
file for **how to change things safely**, then `GoodPractices.md` / `BadPractices.md` for the
house rules and `SyntaxReference.md` before writing code.

Golden rule for every change: **finish with `cd Tools/verify && node verify.mjs` green.** A
change that cannot pass the gate does not merge. GitHub is the source of truth; if this file
and the harness disagree, the harness wins.

---

## 1. Verify (do this before anything else)

```bash
cd Tools/verify
npm install                 # first time only
node verify.mjs             # full gate: compile + analysis + 8 suites + API baseline
node verify.mjs --only=math # one suite
node bench.mjs              # comparative micro-benchmarks (same machine only)
```

Expected: `Compilation 28 pass / 0 fail`, `Analysis 0 errors / 0 warnings / 40 gaps`,
`Cases PASS 433 | FAIL 0`. The 40 definition gaps are pre-existing and classified, not
failures; a missing `roblox-definitions.luau` is a hard FAIL.

## 2. 500-line rule & file placement

Every script ≤ 500 lines. New modules live in the existing hierarchy:

- Runtime client logic → `Client/Runtime/`
- Require-time init (returns handles) → `Client/Bootstrap` / `Server/Bootstrap`
- Constants/data → `Shared/Config/Data`; compile pass → `Shared/Config/Compile`
- Math → `Shared/Math/{Core,Curves,IK,Waves}`; aggregator re-exports via `AnimationMath`
- Net format constants → `Shared/Networking/Constants`; packet decode → `NetworkReceive`

The harness auto-discovers every `*.luau` under the project root (`Walk` in `verify.mjs`), so a
new file is automatically compiled and analysed — you do **not** need to register it anywhere.
Do not create empty folders; do not leave scaffolding files.

## 3. Adding a public API export (safe, additive)

The full current inventory with signatures lives in `API.md` — update it in the same change.

1. Add the export to the module. Keep the signature documented (full parameter and return
   annotations, `--!strict`).
2. Additions are **reported, not failed** by the api suite. Do NOT run
   `--snapshot-baseline` for additions. The baseline (`baseline/api.json`) is a freeze of what
   must keep working — treat it as append-only in practice.
3. **Never** remove, rename, or change the shape/arity/types of an existing export —
   `exports.noneChangedShape` fails the build if you do.
4. Append a changelog entry (§7), bump `Config.Version` if it is a feature release (§8).
5. Mirror the export list update in `Documentation/Memory.md` §4.

## 4. Adding a config key (narrow gates)

- **New top-level key**: safe. The config fingerprint section in the api baseline only freezes
  the *sub-table shapes* it already knows; `VelocityFilterRate`, `SquashStretch`, `LookAt` were
  added this way and the fingerprint passed unchanged.
- **Existing config sub-table** (e.g. `Config.Locomotion`, `Config.Compiled.*`): the fingerprint
  fails. Only do it with an explicit decision, re-run with `--snapshot-baseline`, and justify in
  the changelog. If you are tempted, you probably want a new top-level key instead.
- Bump `Config.Version` and the `config` suite's expected version string together (currently
  `"1.1.0"` in `LuaTests/02-config-suite.luau`).
- Config is centralised: no magic numbers in runtime code; every tunable comes from
  `AnimationConfig`.

## 5. Adding behaviour in the hot path

Rules that keep the frame budget:

- No per-frame table/`Vector3` allocation unless you can show it in `bench.mjs` and justify it.
  Preallocate on `State` at `CreateState` (see `State.JointAmplitude`, `State.SquashSpring`,
  `State.FootRayDirection`, per-chain `State.TargetScratch` for the pattern).
- Buffer writes only (`buffer.readf32`/`writef32`); never index `State.Pose` as a table.
- Integer joint indices; no string keys per frame.
- Zero-weight layers skip work before touching the buffer (existing pattern).
- Smooth with `MathLib.SmoothFactor(Rate, dt)` (frame-rate independent), clamp dt when feeding
  springs/integrators (`StepSpring` caller clamps to 0.0667 s).
- If you optimise, measure with `node bench.mjs`; numbers are machine-dependent — record them
  as comparative deltas, never as absolutes.

## 6. The frozen network packet (do not touch casually)

Header 20 bytes (`Tag u8 | Sequence u16 | Tick u32 | RootPos i16×3 | RootVel i16×3 |
JointCount u8`), then 6 bytes per joint. Changing any offset is a **breaking protocol change**:
requires a `Config.Version` major bump, a new `NetworkReceive` decoder generation, baseline
snapshot, and a coordinated rollout. The network suite asserts the exact offsets and the 116-byte
size. Default answer to "just add a field" is: don't.

## 7. Adding a changelog entry (both copies, append-only)

1. `ReplicatedStorage/ProceduralAnimation/Shared/Changelog.luau` — append a new entry table to
   `Changelog.Entries` with the current version, one-line description, affected files, reason.
   Never edit or renumber existing entries.
2. `Documentation/Changelog.md` — mirror the same content in human-readable form.
3. Keep versions monotonic: fixes → patch bump, features → minor bump.
4. The runtime reads `Changelog.Entries`; the `Entry format` appendix is the template.

## 8. Release checklist

1. `node verify.mjs` green (§1).
2. `wc -l` shows no file over 500.
3. Changelog appended in both places; `Config.Version` bumped and the `config` suite updated
   to match (§4).
4. `Documentation/Memory.md` updated: phase status, suite counts, module table, gotchas.
   `ServerStorage/ZeroScript/Memory.luau` re-mirrored (it is what an engineer inside Studio
   reads first).
5. Tar backup of the tree before committing risky work:
   `tar -czf /home/user/backups/<label>-$(date +%Y%m%d-%H%M%S).tar.gz ROJO_OHIO_MUMBAI Tools Documentation`
6. Commit on `arena/<id>-roblox-studio-test` (work happens only on this branch), push to
   `origin arena/<id>-roblox-studio-test`. No force-push, no rebase of public history, no
   other branches.

## 9. Forbidden shortcuts

- No Play mode without explicit authorization; no claiming runtime behaviour from the harness.
- No editing `baseline/api.json` by hand; no `--snapshot-baseline` without an explicit decision.
- No renumbering/rewriting changelog history.
- No creating `AnimationConstraint`-based support "quietly" — that is an authorized-decision
  item (see Memory.md §5 and Audit.md O1).
- No `--!nocheck`, no `--!nonstrict`, no blanket `any` outside engine boundaries, no OOP,
  metatables, `self`, inheritance, prototype chains.
- No untracked engine connections — every `:Connect` is retained by a tracker or state field
  (the lifecycle suite enforces this mechanically).

## 10. GitHub vs Studio reality

This repository is a *checkout*. The Roblox place (placeId `139066482915692`) is the deployment.
Parity between the two has never been verified in this environment (Studio MCP blocked), and
`.luau` suffixes (`.local`, `.legacy`) are harness conventions, not Rojo filename rules — there
is no `*.project.json`. Until one exists, the mapping is enforced only by `verify.mjs`
(`InstancePathOf`) and human discipline. When adding a file, keep the conventions exactly:
PascalCase module names, correct directory, correct suffix.

## 11. When something breaks

1. Run the gate. Read the FAIL detail — it carries actual vs expected, not a shrug.
2. If analysis reports a *definition gap*: it is not a failure; only the hard-fail case
   (missing definition file) is. Do not "fix" gaps by widening types to `any`.
3. If the harness itself misbehaves (VM crash, zero cases): compare against the last backup,
   check `node_modules` version (`@luau-rs/luau` 0.739.0), confirm `roblox-definitions.luau`
   exists and is rejected/accepted as expected.
4. If you find a real defect: **stop**, record it in the changelog (appended), fix it in its
   own change, re-run the gate, and mention it in `Documentation/Audit.md` findings.
5. If the fix would touch the packet layout, the public API shape, or the AnimationConstraint
   blocker: that is no longer maintenance. Escalate.
