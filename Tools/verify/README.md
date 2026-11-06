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

Exit code is non-zero unless **Compilation 28/28, Analysis 0 errors/0 warnings, Cases 433**.
The 40 "definition gaps" are a classification of engine-boundary expressions the partial,
hand-written `roblox-definitions.luau` cannot model — they are not failures, and
`roblox-definitions.luau` missing or rejected is a hard FAIL (it is what makes analysis see
the project's own code at all; see GoodPractices/Master docs).

## What is in here

| Path | Role |
|---|---|
| `verify.mjs` | Entry point: compile, analysis, boot, suites, API baseline comparison, report |
| `src/00-runner.luau` | Suite runner (discovery, Reset, isolation) |
| `src/01-mock-value-types.luau` | `Vector3`/`CFrame`/`buffer`-level value semantics as the VM sees them |
| `src/02-mock-services.luau` | Mocked `Players`, `Workspace`, `RunService`, `Enum`, instances (Character rigs are built here — the `Motor6D` joins are why it matters) |
| `src/03-env.luau` | Instance-path `require` bridge, `Env.Require`, logs, `PumpFrames` |
| `src/04-testkit.luau` | Assertion kit: `Kit.Equal/Near/Check/Guard/Pass/...` — every case carries actual vs expected |
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

## Adding a suite

Create `LuaTests/NN-name-suite.luau` returning `{ Name = "name", Reset = function() ... end, Body = function(Cases) ... end }`.
The runner discovers `LuaTests/*.luau` automatically — no registration list to update. Prefix
assertions with a short namespace (`"math."`, `"network."`) so the report reads cleanly.
Note `Kit.Guard(name, fn)` records nothing on success (it only fails on throw); use
`Kit.Check/Equal/...` when the pass matters to the count.
