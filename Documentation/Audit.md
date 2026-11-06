# Regression Audit — Procedural Animation Framework (Phase 9)

Date: 2026-11-06. Branch: `arena/4e24aa26-roblox-studio-test`. Auditor: same engineer as Phases 6–8;
this is a deliberate adversarial re-read of the phases' own work, not of inherited code.

**Method:** full harness run (`Tools/verify/verify.mjs`), targeted source re-read of every file
touched in Phases 6–8, static checks (500-line rule, naming, allocations, frozen artifacts),
and targeted test additions for the new behaviour. Play mode is prohibited and was not entered;
nothing in this report is a runtime observation.

## Current gate (must match `node verify.mjs` output)

```
Compilation : 28 pass / 0 fail
Analysis    : 0 error(s), 0 warning(s), 40 definition gap(s)
Cases       : PASS 433 | PARTIAL 0 | FAIL 0 | BLOCKED 0
```

Suites: math 95 | config 62 | network 67 | integration 65 | bootstrap 26 | api 2 | lifecycle 50.

## Findings

### Fixed during this audit

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| F1 | **High** | `ApplyLookAt` wrote the neck with `WritePoseBlend(..., Weight=1.0)`, which *replaces* the buffer entry and discarded whatever clips/IK had written. | Now blends with `Weight = Applied` (the smoothed weight), same idiom as `ApplyWorldDirection`. `Tools/verify` green; integration `lookat.turnsNeck` / `lookat.fadesOut` cover it. |
| F2 | **High** | `CompileSpline`'s **Natural** path returned without calling `AttachArcLengths`, so `GetSplineLength`/`SampleSplineAtDistance` silently returned 0 for every Natural spline. Found by new math tests (`spline.arcLength.lineTotal` FAILED), not by reading. | `AttachArcLengths(Spline)` called on all four compile exits (Count==0, Count==1, Natural, Catmull-Rom). |
| F3 | Medium | `SetLookAtTarget(nil)` cleared the target outright, snapping the neck back to clip pose in one frame instead of fading. | `nil` now only drops the weight; the last target is retained so the exponential approach of `Config.LookAt.Smoothing` eases the head back to neutral. |
| F4 | Medium | Initial `SquashStretch.Strength = 0.16` would have produced an invisible ~0.012 rad amplitude (impulse ÷ ω ≈ 1.2 mm). | Recalibrated to 2.4 (≈0.23 studs at a normal landing); fall-speed scale clamped 0.5–2.0 keeps hops visible and high falls inside rig limits. |
| F5 | Medium | Docs claimed `Motor6D.Transform` carries rotation only; Phase 7 made explicit it carries a full CFrame (vertical bob is honoured). | Corrected in `SyntaxReference.md` §4, `GoodPractices.md` §9, `Memory.md` §5. The `Position` is no longer treated as an error signal. |
| F6 | Low | `ComputeRootOffset` consumed the landing impulse one frame after `UpdateJump` raised it (offset computed before `UpdateJump` in the loop). | Judged cosmetic (one frame at 60 Hz); documented, not restructured (reordering risks jump-clip phase sampling). |
| F7 | Low | Stale verification tool `Tools/verify/diag.mjs` (superseded by `verify.mjs`). | Deleted. |
| F8 | Low | Stale claims: `--!strict` "not yet applied" (SyntaxReference, BadPractices), suite counts (80/61), branch ref (`arena/3fd81267-…`). | All docs updated to measured state. |

### Reviewed and accepted (with rationale)

