#!/usr/bin/env python3
# migrate-jsonl-to-neo4j.py
#
# Reads evolution/knowledge-base/*.jsonl (agent-performance, prompt-evolution-log)
# and emits evolution/knowledge-base/neo4j-seed.json shaped for
# mcp__neo4j-memory__create_entities + create_relations batch calls by
# learning-engine on the next pipeline run.
#
# Idempotent: records migrated file offsets in .migrated-offsets.json so
# re-runs only process new entries.
#
# Non-blocking: exits 0 on every outcome; prints WARN on parse errors.
#
# Schema version: 0.3.0 — see docs/NEO4J-KNOWLEDGE-GRAPH.md.

from __future__ import annotations

import json
import os
import pathlib
import sys
from datetime import datetime, timezone
from typing import Any

SCHEMA_VERSION = "0.3.0"

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
KB_DIR = REPO_ROOT / "evolution" / "knowledge-base"
SEED_PATH = KB_DIR / "neo4j-seed.json"
OFFSETS_PATH = KB_DIR / ".migrated-offsets.json"

SOURCE_FILES = [
    "agent-performance.jsonl",
    "prompt-evolution-log.jsonl",
]


def warn(msg: str) -> None:
    print(f"WARN: {msg}", file=sys.stderr)


def load_offsets() -> dict[str, int]:
    if not OFFSETS_PATH.is_file():
        return {}
    try:
        return json.loads(OFFSETS_PATH.read_text())
    except Exception as e:
        warn(f"could not parse {OFFSETS_PATH.name}: {e}; treating as empty")
        return {}


def save_offsets(offsets: dict[str, int]) -> None:
    try:
        OFFSETS_PATH.write_text(json.dumps(offsets, indent=2, sort_keys=True) + "\n")
    except Exception as e:
        warn(f"could not write {OFFSETS_PATH.name}: {e}")


def load_seed() -> dict[str, Any]:
    if SEED_PATH.is_file():
        try:
            data = json.loads(SEED_PATH.read_text())
            data.setdefault("entities", [])
            data.setdefault("relations", [])
            return data
        except Exception as e:
            warn(f"could not parse {SEED_PATH.name}: {e}; starting fresh")
    return {
        "schema_version": SCHEMA_VERSION,
        "migrated_at": None,
        "entities": [],
        "relations": [],
    }


def save_seed(seed: dict[str, Any]) -> None:
    seed["schema_version"] = SCHEMA_VERSION
    seed["migrated_at"] = (
        datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    )
    SEED_PATH.write_text(json.dumps(seed, indent=2, sort_keys=True) + "\n")


def entity_key(e: dict[str, Any]) -> tuple[str, str]:
    return (e.get("entityType", ""), e.get("name", ""))


def relation_key(r: dict[str, Any]) -> tuple[str, str, str]:
    return (r.get("from", ""), r.get("to", ""), r.get("relationType", ""))


def upsert_entity(seed: dict[str, Any], entity: dict[str, Any]) -> None:
    key = entity_key(entity)
    for existing in seed["entities"]:
        if entity_key(existing) == key:
            obs = existing.setdefault("observations", [])
            for o in entity.get("observations", []):
                if o not in obs:
                    obs.append(o)
            return
    seed["entities"].append(entity)


def upsert_relation(seed: dict[str, Any], relation: dict[str, Any]) -> None:
    key = relation_key(relation)
    for existing in seed["relations"]:
        if relation_key(existing) == key:
            return
    seed["relations"].append(relation)


def mk_entity(
    entity_type: str, name: str, observations: list[str] | None = None
) -> dict[str, Any]:
    return {
        "entityType": entity_type,
        "name": name,
        "observations": observations or [],
    }


def mk_relation(frm: str, to: str, rel_type: str) -> dict[str, Any]:
    return {"from": frm, "to": to, "relationType": rel_type}


def process_agent_performance_line(line: str, seed: dict[str, Any], counters: dict[str, int]) -> None:
    try:
        row = json.loads(line)
    except Exception as e:
        warn(f"agent-performance: invalid JSON ({e}); skipped")
        return

    run_id = row.get("run_id")
    agent = row.get("agent")
    phase = row.get("phase")
    if not run_id or not agent:
        warn(f"agent-performance: missing run_id or agent; skipped")
        return

    run_name = f"Run:{run_id}"
    agent_name = f"Agent:{agent}"

    run_obs = []
    if row.get("pipeline_version"):
        run_obs.append(f"pipeline_version={row['pipeline_version']}")
    if row.get("mode"):
        run_obs.append(f"mode={row['mode']}")
    if row.get("collected_at"):
        run_obs.append(f"collected_at={row['collected_at']}")
    if row.get("status"):
        run_obs.append(f"status={row['status']}")

    run_entity = mk_entity(
        "Run",
        run_name,
        observations=run_obs,
    )
    upsert_entity(seed, run_entity)
    counters["runs"] = counters.get("runs", 0) + 1

    agent_entity = mk_entity(
        "Agent",
        agent_name,
        observations=[f"phase={phase}" if phase else ""],
    )
    agent_entity["observations"] = [o for o in agent_entity["observations"] if o]
    upsert_entity(seed, agent_entity)
    counters["agents"] = counters.get("agents", 0) + 1

    if phase:
        phase_name = f"Phase:{phase}"
        upsert_entity(
            seed,
            mk_entity("Phase", phase_name, observations=[f"id={phase}"]),
        )
        upsert_relation(seed, mk_relation(run_name, phase_name, "RAN_IN_PHASE"))

    upsert_relation(seed, mk_relation(agent_name, run_name, "OBSERVED_IN"))

    scalar_bits = []
    for k in ("quality_score", "rework_iterations", "failures", "coverage_pct"):
        if k in row:
            scalar_bits.append(f"{k}={row[k]}")
    if scalar_bits:
        # attach to the Agent as observation tied to this run
        obs = f"{run_id}: " + ", ".join(scalar_bits)
        for ent in seed["entities"]:
            if entity_key(ent) == ("Agent", agent_name):
                if obs not in ent["observations"]:
                    ent["observations"].append(obs)
                break


