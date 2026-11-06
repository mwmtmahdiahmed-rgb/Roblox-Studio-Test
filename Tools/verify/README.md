# Verification harness — offline Luau gate

The only automated signal for this repository. **No Roblox Studio, no Play mode, no network.**
It compiles and type-checks the framework's Luau with a real Luau VM (`@luau-rs/luau`, pinned in
`package-lock.json`), executes the actual module sources against mocked Roblox services, and
compares the public API surface against `baseline/api.json`.

```bash
npm ci                      # first time (uses package-lock.json)
npm run verify              # = node verify.mjs
node verify.mjs --only=math # one suite
node verify.mjs --report    # write out/last-run.json
node rojo-check.mjs         # project file integrity (paths, coverage, conventions)
node bench.mjs              # comparative micro-benchmarks (same machine only)
```

Exit code is non-zero unless **Compilation 28/28, Analysis 0 errors/0 warnings, Cases 437**.
The 40 "definition gaps" are a classification of engine-boundary expressions the partial,
hand-written `roblox-definitions.luau` cannot model — they are not failures, and
`roblox-definitions.luau` missing or rejected is a hard FAIL (it is what makes analysis see
the project's own code at all; see GoodPractices/Master docs).

## What is in here

| Path | Role |
|---|---|
| `verify.mjs` | Entry point: compile, analysis, boot, suites, API baseline comparison, report |
| `src/00-runner.luau` | Suite runner (discovery, Reset, isolation) |
| `src/01-mock-value-types.luau` + `01b-mock-containers.luau` | `Vector3`/`CFrame` value semantics (part 1) · Signals, the `Instance` mock and `Enum` (part 2) |
| `src/02-mock-services.luau` + `02b-mock-rig.luau` | Mocked `Players`, `Workspace`, `RunService`, instances & remotes (part 1) · the stock R15 rig builder (part 2, attaches `CreateR15Character` to the same `MockHelpers` table) |
| `src/03-env.luau` + `03b-env-simulation.luau` | Instance-path `require` bridge, module registry, globals core (part 1) · globals installation, virtual clock, heartbeat pump, deferred queue and mock passthroughs (part 2, via the `Env.__Context` bridge) |
| `src/04-testkit.luau` | Assertion kit: `Kit.Equal/Near/Check/Guard/Pass/...` — every case carries actual vs expected |

The `0Nb-*.luau` chunks exist so every harness source fits the project's 500-line rule.
Chunks are loaded by `verify.mjs` in dependency order and hand each other their shared tables
as arguments (`Mock`, `Env`) rather than requiring each other — keep that composition when
editing. Every harness chunk is also compiled by `verify.mjs` (the `MockFiles` list) and must
open with `--!strict`.
| `LuaTests/*.luau` | The suites: `01` math · `02` config · `03` network · `04` integration · `05` bootstrap · `06` api · `07` lifecycle |
| `roblox-definitions.luau` | Partial hand-written Roblox API surface for the checker |
| `baseline/api.json` | **Frozen** public API surface (138 exports / 6 modules + network layout). Never edited by hand; `--snapshot-baseline` only with an explicit, reviewed decision |
| `bench.mjs` | Comparative benchmarks; numbers are machine-dependent and prove nothing about live runtime |
| `rojo-check.mjs` | Offline check of `ProceduralAnimation.project.json` (not a `rojo build` substitute) |
| `out/` | Run artifacts (gitignored) |

## Limitations (read before trusting a green run)

- Real Luau semantics, mocked environment. It proves structure, statics, packet layout and the
  tested behaviours — not rendering, physics, input feel, or replication across sessions.
- The default place rig is a skinned-mesh `AnimationConstraint` rig with zero `Motor6D`;
  `CacheJoints` aborts on it and no harness change can fix that — see `Memory.md` §5.
- Play mode is **prohibited** in this project without explicit authorization.
- A passing suite proves the tested property, not the absence of all defects.

## Line and typing rules for the harness

The framework enforces 500 lines per script and `--!strict` everywhere (`Memory.md`). The
harness honours the same limits, with one documented exception:

- **`LuaTests/*.luau` are exempt from the 500-line cap** (largest: `04-integration-suite.luau`).
  They are test specifications, not Roblox Scripts/ModuleScripts, and their assertions close
  over shared, stateful world-setup (`ResetWorld`, `SpawnLocalCharacter`, `Waist`, `Animator`).
  Splitting mid-flow would duplicate that fragile setup into a second suite and invite silent
  coverage loss. New suites should still prefer staying under ~500 lines.
- Every harness chunk **does** carry `--!strict` and every harness `.luau` is compiled by the
  gate (`MockFiles` includes all of `src/`, including chunks added later).

## Adding a suite

Create `LuaTests/NN-name-suite.luau` returning `{ Name = "name", Reset = function() ... end, Body = function(Cases) ... end }`.
The runner discovers `LuaTests/*.luau` automatically — no registration list to update. Prefix
assertions with a short namespace (`"math."`, `"network."`) so the report reads cleanly.
Note `Kit.Guard(name, fn)` records nothing on success (it only fails on throw); use
`Kit.Check/Equal/...` when the pass matters to the count.
