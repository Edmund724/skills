---
name: improve-codebase-architecture
description: Scan a codebase for deepening opportunities and refactor them via subagents, asking only on UX or high-impact changes.
disable-model-invocation: true
---

# Improve Codebase Architecture

Surface architectural friction and execute **deepening refactors**: turn shallow modules into deep ones to improve leverage, locality, and testability.

Ground every assessment and refactor in the project's domain model and shared design language:

- Call the Skill tool with `codebase-design` (and read its `DEEPENING.md` reference) for the architecture vocabulary (**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**), dependency categories, seam discipline, and replace-don't-layer testing. Use these terms exactly rather than drifting into "component," "service," "API," or "boundary."
- Read `GLOSSARY.md` (or `GLOSSARY-MAP.md`) for domain names at seams, and `docs/adr/` for settled decisions that refactors must respect.

## Process

### 1. Explore

**Scope before you scan (YAGNI).** Deepening pays off where code keeps changing:

- If the user named a target (a module, subsystem, or pain point), scope to that area.
- Otherwise, inspect recent commit history (`git log --oneline`) to find hot spots—files and clusters that churn repeatedly—and focus there first. Widen the net only when history has no clear hot spots.

Read `GLOSSARY.md` and any ADRs covering the target area, then spawn an **exploration subagent** to walk the code and locate genuine friction:

- Understanding one concept requires bouncing across many small modules
- **Shallow** modules whose interface is nearly as complex as their implementation
- Pure functions extracted for testability while real bugs hide in caller orchestration (poor **locality**)
- Tightly-coupled modules leaking internal details across seams
- Behaviour that is untested or awkward to test through its current interface

Filter suspects with the **deletion test**: keep only candidates where merging or reshaping genuinely concentrates complexity rather than shifting it around. For each worthwhile candidate, record the involved files, dependency category (per `DEEPENING.md`), target seam and interface shape, and triage bucket (`auto-execute` vs. `escalate`). If nothing clears the bar, state that concisely and stop.

### 2. Triage: dispatch vs. ask

Act directly from triage instead of generating a standalone or HTML report. Partition worthwhile candidates into two buckets and advance them **in parallel** (never block `auto-execute` work on `escalate` answers):

- **Auto-execute**: Purely internal module deepening that preserves user experience and externally observable behaviour, honours existing ADRs, keeps core cross-subsystem public contracts intact, and introduces no new external dependencies. Immediately dispatch **implementer subagents** (Step 3) and briefly note in chat what is running.
- **Escalate**: Any candidate that changes user experience or external behaviour (UI, CLI, public API/config contracts), contradicts an existing ADR (surface only when the friction genuinely justifies reopening it), alters a core public contract shared across major subsystems, or adds a new external dependency. Ask the user concisely in chat—listing files, friction, proposed change, why it requires a decision, and your recommendation—and wait for approval before implementing those items.
  - If the user rejects an escalated candidate for a load-bearing architectural reason, call `domain-modeling` and offer to record an ADR.
  - If an approved high-impact candidate has non-obvious interface trade-offs, use `codebase-design`'s `DESIGN-IT-TWICE.md` pattern before coding.

### 3. Refactor via implementer subagents

Dispatch **implementer subagents** for all `auto-execute` candidates (and any `escalate` candidates once approved):

- Run sequentially when candidates touch overlapping files; run in parallel in isolated `git worktree` branches when candidates touch disjoint areas.
- Brief each subagent with compact context pointers (target files, `GLOSSARY.md`, relevant ADRs, `codebase-design` + `DEEPENING.md`, and the target seam/interface):
  - Deepen the module behind a small interface named with `GLOSSARY.md` domain terms.
  - Apply `DEEPENING.md` seam discipline (only introduce a port when at least two adapters are justified) and **replace, don't layer** tests: test observable behaviour through the deepened interface, delete obsolete shallow tests, and remove orphaned code.
  - Run relevant tests, typechecks, and builds until green.
- When naming or sharpening domain concepts during the refactor, call `domain-modeling` to keep `GLOSSARY.md` current (creating it lazily if needed).

### 4. Integrate and clean up

- Merge completed worktree branches back into the working branch and run verification across the combined changes.
- Clean up every temporary worktree (`git worktree remove`), temporary branch (`git branch -D`, or tag `archive/<worktree>` first if unmerged without conflict resolution), and isolated build caches; explicitly report any worktree retained due to unresolved conflicts.
- Report a concise summary of deepened modules, test/glossary updates, and any escalated items awaiting user input.
