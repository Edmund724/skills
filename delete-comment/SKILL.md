---
name: delete-comment
description: Audit, classify, and eliminate non-directive TypeScript comments into ADRs and deduplicated GitHub issues, then install or tighten a zero-comment ratchet guard. Use when auditing codebase comments, migrating architectural decisions out of inline comments into ADRs, filing clustered technical-debt issues, or shrinking ratchet exemptions.
---

# Delete-Comment Workflow

Execute steps in order. Preserve machine directives strictly, archive genuine architectural decisions in ADRs, file root-cause-clustered technical debt issues non-interactively via `gh`, and enforce a zero-comment ratchet guard.

## 1. Environment Preflight and Comment-Data Discovery

Run from the repository root:

```powershell
git status
gh auth status
gh repo view --json nameWithOwner
gh issue list --state open --limit 100 --json number,title
```

1. Confirm a clean working tree (or confirm intent with the user) and verify `gh` targets the repository itself.
2. Inspect `package.json`, `tsconfig.json`, and any ESLint config to identify the package manager, typecheck command, and whether ESLint + `@typescript-eslint/parser` are compatible (note: TypeScript 7.x native builds omit `ts.createSourceFile`, breaking `@typescript-eslint/parser`).
3. Search tests and build scripts (`readFileSync`, `.includes(`, regex parsers) to detect any comments parsed or asserted as machine data (such as single-line build markers or comment-embedded source URLs) before touching files.

## 2. Scan, Estimate Shed LOC, and Shard Non-Overlapping Work

Scan all `.ts`, `.tsx`, `.mts`, and `.cts` files (excluding `*.d.ts`, `*.generated.ts`, `node_modules`, `dist`, `build`, `coverage`, and scratch directories):

- Compute per-directory file counts, comment counts, comment lines, and estimated Shed LOC.
- Partition commented files into disjoint cohesive shards (roughly 15–35 files per shard) when running parallel subagents or swarm waves.
- Create a temporary scratch directory (e.g., `.comment-audit-tmp/`) for intermediate dumps, extracted JSON records, and issue bodies; never stage or commit it.

## 3. Preserve Machine Directives and Classify Comments

### Whitelisted Machine Directives (Never Delete)

- Shebang (`#!/usr/bin/env ...`)
- TypeScript triple-slash references (`/// <reference ... />`)
- JSX pragmas (`@jsx`, `@jsxImportSource`)
- Bundler, formatter, coverage, license, and codegen guards (`@vite-ignore`, `v8 ignore`, `c8 ignore`, `istanbul ignore`, `prettier-ignore`, `@license`, `DO NOT EDIT`)
- Project-specific exact single-line build markers discovered in Step 1 (for example, `// BILISCRIPT_DUAL_INSTANCE_STATEFUL` without extra prose)
- Active `eslint-disable` pragmas and explained `@ts-expect-error <reason>` assertions (retain `@ts-expect-error` when removal breaks `tsc` and log as `Excuse` unless intentionally used in negative type tests)
- Block `@ts-ignore` and `@ts-nocheck` (delete if `tsc` still passes, or convert to `@ts-expect-error <reason>` and log as `Excuse`)

### Four-Category Audit

For every remaining `//`, `/* */`, and redundant JSDoc comment:

1. **Tautology** (restates variable names or TypeScript signatures) -> Delete directly.
2. **Stale** (references removed fields, old tickets, or deleted flows) -> Delete directly.
3. **Excuse** (`TODO`, `FIXME`, fragile hack, `as unknown as` bypass, blanket empty `catch` rationale) -> Delete comment and record `{ file, line, category, comment, codeContext, rootCause, refactorSuggestion }`.
4. **Decision Record** (non-obvious architectural invariant, platform quirk, or cross-module boundary not already covered in `docs/adr/`) -> Delete source comment and record `{ file, line, topic, context, rationale }`.

Validate syntax on every stripped file (`esbuild.transformSync` or `tsc --noEmit`) before committing each wave.

## 4. Archive Decisions into ADRs

1. Deduplicate extracted `Decision Record` items against existing ADRs under `docs/adr/` (or the repo's ADR directory).
2. Cluster genuinely new, cross-cutting architectural decisions into cohesive numbered ADR files (`NNNN-slug.md`), following any existing ADR index/format rules (status header line, no scratch paths, index table updated in `docs/adr/README.md`).
3. Verify any ADR format guard tests immediately.

## 5. File Root-Cause-Clustered Technical Debt Issues

1. Cluster `Excuse` entries by shared root cause across files (avoid creating dozens of single-line issues) and exclude issues already tracked in `gh issue list --state open`.
2. Write each clustered issue body to a markdown file inside the temporary directory, listing every `file:line`, original comment/code context, root cause, and concrete refactoring plan.
3. Submit non-interactively via `--body-file` (never embed multiline/backtick bodies inside double-quoted CLI arguments) with a 1-second delay between calls:

```powershell
gh issue create --title "<concise debt title>" --body-file ".comment-audit-tmp/issue-body-1.md"
```

4. Record created Issue URLs and delete the temporary directory completely.

## 6. Enforce Zero-Comment Ratchet Guard, Verify, and Commit

Choose the enforcement mechanism matching the repository toolchain:

- **With compatible ESLint**: Add a local rule using `sourceCode.getAllComments()` plus `@typescript-eslint/ban-ts-comment`, setting `error` across `**/*.{ts,tsx,mts,cts}` with an explicit ratchet file-exemption list for remaining legacy files.
- **Without ESLint (or on TS 7.x incompatible with `@typescript-eslint/parser`)**: Maintain a zero-dependency lexical scanner script (e.g., `scripts/check-no-comments.mjs` + `lint:comments` npm script + unit test guard) using the exact same whitelist/blacklist and explicit ratchet exemption list (`RATCHET_EXEMPT_FILES` / `RATCHET_EXEMPT_PREFIXES`).

When tightening an existing ratchet guard, delete comments in one or more exempted files/subdirectories, archive any decisions/excuses per Steps 4–5, and remove those paths from the exemption list.

Finally:

1. Run full verification (`typecheck`, comment lint gate, tests, and production build).
2. Confirm `git status` is free of temporary artifacts, stage changed/added files by explicit path (`git add -- <paths...>`), and commit cleanly.
