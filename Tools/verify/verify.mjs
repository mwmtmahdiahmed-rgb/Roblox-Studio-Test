#!/usr/bin/env node
/**
 * Tools/verify/verify.mjs
 *
 * Offline verification harness for the ProceduralAnimation framework.
 * No Roblox Studio session, no Play mode, no server, no gameplay simulation.
 *
 * What it measures:
 *
 *   1. Compilation      every .luau file is compiled by the real Luau compiler.
 *   2. Static analysis  the Luau type checker and linter run over the whole project with a
 *                       checked-in definition file describing the Roblox API surface used.
 *   3. Module loading   every module is actually require()d inside a real Luau VM against a
 *                       mocked Roblox environment, in dependency order, with cycle detection.
 *   4. Public API diff  every module export is deep-compared with the baseline recorded at
 *                       checkpoint c78cd01, so API preservation is measured.
 *   5. Behavioural      suites registered by the Lua test files are executed and asserted on.
 *
 * Usage:
 *   node Tools/verify/verify.mjs                 everything
 *   node Tools/verify/verify.mjs --only=math     suites whose name matches
 *   node Tools/verify/verify.mjs --no-analysis   skip the type checker
 *   node Tools/verify/verify.mjs --report        also write Tools/verify/out/last-run.json
 *
 * Exit code: 0 when every case passes, 1 when anything fails, 2 on harness failure.
 */

import { readFileSync, readdirSync, statSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, sep } from "node:path";

import { Lua } from "@luau-rs/luau";
import { Analysis } from "@luau-rs/luau/analysis";

const Here = dirname(fileURLToPath(import.meta.url));
const RepoRoot = join(Here, "..", "..");
const SourceRoot = join(RepoRoot, "ROJO_OHIO_MUMBAI");
const MockRoot = join(Here, "src");

// Harness files, in dependency order.
const MockFiles = ["01-mock-value-types.luau", "02-mock-services.luau", "03-env.luau", "00-runner.luau"];

const Args = process.argv.slice(2);
const OnlyFilter = (Args.find((A) => A.startsWith("--only=")) || "").split("=")[1] || null;
const SkipAnalysis = Args.includes("--no-analysis");
const WriteReport = Args.includes("--report");
// --snapshot-baseline records the current public API surface as the reference for future runs.
const SnapshotBaseline = Args.includes("--snapshot-baseline");

const Paint = process.stdout.isTTY
    ? { PASS: "\x1b[32m", FAIL: "\x1b[31m", WARN: "\x1b[33m", BLOCKED: "\x1b[35m", INFO: "\x1b[36m", DIM: "\x1b[2m", OFF: "\x1b[0m" }
    : { PASS: "", FAIL: "", WARN: "", BLOCKED: "", INFO: "", DIM: "", OFF: "" };

const Summary = { sections: [] };
let FailCount = 0;

function Headline(Text) {
    console.log(`\n${Paint.INFO}== ${Text} ==${Paint.OFF}`);
}

function Record(SectionName, Name, Status, Detail) {
    let Section = Summary.sections.find((S) => S.name === SectionName);
    if (!Section) {
        Section = { name: SectionName, cases: [] };
        Summary.sections.push(Section);
    }
    Section.cases.push({ name: Name, status: Status, detail: Detail ?? "" });
    if (Status === "FAIL") FailCount += 1;
}

//=========================================================
// File discovery
//=========================================================

function Walk(Dir, Out = []) {
    for (const Entry of readdirSync(Dir).sort()) {
        const Full = join(Dir, Entry);
        if (statSync(Full).isDirectory()) {
            if (Entry === "node_modules" || Entry === ".git" || Entry === "out") continue;
            Walk(Full, Out);
        } else if (Entry.endsWith(".luau")) {
            Out.push(Full);
        }
    }
    return Out;
}

function ReadProject() {
    const Files = new Map();
    for (const Full of Walk(SourceRoot)) {
        Files.set(relative(SourceRoot, Full).split(sep).join("/"), readFileSync(Full, "utf8"));
    }
    return Files;
}

// Rojo path -> dotted Roblox instance path, using the same naming rules Rojo applies.
function InstancePathOf(RojoPath) {
    const Segments = RojoPath.replace(/\.luau$/, "").split("/");
    let Leaf = Segments.pop();
    Leaf = Leaf.replace(/\.(local|server|legacy)$/, "");
    Segments.push(Leaf);
    return Segments.join(".");
}

