---
name: no-comments
description: Clean up redundant comments, suppressions, and workarounds. Use when removing unnecessary comments or auditing comment quality in a diff or target files, or when running a repo-wide zero-comment migration with ADR archival, clustered debt issues, and a CI ratchet guard.
---

# No Comments

Audit and eliminate redundant comments, lint/type suppressions, and workarounds.

## Mode Selection

- **Scoped Mode (default)**: Use when targeting caller-specified files or a diff (defaulting to the current diff against base branch `main`, including the working tree). Run the Scoped Mode Steps below with [comment-sicko.md](comment-sicko.md).
- **Repo-Ratchet Mode**: Use when asked to audit comments across an entire codebase, migrate inline architectural decisions into ADRs, file clustered technical-debt issues, or install/tighten a zero-comment CI ratchet guard. Read and execute [repo-ratchet.md](repo-ratchet.md) instead of the Scoped Mode Steps.

## Keep Baseline

Both modes preserve genuine machine directives and legal headers:

- Legal, copyright, or `@license` headers, and generated-file guards (`DO NOT EDIT`).
- Runtime, compiler, bundler, formatter, and coverage directives: shebangs (`#!`), TypeScript triple-slash directives (`/// <reference ... />`), JSX pragmas (`@jsx`, `@jsxImportSource`), `@vite-ignore`, `prettier-ignore`, and coverage pragmas (`v8 ignore`, `c8 ignore`, `istanbul ignore`).
- Exact single-line markers or comment-embedded metadata parsed as data by tests or build scripts (`readFileSync`, `.includes(`, regex parsers), without extra prose.
- Lint or type suppressions only when the rule itself is proven faulty, pedantic, style-only, or part of an intentional negative type test. Correctness and safety suppressions (`eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`) stay actionable refactor targets.

Mode-specific handling for contracts and external constraints:

- **Scoped Mode** also keeps public API contract doc comments, proven external dependency/platform/vendor/protocol constraints our code cannot reshape, and Issue/RFC links explaining constraints code cannot express.
- **Repo-Ratchet Mode** migrates cross-cutting architectural and external platform invariants into `docs/adr/` so source files can enforce a strict zero-comment gate (excluding public package JSDoc when library typings require it).

## Scoped Mode Steps

1. Spawn a subagent with a fresh context (use the default model and reasoning effort, or raise reasoning effort for complex diffs). Instruct it to read `comment-sicko.md` in this skill's directory and run its review against the target scope.
2. Inspect its report and diff. Reject application-code edits, scope escapes, Keep Baseline deletions, misstated `MUST KILL` reasons, and flags that treat kept intentional code as guilty. Reshape flags on our-code surprises stay actionable; do not restore those comments. A keep survives only with proof it matches the Keep Baseline on a live path. Audit missed scoped lint and type suppressions; correctness or safety suppressions stay actionable `MUST KILL`s. Restore deletions only with exact Keep Baseline matches and scoped proof. Before accepting thin `IMPORTANT` or `do not remove` kills or keeps, trace the named symbol, callers, test/build script consumers, and git history. If a kill is ambiguous, do not restore. If a keep is refuted or still ambiguous, delete it. If the report is rejected, revert its changes and rerun once with the failure named; if a second run is rejected, report it open and abort.
3. Fix trivial accepted flags directly by deleting a dead path, dropping a parameter, or using the real API. If any fix needs structural changes, draft a concise design sketch for the accepted set and surrounding code first, then stop at the sketch before implementing in Step 4.
4. Implement the smallest root-cause fix strictly within scope and remove every named workaround. If the root cause is out of scope, land the smallest in-scope fix and report the rest open. Address root causes directly rather than adding symptom guards or widening the scope fence.
5. For constraint comments (`do not remove`, `do not change wording`, `talk to X before changing`): leave keeps about external constraints we cannot change. Offer the cheapest in-scope type, runtime, test, or CI lint enforcement. Wait for user approval (unless pre-approved in an unattended or eval run). If approved, encode the constraint then delete the comment; otherwise delete it, report the constraint open, and sketch any out-of-scope enforcement work.
6. Report the deletion count, restored comments, reruns, design sketch, fixes, encoding offers, encodings, unenforced constraints, and other open work.
