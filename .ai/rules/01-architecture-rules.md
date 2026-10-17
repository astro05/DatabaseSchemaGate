# 01 — Architecture Rules

## Layers (`src/`)

New project: use the layers below as written. Existing project: keep its current layout. Map its folders onto these layers in SPEC-001 §2.1, apply the dependency direction to new code, and do not restructure existing code unless a spec asks for it.

| Layer | Contains | May import | Must not |
|---|---|---|---|
| `src/domain/` | Entities, value objects, pure business rules | nothing outside `domain/` (plus the language stdlib) | Do I/O, read clocks or randomness directly, or import a framework |
| `src/core/` | Use cases / application services; **ports** (interfaces) for anything external | `domain/` | Import `data/` or `interfaces/`; know about transport or storage details |
| `src/data/` | **Adapters** that implement core ports: DB, HTTP clients, queues, files | `core/` (ports), `domain/` | Contain business rules |
| `src/interfaces/` | Entrypoints: HTTP handlers, CLI, UI, jobs; the composition root | `core/`, `domain/`; `data/` **only** in the composition root | Contain business rules; return raw internal errors |

Dependencies always point inward: `interfaces → core → domain`, and `data → core/domain`.
A dependency that points outward is a defect.

## Module boundaries

- One spec owns one module. The spec's §2.1 names the paths it owns.
- A module talks to another module only through that module's public API, as specified in the other module's spec §3. Never reach into another module's internals.
- A new cross-module dependency must be listed in the spec's `Dependencies` and in `SPEC-INDEX.md`.

## Safety

- **Validate at trust boundaries.** Parse and validate all external input in `interfaces/` (or the adapter in `data/`) into typed domain values. Never trust input that has not been validated.
- **Secrets** come from environment or a secret manager. They never appear in code, specs, tests, logs, or commits.
- **Never log PII or credentials.** Log IDs, not payloads.
- **All external I/O has a timeout** and a defined failure mode (listed in spec §4.2).
- **Retried operations must be idempotent**, or the spec must say why they can't be.
- **Least privilege:** every credential, token, and DB role gets the minimum scope it needs.
- **Fail closed:** when an authorization check errors, deny access.

## Decisions

Any choice that is hard to reverse needs a row in the owning spec's §2.4 Decisions **before** implementation. That covers: frameworks, datastores, protocols, new runtime dependencies, sync vs. async, and caching.
