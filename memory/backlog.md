# Backlog

Levels describe impact on the recovery point's adopted objective, not a
promise or implementation priority: **current blocker**, **conditional
blocker**, or **non-blocking candidate**. Rejected approaches belong in
topic memory rather than becoming tasks automatically.

## Publication-core follow-through

- Status: implementation exists; inspect later evidence before calling the
  complete release finished.
- Level: conditional blocker for release readiness if metadata, export
  isolation or representative real-site behavior remains unverified.
- Next: settle database-backed publication time and localized customization;
  perform meaningful regression checks rather than repair upstream links.

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
