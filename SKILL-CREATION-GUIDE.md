<!-- cross_language_ok: true — top-level pipeline doc references per-pack tooling and the multi-tenant SaaS platform context (per F-008 in migration-findings.md). Authoritative project description: SDK is built FOR multi-tenant SaaS consumers; multi-tenant guardrails (TenantID, JetStream, MsgPack, schema-per-tenant) are in-scope. -->

# Skill Creation Guide (SDK pipeline)

Authoring rules for new skills in `skills/<name>/SKILL.md`. Every skill must pass the validator checklist at the end of this doc.

## Core rules

### 1. Mandatory `version:` frontmatter

Every skill MUST declare a semver:

```yaml
---
name: go-sdk-config-struct-pattern
description: ...
version: 1.0.0
created-in-run: <run-id>
last-evolved-in-run: <run-id>
source-pattern: core/l2cache/dragonfly/
status: stable | draft | deprecated
tags: [sdk, client, config, constructor]
---
```

- Patch bump (1.0.0 → 1.0.1): append-only, no semantic change
- Minor bump: new examples, extended scope
- Major bump: breaking reinterpretation; requires user approval at H9 (no golden-corpus gate — the pipeline does not run full-replay regression; per-patch notifications in `learning-notifications.md` let the user revert)

### 2. Mandatory `evolution-log.md` sibling

Each `skills/<name>/` dir MUST contain `evolution-log.md`:

```
## 1.2.0 — run-<id> — 2026-MM-DD
Triggered by: <agent> finding <id>
Change: <one-line summary>
Applied by: learning-engine (body patch, minor bump) | human-PR (new skill | major bump)
Golden-regression: PASS | FAIL (FAIL blocks auto-apply)
## 1.1.0 — ...
```

### 3. DROP multi-tenancy-mandatory clause

Archive guide requires data/API skills include multi-tenancy patterns. SDK is a library — tenant context is caller-supplied. Drop this requirement.

### 4. ADD target-SDK-convention clause

Every skill whose domain touches target SDK structure (package layout, constructor pattern, OTel wiring) MUST include a section:

```
## Target SDK Convention

Current convention in motadatagosdk: <what the SDK does today>
If TPRD requests divergence: <decision procedure>
```

### 5. ADD 3+ GOOD/BAD examples sourced from target SDK

Examples must cite actual files in the target SDK where possible. Purely synthetic examples ok only when no target-SDK equivalent exists.

### 6. Human PR review on every new skill

Skills are human-authored. Before a new skill lands in `skills/`, the PR must be reviewed by: (a) the subject-matter owner (per `AGENTS.md` ownership matrix), (b) at least one devil-agent owner for the domain. Pipeline-run reviews are not a substitute for human review. Every PR merge logs a `skill-evolution` entry in `evolution/knowledge-base/prompt-evolution-log.jsonl` for provenance.

## Skill file layout

```
skills/<skill-name>/
├── SKILL.md              ← required
├── evolution-log.md      ← required, append-only
├── reference/            ← optional, longer examples
│   └── *.md
└── examples/             ← optional, runnable Go snippets
    └── *.go
```

## Final checklist

The archive's 16-check validator + these SDK-mode checks:

17. `version:` frontmatter present and semver-valid
18. `evolution-log.md` exists with at least one entry
19. Target SDK Convention section present if domain touches SDK structure
20. ≥3 GOOD/BAD examples, ≥1 sourced from target SDK (when applicable)
21. Human PR review ACCEPT from subject-matter owner + domain devil-agent owner (recorded in commit trailers + evolution-log.md)
22. No prescription requires `encoding/json` for internal patterns (SDK prefers MsgPack for NATS-adjacent code)
23. No tenant_id column / schema-per-tenant artifacts proposed
