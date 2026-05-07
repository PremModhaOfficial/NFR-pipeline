# Agent Creation Guide (SDK pipeline)

Authoring rules for new agents in `agents/<name>.md`. Every agent must meet the 9-section template and pass the validator checklist at the end of this doc.

## Core rules

### 1. Agents map to SDK phases (not microservice waves)

SDK pipeline has no system-decomposer, api-designer, database-architect, infrastructure-architect, or simulated-cto waves. Agent wave assignment maps to SDK phases:

- Phase 0 Intake: `sdk-intake-agent`
- Phase 0.5 Analyze: `sdk-existing-api-analyzer-go`, `sdk-marker-scanner`
- Phase 1 Design: `sdk-design-lead`, `sdk-designer`, `interface-designer`, `algorithm-designer`, `concurrency-designer`, `pattern-advisor`, `sdk-*-devil`
- Phase 2 Impl: `sdk-impl-lead`, `sdk-implementor`, `code-generator`, `test-spec-generator`, `sdk-merge-planner`, `sdk-marker-hygiene-devil`, `refactoring-agent-go`, `documentation-agent-go`
- Phase 3 Testing: `sdk-testing-lead`, `unit-test-agent`, `integration-test-agent`, `performance-test-agent`, `sdk-leak-hunter-go`, `sdk-integration-flake-hunter-go`, `sdk-benchmark-devil-go`
- Phase 4 Feedback: `learning-engine`, `metrics-collector`, `phase-retrospector`, `root-cause-tracer`, `defect-analyzer`, `improvement-planner`, `baseline-manager`, `sdk-skill-drift-detector`, `sdk-skill-coverage-reporter`

### 2. Devil agent requirements

Any agent whose name ends in `-devil`, `-critic`, or contains `hunter` MUST:

1. Declare `tools:` with NO write tools on source (Read, Glob, Grep, Bash for running checks only; Write only to `runs/<run-id>/<phase>/reviews/`)
2. Include explicit "You are PARANOID / SKEPTICAL / ADVERSARIAL" framing
3. Output verdict format: `ACCEPT` | `NEEDS-FIX` | `REJECT` with prefix-id findings (e.g., `DD-<n>`, `IM-<n>`)
4. Feed findings into `review-fix-protocol` (per-issue retry cap 5)

### 3. Ported agents: wrapper pattern

Ported agents (learning-engine, improvement-planner, etc.) live as thin wrappers in `agents/<name>.md`. Wrapper format:

```markdown
---
name: learning-engine
description: ...
model: opus
tools: Read, Write, Edit, Glob, Grep, Bash
---




## SDK-MODE deltas

1. [delta-1]: Drop the NATS-compliance baseline tracking. Reason: SDK is a library, no inter-service communication.
2. [delta-2]: Add skill-version-bump responsibility: when applying a prompt patch, if the patch affects a skill's prescribed behavior, bump that skill's version (patch/minor/major per the change scope).
3. [delta-3]: Read additional inputs from `runs/<run-id>/feedback/skill-drift.md` and `runs/<run-id>/feedback/skill-coverage.md`.

## Evolution patches

Apply patches from `evolution/prompt-patches/learning-engine.md` (append-only list).
```

### 4. Markers-aware agents

`sdk-marker-scanner`, `sdk-constraint-devil-go`, `sdk-merge-planner`, `sdk-marker-hygiene-devil` MUST:

- Read `state/ownership-cache.json` on startup
- Update it on completion (if applicable)
- Respect ALL marker rules from CLAUDE.md rule #29

## Final checklist deltas

Archive's checklist + SDK-mode:

18. Agent wave assignment matches one of the 7 SDK phases
19. Ported agents use the wrapper pattern (no verbatim copy) unless explicitly justified
20. Devil agents have NO source-write tools
21. Markers-aware agents read+update `state/ownership-cache.json`
22. Every agent has a `tools:` frontmatter field with least-privilege selection