function LogicalSegments(RojoPath) {
    return RojoPath.replace(/\.luau$/, "").split("/");
}

//=========================================================
// 1. Compilation
//=========================================================

function CheckCompilation(lua, Files) {
    Headline("Compilation (real Luau compiler)");
    let Ok = 0;
    let Bad = 0;
    const Entries = [...Files.entries()];
    for (const [Rel, Source] of Entries) {
        try {
            const Bytecode = lua.compile(Source, { optimizationLevel: 1, debugLevel: 1, coverageLevel: 0 });
            if (!Bytecode || Bytecode.length === 0) throw new Error("compiler returned no bytecode");
            Ok += 1;
            Record("Compilation", Rel, "PASS", `${Bytecode.length} bytes`);
        } catch (Error) {
            Bad += 1;
            const Message = String(Error.message || Error).replace(/\s+/g, " ").slice(0, 300);
            Record("Compilation", Rel, "FAIL", Message);
            console.log(`${Paint.FAIL}  FAIL${Paint.OFF} ${Rel}: ${Message}`);
        }
    }
    for (const MockName of MockFiles) {
        const Path = `Tools/verify/src/${MockName}`;
        try {
            lua.compile(readFileSync(join(MockRoot, MockName), "utf8"), { optimizationLevel: 1, debugLevel: 1, coverageLevel: 0 });
            Record("Compilation", Path, "PASS", "harness");
        } catch (Error) {
            Bad += 1;
            const Message = String(Error.message || Error).replace(/\s+/g, " ").slice(0, 400);
            Record("Compilation", Path, "FAIL", Message);
            console.log(`${Paint.FAIL}  FAIL${Paint.OFF} ${Path}: ${Message}`);
        }
    }
    console.log(`  ${Ok} compiled, ${Bad} failed`);
    return { Ok, Bad };
}

//=========================================================
// 2. Static analysis
//=========================================================

async function CheckAnalysis(Files) {
    Headline("Static analysis (Luau type checker + linter)");
    if (SkipAnalysis) {
        console.log("  skipped (--no-analysis)");
        return null;
    }

    const AnalysisInstance = await Analysis.create({ mode: "nonstrict", lint: true });
    let DefinitionLoaded = false;
    const DefinitionPath = join(Here, "roblox-definitions.luau");
    if (existsSync(DefinitionPath)) {
        try {
            AnalysisInstance.addDefinition("roblox", readFileSync(DefinitionPath, "utf8"));
            DefinitionLoaded = true;
        } catch (Error) {
            console.log(`${Paint.WARN}  definition file rejected: ${String(Error.message || Error).slice(0, 240)}${Paint.OFF}`);
        }
    }

    const Modules = [];
    for (const [Rel] of Files) Modules.push([Rel, InstancePathOf(Rel)]);
    for (const [Rel, Instance] of Modules) AnalysisInstance.setModule(Instance, Files.get(Rel));

    const Diagnostics = [];
    for (const [Rel, Instance] of Modules) {
        let Result;
        try {
            Result = AnalysisInstance.check(Instance);
        } catch (Error) {
            Diagnostics.push({ module: Rel, kind: "internal", severity: "error", line: 0, message: String(Error.message || Error).slice(0, 240) });
            continue;
        }
        for (const Diagnostic of Result.diagnostics) {
            Diagnostics.push({
                module: Rel,
                kind: Diagnostic.kind,
                severity: Diagnostic.severity,
                line: Diagnostic.location.begin.line + 1,
                message: Diagnostic.message.replace(/\s+/g, " ").slice(0, 240),
            });
        }
    }

    // A partial definition file necessarily produces "unknown global / unknown member" noise.
    // Those are reported as definition gaps; everything else is a real project diagnostic.
    const IsDefinitionGap = (Message) =>
        /Unknown global|Unknown type|does not exist|Property '.*' does not exist|Cannot call a value of the union type/i.test(Message);

    const ProjectDiagnostics = Diagnostics.filter((D) => D.kind !== "internal" && !IsDefinitionGap(D.message));
    const Gaps = Diagnostics.filter((D) => IsDefinitionGap(D.message));

    const ByModule = new Map();
    for (const Diagnostic of ProjectDiagnostics) {
        if (!ByModule.has(Diagnostic.module)) ByModule.set(Diagnostic.module, []);
        ByModule.get(Diagnostic.module).push(Diagnostic);
    }

    for (const [Rel] of Modules) {
        const Own = ByModule.get(Rel) || [];
        const Errors = Own.filter((D) => D.severity === "error");
        const Warnings = Own.filter((D) => D.severity === "warning");
        if (Errors.length > 0) {
            Record("Static analysis", Rel, "FAIL", `${Errors.length} error(s), ${Warnings.length} warning(s)`);
            for (const Error of Errors.slice(0, 8)) {
                console.log(`${Paint.FAIL}  TYPE${Paint.OFF} ${Rel}:${Error.line} ${Error.message}`);
            }
        } else if (Warnings.length > 0) {
            Record("Static analysis", Rel, "PARTIAL", `${Warnings.length} warning(s)`);
            for (const Warning of Warnings.slice(0, 8)) {
                console.log(`${Paint.WARN}  WARN${Paint.OFF} ${Rel}:${Warning.line} ${Warning.message}`);
            }
        } else {
            Record("Static analysis", Rel, "PASS", "clean");
        }
    }

    const Internal = Diagnostics.filter((D) => D.kind === "internal");
    console.log(
        `  definition file ${DefinitionLoaded ? "loaded" : "MISSING"}; ` +
        `${ProjectDiagnostics.length} project diagnostic(s), ${Gaps.length} definition gap(s), ${Internal.length} checker failure(s)`
    );

    return {
        definitionLoaded: DefinitionLoaded,
        projectErrors: ProjectDiagnostics.filter((D) => D.severity === "error").length,
        projectWarnings: ProjectDiagnostics.filter((D) => D.severity === "warning").length,
        definitionGaps: Gaps.length,
        internal: Internal.length,
        diagnostics: Diagnostics,
    };
}

