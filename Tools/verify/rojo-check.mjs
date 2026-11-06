#!/usr/bin/env node
/*
 * rojo-check.mjs — offline integrity check for ProceduralAnimation.project.json.
 *
 * `rojo build` is the authority, but Rojo binaries are not installable from every sandbox
 * (release assets redirect to object storage the harness cannot reach). This script is NOT a
 * replacement for `rojo build`; it asserts the properties that fail silently without one:
 *   1. the project file parses as JSON with a DataModel tree;
 *   2. every $path it references exists on disk;
 *   3. every .luau under ROJO_OHIO_MUMBAI/ is claimed by some node (no file silently dropped);
 *   4. instance names in the two class-forced starter entries match the harness conventions
 *      (StarterPlayerScripts -> LocalScript, .local.luau; ServerScriptService -> Script, .legacy.luau);
 *   5. no path escapes the repository root.
 * Exit 0 = consistent, exit 1 = broken. Run it whenever files move or the project file changes.
 */
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const RepoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ProjectPath = join(RepoRoot, "ProceduralAnimation.project.json");
const SourceRoot = join(RepoRoot, "ROJO_OHIO_MUMBAI");

const Failures = [];
const Fail = (Message) => Failures.push(Message);

const Project = JSON.parse(readFileSync(ProjectPath, "utf8"));
if (!Project.tree || Project.tree["$className"] !== "DataModel") {
    Fail("tree.$className must be DataModel");
}

// Instance name of a file node = the JSON key that holds it (see note in header). Recursively
// collect: nodes with $path (must exist, must be file or folder), and the set of claimed
// files. Folder nodes claim everything beneath them.
const Claimed = new Set();
const CheckNode = (Name, Node) => {
    if (typeof Node !== "object" || Node === null) {
        Fail(`node ${Name}: must be an object`);
        return;
    }
    const ClassName = Node["$className"];
    const PathValue = Node["$path"];
    if (ClassName !== undefined && typeof ClassName !== "string") {
        Fail(`node ${Name}: $className must be a string`);
    }
    if (PathValue !== undefined) {
        if (typeof PathValue !== "string") {
            Fail(`node ${Name}: $path must be a string`);
            return;
        }
        const Full = isAbsolute(PathValue) ? PathValue : resolve(RepoRoot, PathValue);
        const Rel = relative(RepoRoot, Full);
        if (Rel.startsWith("..") || isAbsolute(Rel)) {
            Fail(`node ${Name}: $path escapes the repository root: ${PathValue}`);
            return;
        }
        if (!existsSync(Full)) {
            Fail(`node ${Name}: $path does not exist: ${PathValue}`);
            return;
        }
        if (statSync(Full).isDirectory()) {
            Walk(Full, (File) => Claimed.add(relative(RepoRoot, File)));
        } else {
            Claimed.add(relative(RepoRoot, Full));
        }
        return; // file nodes have no children to check
    }
    for (const [ChildName, ChildNode] of Object.entries(Node)) {
        if (ChildName.startsWith("$")) continue;
        CheckNode(`${Name}/${ChildName}`, ChildNode);
    }
};

function Walk(Dir, Visit) {
    for (const Entry of readdirSync(Dir).sort()) {
        const Full = join(Dir, Entry);
        if (statSync(Full).isDirectory()) {
            Walk(Full, Visit);
        } else if (Entry.endsWith(".luau")) {
            Visit(Full);
        }
    }
}

for (const [Key, Node] of Object.entries(Project.tree ?? {})) {
    if (Key.startsWith("$")) continue;
    CheckNode(Key, Node);
}

// Coverage: every .luau in the source tree must be claimed.
const Unclaimed = [];
Walk(SourceRoot, (File) => {
    const Rel = relative(RepoRoot, File);
    if (!Claimed.has(Rel)) Unclaimed.push(Rel);
});
for (const Rel of Unclaimed) Fail(`unmapped source file (would be dropped from the place): ${Rel}`);

// Harness conventions for the two class-forced starter entries.
const ScriptService = Project.tree?.ServerScriptService?.ProceduralAnimationServer;
if (ScriptService?.["$className"] !== "Script") Fail("ServerScriptService.ProceduralAnimationServer must be $className Script");
if (typeof ScriptService?.["$path"] === "string" && !ScriptService["$path"].endsWith(".legacy.luau")) {
    Fail("server entry must be the .legacy.luau harness file");
}
const ClientScripts = Project.tree?.StarterPlayer?.StarterPlayerScripts?.ProceduralAnimationClient;
if (ClientScripts?.["$className"] !== "LocalScript") Fail("StarterPlayerScripts.ProceduralAnimationClient must be $className LocalScript");
if (typeof ClientScripts?.["$path"] === "string" && !ClientScripts["$path"].endsWith(".local.luau")) {
    Fail("client entry must be the .local.luau harness file");
}

if (Failures.length > 0) {
    for (const Failure of Failures) console.error("FAIL " + Failure);
    console.error(`rojo-check: ${Failures.length} problem(s)`);
    process.exit(1);
}
console.log(`rojo-check: OK — ${Claimed.size} source file(s) mapped, no escapes, harness conventions hold`);
