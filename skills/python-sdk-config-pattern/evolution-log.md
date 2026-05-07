# Evolution Log — python-sdk-config-pattern

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. frozen=True + slots=True + kw_only=True dataclass primary; pydantic.BaseModel(frozen=True) secondary; field(default_factory=...) for mutable defaults; from_url/from_env classmethods; __post_init__ for validation; dataclasses.replace for updates. Python pack analog of go-sdk-config-struct-pattern. Cited from conventions.yaml parameter_count and sdk-convention-devil-python C-4.