//=========================================================
// 3. Runtime boot
//=========================================================

function BuildProjectMap(Files) {
    // The env mirrors the Rojo tree, so only project files under the services matter.
    const Map = {};
    for (const [Rel, Source] of Files) {
        const Segments = Rel.split("/");
        const Service = Segments[0];
        if (Service === "Tools" || Service === "README.md") continue;
        if (!/^(ReplicatedStorage|ServerScriptService|ServerStorage|StarterPlayerScripts|StarterPlayer|StarterGui|Workspace|ReplicatedFirst)$/.test(Service)) continue;
        // StarterPlayerScripts is nested under StarterPlayer in the real tree.
        Map[Rel] = Source;
    }
    // The client bootstrapper lives directly under StarterPlayerScripts in Rojo, which maps onto
    // StarterPlayer.StarterPlayerScripts in the instance tree.
    for (const Rel of [...Object.keys(Map)]) {
        if (Rel.startsWith("StarterPlayerScripts/")) {
            Map["StarterPlayer/StarterPlayerScripts/" + Rel.slice("StarterPlayerScripts/".length)] = Map[Rel];
        }
        if (Rel.startsWith("StarterPlayer/")) {
            const Rest = Rel.slice("StarterPlayer/".length);
            if (!Map["StarterPlayerScripts/" + Rest]) Map["StarterPlayerScripts/" + Rest] = Map[Rel];
        }
    }
    return Map;
}