def process_prompt_evolution_line(line: str, seed: dict[str, Any], counters: dict[str, int]) -> None:
    try:
        row = json.loads(line)
    except Exception as e:
        warn(f"prompt-evolution-log: invalid JSON ({e}); skipped")
        return

    run_id = row.get("run_id")
    patch_id = row.get("patch_id")
    target = row.get("target", "")
    if not run_id or not patch_id:
        warn(f"prompt-evolution-log: missing run_id or patch_id; skipped")
        return

    run_name = f"Run:{run_id}"
    upsert_entity(
        seed,
        mk_entity(
            "Run",
            run_name,
            observations=[f"pipeline_version={row.get('pipeline_version','?')}"],
        ),
    )

    patch_name = f"Patch:{patch_id}"
    patch_obs = []
    if row.get("confidence"):
        patch_obs.append(f"confidence={row['confidence']}")
    if row.get("ts"):
        patch_obs.append(f"applied_at={row['ts']}")
    if row.get("change_type"):
        patch_obs.append(f"change_type={row['change_type']}")
    if row.get("description"):
        desc = row["description"]
        if len(desc) > 180:
            desc = desc[:177] + "..."
        patch_obs.append(f"description={desc}")

    upsert_entity(seed, mk_entity("Patch", patch_name, observations=patch_obs))
    counters["patches"] = counters.get("patches", 0) + 1

    target_entity_type = "Skill" if "/skills/" in target else "Agent"
    if target:
        simple = (
            target.split("/")[-2]
            if target_entity_type == "Skill"
            else pathlib.Path(target).stem
        )
        target_name = f"{target_entity_type}:{simple}"
        upsert_entity(
            seed,
            mk_entity(
                target_entity_type,
                target_name,
                observations=[f"patched_by={patch_id}"],
            ),
        )
        upsert_relation(seed, mk_relation(patch_name, target_name, "APPLIED_TO"))

    for ev in row.get("source_evidence", []) or []:
        if not isinstance(ev, str):
            continue
        pat_id = f"PAT-{ev.replace(' ', '-')[:40]}"
        pat_name = f"Pattern:{pat_id}"
        upsert_entity(
            seed,
            mk_entity(
                "Pattern",
                pat_name,
                observations=[f"evidence={ev}", f"first_in={run_id}"],
            ),
        )
        upsert_relation(seed, mk_relation(patch_name, pat_name, "MOTIVATED_BY"))
        upsert_relation(seed, mk_relation(pat_name, run_name, "OBSERVED_IN"))
        counters["patterns"] = counters.get("patterns", 0) + 1


def process_file(
    path: pathlib.Path,
    seed: dict[str, Any],
    offsets: dict[str, int],
    counters: dict[str, int],
) -> None:
    if not path.is_file():
        warn(f"{path.name} not found; skipping")
        return
    start = offsets.get(path.name, 0)
    try:
        with path.open() as fh:
            lines = fh.readlines()
    except Exception as e:
        warn(f"could not read {path.name}: {e}")
        return

    new_lines = lines[start:]
    for raw in new_lines:
        line = raw.strip()
        if not line:
            continue
        if path.name == "agent-performance.jsonl":
            process_agent_performance_line(line, seed, counters)
        elif path.name == "prompt-evolution-log.jsonl":
            process_prompt_evolution_line(line, seed, counters)
        else:
            warn(f"{path.name}: unknown source; skipped")
    offsets[path.name] = len(lines)


def main() -> int:
    if not KB_DIR.is_dir():
        warn(f"{KB_DIR} not found; nothing to migrate")
        return 0

    offsets = load_offsets()
    seed = load_seed()
    counters: dict[str, int] = {}

    for fname in SOURCE_FILES:
        process_file(KB_DIR / fname, seed, offsets, counters)

    save_seed(seed)
    save_offsets(offsets)

    agents = sum(1 for e in seed["entities"] if e.get("entityType") == "Agent")
    runs = sum(1 for e in seed["entities"] if e.get("entityType") == "Run")
    patches = sum(1 for e in seed["entities"] if e.get("entityType") == "Patch")
    patterns = sum(1 for e in seed["entities"] if e.get("entityType") == "Pattern")

    print(
        f"Migrated {agents} agents, {runs} runs, {patches} patches, {patterns} patterns "
        f"into {SEED_PATH.relative_to(REPO_ROOT)}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        warn(f"unexpected error: {e}")
        sys.exit(0)
