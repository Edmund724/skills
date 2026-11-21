---
name: no-comments
description: Clean up unnecessary comments, lint/TypeScript suppressions, and workarounds in a diff or target files. Use when asked to remove redundant comments, audit comment quality, or run /no-comments.
---

# No comments

Spawn a fresh subagent using [comment-sicko.md](comment-sicko.md), audit its findings, apply root-cause fixes, and handle claimed constraints.

## Scope

Use the caller's files or diff. Otherwise use the current diff against the base branch, default `main`, including the working tree.

## Steps

1. Spawn a subagent with a fresh context (use the default model and reasoning effort, or raise reasoning effort for complex diffs). Instruct it to read `comment-sicko.md` in this skill's directory and run its review against the target scope.
2. Inspect its report and diff. Reject application-code edits, scope escapes, exception-protected deletions, misstated `MUST KILL` reasons, and flags that treat kept intentional code as guilty. Reshape flags on our-code surprises stay actionable; do not restore those comments. A keep survives only with proof it describes an external constraint we cannot change. Audit missed scoped lint and TypeScript suppressions; correctness or safety suppressions stay actionable `MUST KILL`s. Restore deletions only with exact exceptions and scoped proof. Before accepting thin `IMPORTANT` or `do not remove` kills or keeps, trace the named symbol, callers, and git history. If a kill is ambiguous, do not restore. If a keep is refuted or still ambiguous, delete it. If the report is rejected, revert its changes and rerun once with the failure named; if a second run is rejected, report it open and abort.
3. Fix trivial accepted flags directly by deleting a dead path, dropping a parameter, or using the real API. If any fix needs structural changes, draft a concise design sketch for the accepted set and surrounding code first, then stop at the sketch before implementing in Step 4.
4. Implement the smallest root-cause fix strictly within scope and remove every named workaround. If the root cause is out of scope, land the smallest in-scope fix and report the rest open. Address root causes directly rather than adding symptom guards or widening the scope fence.
5. For constraint comments (`do not remove`, `do not change wording`, `talk to X before changing`): leave keeps about external constraints we cannot change. Offer the cheapest in-scope type, runtime, test, or CI lint enforcement. Wait for user approval (unless pre-approved in an unattended or eval run). If approved, encode the constraint then delete the comment; otherwise delete it, report the constraint open, and sketch any out-of-scope enforcement work.
6. Report the deletion count, restored comments, reruns, design sketch, fixes, encoding offers, encodings, unenforced constraints, and other open work.
