# Evolution Log — decision-logging

## 1.1.0 — bootstrap-seed — 2026-04-17
Added `skill-evolution` and `budget` entry types. Envelope required new fields `pipeline_version` + `skill_version_snapshot`. Wired into baseline-manager + improvement-planner + sdk-skill-drift-detector.

6-type schema: decision, lifecycle, communication, event, failure, refactor.
