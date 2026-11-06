#!/usr/bin/env node
/*
 * changelog-check.mjs — parity gate between the two copies of the changelog.
 *
 * The project keeps the changelog twice, by design:
 *   - Documentation/Changelog.md      (human copy, grouped by version, one `###` per entry)
 *   - Shared/Changelog.luau           (runtime copy, one table entry per change)
 * They drifted once (a 1.0.5 section misfiled under 1.0.4 in the md; caught by hand, fixed
 * in changelog 1.1.7). This script makes that failure class impossible to merge quietly.
 *
 * Asserts:
 *   1. the md has no duplicate version headers, they appear in ascending order, and every
 *      section contains at least one `###` entry;
 *   2. no `###` entry lives outside a version section;
 *   3. every runtime entry carries non-empty Description, File and Reason;
 *   4. the version SET is identical in both copies;
 *   5. per version, the entry COUNT matches between the copies (1:1 mapping).
 *
 * Usage: node changelog-check.mjs [mdPath] [luauPath]   (paths exist mainly for isolated tests)
 * Exit 0 = in parity, exit 1 = drift.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const Here = dirname(fileURLToPath(import.meta.url));
const RepoRoot = join(Here, "..", "..");
const [MdArg, LuauArg] = process.argv.slice(2);
const MdPath = MdArg ?? join(RepoRoot, "Documentation", "Changelog.md");
const LuauPath = LuauArg ?? join(RepoRoot, "ROJO_OHIO_MUMBAI", "ReplicatedStorage", "ProceduralAnimation", "Shared", "Changelog.luau");

const Failures = [];
const Fail = (Message) => Failures.push(Message);
const SemverTuple = (Text) => Text.split(".").map((Part) => Number(Part));
const CompareSemver = (A, B) => {
    for (let Index = 0; Index < 3; Index += 1) {
        if (A[Index] !== B[Index]) return A[Index] - B[Index];
    }
    return 0;
};

// ---------- 1-3: parse the markdown copy ----------
const MdSource = readFileSync(MdPath, "utf8");
const MdSections = [];
const MdSplit = MdSource.split(/^(## .+)$/gm);
// MdSplit = [preamble, header1, body1, header2, body2, ...]
for (let Index = 1; Index < MdSplit.length; Index += 2) {
    const HeaderLine = MdSplit[Index];
    const Body = MdSplit[Index + 1] ?? "";
    const VersionMatch = /^## (\d+)\.(\d+)\.(\d+)$/.exec(HeaderLine.trim());
    const Entries = (Body.match(/^### /gm) ?? []).length;
    MdSections.push({ HeaderLine: HeaderLine.trim(), Version: VersionMatch ? VersionMatch.slice(1).join(".") : null, Entries, Body });
}

const TotalMdEntries = MdSections.reduce((Total, Section) => Total + Section.Entries, 0);
const TotalTripleHeadings = (MdSource.match(/^### /gm) ?? []).length;
if (TotalTripleHeadings !== TotalMdEntries) {
    Fail(`${TotalTripleHeadings - TotalMdEntries} '### ' entr(y|ies) live outside version sections in the md copy`);
}

const MdSeen = new Map();
const VersionSections = [];
for (const Section of MdSections) {
    if (Section.Version === null) continue;
    VersionSections.push(Section);
    MdSeen.set(Section.Version, (MdSeen.get(Section.Version) ?? 0) + 1);
    if (Section.Entries === 0) Fail(`md section ${Section.Version} has no '### ' entries`);
}
for (const [Version, Count] of MdSeen) {
    if (Count > 1) Fail(`md has ${Count} duplicate '## ${Version}' sections`);
}
for (let Index = 1; Index < VersionSections.length; Index += 1) {
    if (CompareSemver(SemverTuple(VersionSections[Index - 1].Version), SemverTuple(VersionSections[Index].Version)) > 0) {
        Fail(`md version sections out of order: ${VersionSections[Index - 1].Version} then ${VersionSections[Index].Version}`);
    }
}

// ---------- parse the runtime copy ----------
const LuauSource = readFileSync(LuauPath, "utf8");
const EntryPattern = /\{\s*\n\s*Version = "(\d+\.\d+\.\d+)",\s*\n\s*Description = "((?:[^"\\]|\\.)*)",\s*\n\s*File = "((?:[^"\\]|\\.)*)",\s*\n\s*Reason = "((?:[^"\\]|\\.)*)",?\s*\n\s*\}/g;
const LuauEntries = [];
for (const Match of LuauSource.matchAll(EntryPattern)) {
    LuauEntries.push({ Version: Match[1], Description: Match[2].trim(), File: Match[3].trim(), Reason: Match[4].trim() });
}
if (LuauEntries.length === 0) {
    Fail("no runtime changelog entries matched the expected shape (parser regression or format change)");
}
for (const Entry of LuauEntries) {
    if (!Entry.Description) Fail(`runtime entry ${Entry.Version}: empty Description`);
    if (!Entry.File) Fail(`runtime entry ${Entry.Version}: empty File`);
    if (!Entry.Reason) Fail(`runtime entry ${Entry.Version}: empty Reason`);
}
const LuauSeen = new Map();
for (const Entry of LuauEntries) {
    LuauSeen.set(Entry.Version, (LuauSeen.get(Entry.Version) ?? 0) + 1);
}

// ---------- cross-checks ----------
const MdVersions = new Set(MdSeen.keys());
const LuauVersions = new Set(LuauSeen.keys());
for (const Version of MdVersions) {
    if (!LuauVersions.has(Version)) Fail(`version ${Version} present in md but missing from the runtime copy`);
}
for (const Version of LuauVersions) {
    if (!MdVersions.has(Version)) Fail(`version ${Version} present in the runtime copy but missing from the md`);
}
const AllVersions = [...new Set([...MdVersions, ...LuauVersions])].sort((A, B) => CompareSemver(SemverTuple(A), SemverTuple(B)));
for (const Version of AllVersions) {
    const MdCount = MdSeen.get(Version) ?? 0;
    const LuauCount = LuauSeen.get(Version) ?? 0;
    if (MdCountRaw(MdSections, Version) !== LuauCount) {
        Fail(`version ${Version}: ${LuauCount} runtime entr${LuauCount === 1 ? "y" : "ies"} vs ${MdCountRaw(MdSections, Version)} md entr${MdCountRaw(MdSections, Version) === 1 ? "y" : "ies"}`);
    }
}

function MdCountRaw(Sections, Version) {
    return Sections.filter((Section) => Section.Version === Version).reduce((Total, Section) => Total + Section.Entries, 0);
}

// ---------- report ----------
console.log("== Changelog parity (Documentation/Changelog.md vs Shared/Changelog.luau) ==");
console.log(`  sections in md        : ${VersionSections.length}`);
console.log(`  entries in md         : ${TotalMdEntries}`);
console.log(`  entries in runtime    : ${LuauEntries.length}`);
console.log(`  versions compared     : ${AllVersions.length}`);
if (Failures.length > 0) {
    for (const Message of Failures) console.log(`  FAIL ${Message}`);
    console.log(`  ${Failures.length} failure(s)`);
    process.exit(1);
}
console.log("  OK — both copies agree on versions and entry counts");
process.exit(0);
