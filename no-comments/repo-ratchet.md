# Repo-Ratchet Workflow

Execute steps in order when eliminating non-directive comments across a codebase, archiving architectural decisions into ADRs, filing root-cause-clustered debt issues, and installing or tightening a zero-comment CI ratchet guard.

## 1. Environment Preflight and Comment-Data Discovery

Run from the repository root:

```sh
git status
gh auth status
gh repo view --json nameWithOwner
gh issue list --state open --limit 100 --json number,title
```

1. Confirm a clean working tree (or confirm intent with the user) and verify `gh` targets the repository itself (if the repository uses another issue tracker, adapt Step 5 to that tracker).
2. Inspect project configs (such as `package.json`, `tsconfig.json`, and linter configs) to identify the package manager, typecheck/test commands, and linter compatibility (note: TypeScript 7.x native builds omit `ts.createSourceFile`, breaking `@typescript-eslint/parser`).
3. Search tests and build scripts (`readFileSync`, `.includes(`, regex parsers) to detect any comments parsed or asserted as machine data (such as exact single-line build markers or comment-embedded source URLs) before touching files.

## 2. Scan, Estimate Shed LOC, and Shard Non-Overlapping Work

Scan source files (for TypeScript repos, `.ts`, `.tsx`, `.mts`, and `.cts`; exclude `*.d.ts`, `*.generated.*`, vendor/dependency folders like `node_modules`, build/coverage outputs, and scratch directories):

- Compute per-directory file counts, comment counts, comment lines, and estimated Shed LOC.
- Partition commented files into disjoint cohesive shards (roughly 15 to 35 files per shard) when running parallel subagents or waves.
- Create an untracked temporary scratch directory (`.comment-audit-tmp/`) for intermediate JSON dumps and issue bodies; never stage or commit it.

## 3. Preserve Machine Directives, Fix Trivial Root Causes, and Classify Remaining Comments

Preserve every machine and legal directive listed in [SKILL.md](SKILL.md) (including project-specific exact single-line build markers discovered in Step 1). If the package publishes public library typings that require API JSDoc, scope JSDoc stripping accordingly.

Classify and process every remaining line, block, and redundant doc comment:

1. **Tautology** (restates variable names, control flow, or type signatures) -> Delete directly.
2. **Stale** (references removed fields, old tickets, deleted flows, or commented-out code) -> Delete directly.
3. **Excuse and Suppressions** (`TODO`, `FIXME`, fragile hack, `as unknown as` bypass, blanket empty `catch` rationale, `eslint-disable`, `@ts-ignore`, `@ts-nocheck`, `@ts-expect-error`):
   - **Small, local root cause** (dead branch, unused parameter, straightforward type narrowing, or `@ts-ignore` where typecheck already passes) -> Fix the code or drop the dead suppression directly within the shard.
   - **Cross-module or risky structural root cause** -> Record `{ file, line, category, comment, codeContext, rootCause, refactorSuggestion }` for Step 5. If removing `@ts-ignore` or `@ts-nocheck` breaks typecheck, convert it to `@ts-expect-error <concise-reason>` rather than hiding a bare ignore. When leaving unfixed risky code in place, keep the file under explicit ratchet exemption until resolved or retain an allowed minimal issue/ADR marker so hazards do not go silent.
4. **Decision Record** (non-obvious architectural invariant, external platform/vendor quirk, or cross-module boundary not already covered in `docs/adr/`) -> Delete inline prose and record `{ file, line, topic, context, rationale }` for Step 4.

Validate syntax and types on every stripped shard (such as `esbuild.transformSync` or `tsc --noEmit`) before committing each wave.

## 4. Archive Decisions into ADRs

1. Deduplicate extracted `Decision Record` items against existing ADRs under `docs/adr/` (or the repository's ADR directory).
2. Cluster genuinely new, cross-cutting architectural decisions into cohesive numbered ADR files (`NNNN-slug.md`), following existing ADR index and format rules (status header line, no scratch paths, index table updated in `docs/adr/README.md`).
3. Run any ADR format guard tests immediately.

## 5. File Root-Cause-Clustered Technical Debt Issues

1. Cluster unresolved `Excuse` entries by shared root cause across files (avoid creating dozens of single-line issues) and exclude debt already tracked in open issues.
2. Write each clustered issue body to a markdown file inside `.comment-audit-tmp/`, listing every `file:line`, original comment/code context, root cause, and concrete refactoring plan.
3. Submit non-interactively via `--body-file` (avoid embedding multiline or backtick bodies inside quoted CLI arguments) with a 1-second delay between calls:

```sh
gh issue create --title "<concise debt title>" --body-file ".comment-audit-tmp/issue-body-1.md"
```

4. Record created Issue URLs and delete `.comment-audit-tmp/` completely.

## 6. Enforce Zero-Comment Ratchet Guard, Verify, and Commit

Choose the enforcement mechanism matching the repository toolchain:

- **Compatible ESLint**: Add a local rule using `sourceCode.getAllComments()` plus `@typescript-eslint/ban-ts-comment`, setting `error` across `**/*.{ts,tsx,mts,cts}` with an explicit ratchet file-exemption list for remaining legacy files.
- **No ESLint, TS 7.x incompatible with `@typescript-eslint/parser`, or non-JS toolchain**: Maintain a zero-dependency lexical scanner script (for example, `scripts/check-no-comments.mjs` + `lint:comments` script + unit test guard) using the exact same directive whitelist and explicit ratchet exemption list (`RATCHET_EXEMPT_FILES` / `RATCHET_EXEMPT_PREFIXES`).

When tightening an existing ratchet guard, process one or more exempted files or directories through Steps 3 to 5 and remove those paths from the exemption list.

Finally:

1. Run full verification (`typecheck`, comment lint gate, tests, and production build).
2. Confirm `git status` is free of temporary artifacts, stage changed/added files by explicit path (`git add -- <paths...>`), and commit cleanly.