function BootRuntime(lua) {
    Headline("Runtime boot (real Luau VM + mocked Roblox)");

    // Each harness file is a chunk. Value-type files return a table; the mock services, Env,
    // TestKit and Runner files return factories that receive their dependencies explicitly,
    // which keeps the harness free of require cycles and keeps line numbers intact.
    const LoadChunk = (FileName) => lua.load(readFileSync(join(MockRoot, FileName), "utf8"), {
        name: `@verify/${FileName}`,
    });

    const ValueTypes = LoadChunk("01-mock-value-types.luau").call().at(0);

    const ServicesFactory = LoadChunk("02-mock-services.luau").call().at(0);
    const Services = ServicesFactory.call(ValueTypes).at(0);

    const EnvFactory = LoadChunk("03-env.luau").call().at(0);
    const EnvHandle = EnvFactory.call(ValueTypes, Services).at(0);

    const KitFactory = LoadChunk("04-testkit.luau").call().at(0);
    const Kit = KitFactory.call(EnvHandle).at(0);

    const RunnerFactory = LoadChunk("00-runner.luau").call().at(0);
    const Runner = RunnerFactory.call(EnvHandle).at(0);

    if (!Runner) {
        Record("Runtime boot", "harness runner", "FAIL", "no handle returned");
        return null;
    }

        const BootFn = EnvHandle.get("Boot");
    BootFn.call(Services, ValueTypes);

    // Env needs a compiler and a clock. If the source fails to compile, the reported error is
    // the real Luau diagnostic, so a broken module cannot hide behind the harness.
    const CompilerFn = lua.createFunction(function (Source, Name) {
        const SourceText = String(Source);
        const Chunk = lua.load(SourceText, { name: `@${String(Name)}` });
        return Chunk;
    }, { args: [String, String] });
    lua.globals.set("__VerifyCompiler", CompilerFn);

    lua.globals.set("__MockEnv", EnvHandle);
    lua.execute(`
        __MockEnv.SetHost({
            Compile = function(Source, Name)
                return __VerifyCompiler(Source, Name)
            end,
            Clock = function()
                return 0
            end,
        })
    `);

    const Bridge = {
        /** Calls a Lua function stored in a Lua table and unwraps the first return value. */
        call(Table, Name, ...Args) {
            const Fn = Table.get(Name);
            if (!Fn) throw new Error(`Lua bridge: ${Name} is missing`);
            return Fn.call(...Args).at(0);
        },
    };

    const Harness = { Env: EnvHandle, Kit, Runner, Services, ValueTypes, Bridge };
    Record("Runtime boot", "harness", "PASS", "Env, TestKit and Runner constructed");
    return Harness;
}

function LoadSuites(lua, Harness, Filter) {
    const SuiteDir = join(Here, "LuaTests");
    if (!existsSync(SuiteDir)) return [];
    const Factories = [];
    const Names = [];
    for (const FileName of readdirSync(SuiteDir).sort()) {
        if (!FileName.endsWith(".luau")) continue;
        const Source = readFileSync(join(SuiteDir, FileName), "utf8");
        // Each suite file is a chunk that returns a factory over (Env, Kit).
        const Chunk = lua.load(Source, { name: `@verify/LuaTests/${FileName}` });
        Factories.push(Chunk.call().at(0));
        Names.push(FileName);
    }
    if (Factories.length === 0) return [];
    const Count = Harness.Bridge.call(Harness.Runner, "InitSuites", Harness.Kit, Factories);
    return { Names, Count };
}

//=========================================================
// Main
//=========================================================