| # | Area | Decision |
|---|------|----------|
| A1 | Arc-length chord approximation (64 segments) | Underestimates true arc by <0.1% for spline families used here; binary search is correct for ties (non-decreasing table); linear scan inside `SampleSpline` kept (measured faster than binary search at ≤8 keys: 570 ns/op). |
| A2 | `StepSpring` semi-implicit Euler | Stable for shipped stiffness 170 at dt ≤ 0.0667 s (caller clamps). Damping ratio 0.54 → visible overshoot, which is the desired squash-stretch character. Exact endpoints are NOT guaranteed; `Spring` semantics documented in the function header. |
| A3 | `Transform` translation for root joint | Honoured by the engine (vertical bob flows through it); relying on it is a deliberate, documented choice. |
| A4 | Epsilon `0.0002` fast path in `ApplyPose` | Drops a ≤0.2 mm vertical translation only when offset is live-but-immaterial; no visual difference; saves one CFrame composition/frame. |
| A5 | `any` at engine boundaries | 86 explicit `: any` sites (upvalues `State`, engine userdata, dependency-injection tables). Roblox object types are not expressible precisely enough to erase these without lying; the project rule is to document, not eliminate. |
| A6 | Velocity filter changes feel | At `VelocityFilterRate = 12` the walk blend lags ~80 ms behind actual speed; this is the intended de-jitter trade-off and is configurable down/up or off (`0`). |
| A7 | Look-at sign conventions | Yaw/pitch derived from Roblox's −Z-forward CFrame convention and verified mathematically (R_x/R_y derivations); **not visually verified** — no playtest. The integration tests assert that the neck *changes*, not the exact axis signs. A sign error would show as the head aiming mirrored; this is the one Phase 8 behaviour eyeballing should confirm on the next authorised playtest. |
| A8 | `WritePoseBlend` semantics | `buf*(1-W) + x*W` — replace-with-weight, NOT additive. All blend sites now pass the intended weight; additive layers use `WritePoseAdd`. |
| A9 | `Config.Version = "1.1.0"` | Intentional Phase 8 release bump; matches `config` suite expectation and `Shared/Changelog.luau` 1.1.0 entry. |

### Known, open (carried, not regressions)

| # | Item | Status |
|---|------|--------|
| O1 | Default rig is skinned-mesh `AnimationConstraint` with zero `Motor6D` — `CacheJoints` aborts ("missing R15 joint Waist"). | **Blocker, architectural, needs explicit authorization + playtest.** Unchanged by Phases 6–8. |
| O2 | Studio MCP unavailable; GitHub-vs-Studio parity unverified. | BLOCKED. All evidence is harness-local. |
| O3 | No `*.project.json`; Rojo mapping is convention enforced by harness. | Open. Worth adding a real project file next. |
| O4 | R6 unsupported (R15 clip data only). | Deferred by design. |
| O5 | 40 definition gaps (engine-boundary expressions the partial `roblox-definitions.luau` cannot model). | Accepted; documented in Memory.md §6. Not failures. |
| O6 | Squash impulse timing is one frame after the FloorMaterial poll that raises it. | Cosmetic; see F6. |

## Frozen artifacts — verified untouched

- **Packet layout** (20-byte header, 6 B/joint, 116 B @ 16 joints): network suite byte-by-byte green; unchanged.
- **API baseline** `Tools/verify/baseline/api.json` (138 exports / 6 modules): not re-recorded; not edited. Phase 8 exports were *added* (reported), never changed; existing sub-tables untouched; only new top-level config keys (`VelocityFilterRate`, `SquashStretch`, `LookAt`).
- **Changelog numbering**: appended only (1.0.6, 1.0.7, 1.1.0); no historical entry edited.

## What this audit cannot claim

Nothing here is observed at runtime. No Play mode, no render, no physics interaction, no
network flow across sessions. The harness executes real Luau with mocked services; it proves
structure, statics, and the tested behaviours — not feel. The AnimationConstraint blocker
remains the single largest unknown and gates any claim of "works on my avatar".

## Phase 8/9 acceptance matrix

| Feature | Unit (math suite) | Integration | Suite |
|---|---|---|---|
| Velocity filter | — (wiring) | existing locomotion cases exercise it | 61→65 |
| Spline arc length | `spline.arcLength.*` (10 cases) | — | math 95 |
| `StepSpring` | `spring.*` (5 cases) | — | math 95 |
| Squash & stretch | spring cases + reviewed wiring | reviewed; timing documented (F6) | — |
| Look-at | — | `lookat.neckMotor/turnsNeck/fadesOut` | integration 65 |
| Joint amplitude | — | `amplitude.freezeWaist/waistCollapsed/restoreWaist` | integration 65 |
| Arc-length API surface | `math.exports.allPresent` extended | — | math 95 |

**Phase 9 exit: PASS (with the honest caveats in "What this audit cannot claim").**
