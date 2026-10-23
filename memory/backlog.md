# Backlog

Levels describe impact on the recovery point's adopted objective, not a
promise or implementation priority: **current blocker**, **conditional
blocker**, or **non-blocking candidate**. Rejected approaches belong in
topic memory rather than becoming tasks automatically.

## Representative migration validation

- Status: core metadata and scoped export architecture implemented.
- Level: conditional blocker for confidence in replacing the previous site
  configuration; architecture alone is not a real-site publication result.
- Next: migrate a representative configuration and inspect staging, public
  targets and presentation without moving theme policy into the package.

## Theindex

- Status: discussed, optional for the initial release at this point.
- Level: non-blocking candidate; revisit when concept-index compatibility
  becomes an explicit release requirement.
- Need: reuse author-supplied `#+INDEX` semantics, including positional
  entries where feasible; do not silently substitute a title-only sitemap.

## Deferred product extensions

- Feed generation, incremental publishing, publish-on-save and stale-output
  management are non-blocking candidates, not accepted milestones.
- Reconsider each only for a concrete user need and an explicit output,
  cache, attachment or deletion policy. Existing external feed generation
  is a possible alternative; no deployment integration is assumed.