async function Main() {
    const Files = ReadProject();
    Headline(`Project ${relative(RepoRoot, SourceRoot)} (${Files.size} Luau files)`);

    const lua = await Lua.create({ sandbox: false });

    const Compile = CheckCompilation(lua, Files);
    const Analysis = await CheckAnalysis(Files);

    const Harness = BootRuntime(lua);

    if (Harness) {
        Headline("Project load and suites");
        const ProjectMap = BuildProjectMap(Files);
        const MapTable = lua.createTable();
        for (const [Rel, Source] of Object.entries(ProjectMap)) MapTable.set(Rel, Source);
        Harness.Bridge.call(Harness.Runner, "LoadProject", MapTable);

        const Loaded = LoadSuites(lua, Harness, OnlyFilter);
        if (Loaded) {
            console.log(`  ${Loaded.Count} suite(s) registered from ${Loaded.Names.length} test file(s)`);
            const SuiteList = Harness.Bridge.call(Harness.Runner, "ListSuites");
            const Wanted = String(SuiteList).split(",").filter(Boolean).filter((Name) => !OnlyFilter || Name.includes(OnlyFilter));
            for (const SuiteName of Wanted) {
                const Raw = Harness.Bridge.call(Harness.Runner, "RunSuite", SuiteName);
                let Parsed;
                try {
                    Parsed = JSON.parse(String(Raw));
                } catch (Error) {
                    Record(`Suite: ${SuiteName}`, "parse", "FAIL", String(Error.message).slice(0, 200));
                    continue;
                }
                let Pass = 0;
                let Fail = 0;
                let Blocked = 0;
                for (const TestCase of Parsed.Cases) {
                    Record(`Suite: ${SuiteName}`, TestCase.Name, TestCase.Status, TestCase.Detail);
                    if (TestCase.Status === "PASS") Pass += 1;
                    else if (TestCase.Status === "FAIL") Fail += 1;
                    else Blocked += 1;
                }
                const Tone = Fail > 0 ? Paint.FAIL : Blocked > 0 ? Paint.WARN : Paint.PASS;
                console.log(`  ${Tone}${SuiteName.padEnd(12)}${Paint.OFF} ${Pass} pass, ${Fail} fail, ${Blocked} blocked`);
                if (Fail > 0) {
                    for (const TestCase of Parsed.Cases) {
                        if (TestCase.Status === "FAIL") {
                            console.log(`${Paint.FAIL}     FAIL${Paint.OFF} ${TestCase.Name}: ${TestCase.Detail}`);
                        }
                    }
                }
            }
        }
    }

    //=========================================================
    // Public API baseline snapshot / comparison
    //=========================================================
    if (Harness && (!OnlyFilter || OnlyFilter.includes("api"))) {
        Headline("Public API surface");
        const BaselineDir = join(Here, "baseline");
        const BaselineFile = join(BaselineDir, "api.json");

        const ApiSuite = Harness.Runner.get("GetSuite").call("api").at(0);
        const SurfaceTable = ApiSuite.get("Snapshot").call().at(0);
        const CurrentSurface = JSON.parse(String(Harness.Bridge.call(Harness.Runner, "ToJson", SurfaceTable)));

        if (SnapshotBaseline || !existsSync(BaselineFile)) {
            if (!existsSync(BaselineDir)) mkdirSync(BaselineDir, { recursive: true });
            writeFileSync(BaselineFile, JSON.stringify(CurrentSurface, null, 2) + "\n");
            let Count = 0;
            for (const Entries of Object.values(CurrentSurface)) Count += Object.keys(Entries).length;
            console.log(`  baseline ${SnapshotBaseline ? "written" : "created"}: ${relative(RepoRoot, BaselineFile)} (${Count} exports)`);
            Record("API surface", "baseline", "PASS", `${Count} exports recorded`);
        } else {
            const Baseline = JSON.parse(readFileSync(BaselineFile, "utf8"));
            const BaselineTable = lua.createTable();
            for (const [ModuleName, Entries] of Object.entries(Baseline)) {
                const EntryTable = lua.createTable();
                for (const [Key, Value] of Object.entries(Entries)) EntryTable.set(Key, Value);
                BaselineTable.set(ModuleName, EntryTable);
            }
            const Compared = ApiSuite.get("Compare").call(BaselineTable).at(0);
            const Parsed = JSON.parse(String(Harness.Bridge.call(Harness.Runner, "ToJson", Compared)));
            let Fail = 0;
            for (const TestCase of Parsed) {
                Record("API surface", TestCase.Name, TestCase.Status, TestCase.Detail);
                if (TestCase.Status === "FAIL") {
                    Fail += 1;
                    console.log(`${Paint.FAIL}  FAIL${Paint.OFF} api.${TestCase.Name}: ${TestCase.Detail}`);
                }
            }
            console.log(`  ${Parsed.length} comparison case(s), ${Fail} failure(s)`);
        }
    }

    const Totals = {};
    for (const Section of Summary.sections) {
        for (const TestCase of Section.cases) {
            Totals[TestCase.status] = (Totals[TestCase.status] || 0) + 1;
        }
    }

    Headline("Summary");
    console.log(`  Compilation : ${Compile.Ok} pass / ${Compile.Bad} fail`);
    if (Analysis) {
        console.log(`  Analysis    : ${Analysis.projectErrors} error(s), ${Analysis.projectWarnings} warning(s), ${Analysis.definitionGaps} definition gap(s)`);
    }
    console.log(`  Cases       : PASS ${Totals.PASS || 0} | PARTIAL ${Totals.PARTIAL || 0} | FAIL ${Totals.FAIL || 0} | BLOCKED ${Totals.BLOCKED || 0}`);

    if (WriteReport) {
        const OutDir = join(Here, "out");
        if (!existsSync(OutDir)) mkdirSync(OutDir, { recursive: true });
        writeFileSync(join(OutDir, "last-run.json"), JSON.stringify({ summary: Summary, compile: Compile, analysis: Analysis }, null, 2));
        console.log(`  Report      : ${relative(RepoRoot, join(OutDir, "last-run.json"))}`);
    }

    process.exit(FailCount > 0 ? 1 : 0);
}

Main().catch((Error) => {
    console.error("Harness crashed:", Error);
    process.exit(2);
});
