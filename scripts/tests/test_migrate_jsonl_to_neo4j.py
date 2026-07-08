import sys
import json
import pathlib
from unittest.mock import patch
import pytest
import importlib.util

# Add scripts directory to path so we can import the script
scripts_dir = pathlib.Path(__file__).resolve().parent.parent
script_path = scripts_dir / "migrate-jsonl-to-neo4j.py"

spec = importlib.util.spec_from_file_location("migrate_jsonl", script_path)
migrate_jsonl = importlib.util.module_from_spec(spec)
sys.modules["migrate_jsonl"] = migrate_jsonl
spec.loader.exec_module(migrate_jsonl)

DEFAULT_SEED = {
    "schema_version": migrate_jsonl.SCHEMA_VERSION,
    "migrated_at": None,
    "entities": [],
    "relations": [],
}

@patch("migrate_jsonl.SEED_PATH")
def test_load_seed_file_not_found(mock_seed_path):
    mock_seed_path.is_file.return_value = False

    result = migrate_jsonl.load_seed()

    assert result == DEFAULT_SEED

@patch("migrate_jsonl.warn")
@patch("migrate_jsonl.SEED_PATH")
def test_load_seed_invalid_json(mock_seed_path, mock_warn):
    mock_seed_path.is_file.return_value = True
    mock_seed_path.read_text.return_value = "not a json"
    mock_seed_path.name = "neo4j-seed.json"

    result = migrate_jsonl.load_seed()

    assert result == DEFAULT_SEED
    mock_warn.assert_called_once()
    assert "could not parse" in mock_warn.call_args[0][0]

@patch("migrate_jsonl.SEED_PATH")
def test_load_seed_valid_json_missing_keys(mock_seed_path):
    mock_seed_path.is_file.return_value = True
    # Missing entities and relations
    data = {"some": "data"}
    mock_seed_path.read_text.return_value = json.dumps(data)

    result = migrate_jsonl.load_seed()

    assert result["entities"] == []
    assert result["relations"] == []
    assert result["some"] == "data"

@patch("migrate_jsonl.SEED_PATH")
def test_load_seed_valid_json_full(mock_seed_path):
    mock_seed_path.is_file.return_value = True
    data = {
        "entities": [{"name": "E1"}],
        "relations": [{"from": "A", "to": "B"}],
        "schema_version": "0.1.0"
    }
    mock_seed_path.read_text.return_value = json.dumps(data)

    result = migrate_jsonl.load_seed()

    assert result == data
