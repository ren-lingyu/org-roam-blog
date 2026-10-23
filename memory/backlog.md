# Backlog

Levels: current blocker, conditional blocker, non-blocking candidate.
No known implementation blocker to the agreed v0.1.0 feature scope remains
in the examined source. Historical validation limits remain in sources and
topic memory; they are not invented implementation tasks.

## Optional next capabilities

- Feed generation: discussed, not adopted; non-blocking candidate. Revisit
  when local generation has a concrete benefit over the existing external
  feed workflow and URL/metadata requirements are specified.
- Incremental/per-file publication: discussed, not adopted; non-blocking
  candidate. Revisit for measured full-build cost; cache invalidation and
  auxiliary-page dependencies need an explicit design.
- Publish-on-save/minor mode: deferred, not a release requirement;
  non-blocking candidate. Revisit for a concrete opt-in automation need.
- Stale-output diagnostics/cleanup: discussed, not implemented;
  non-blocking candidate. Revisit when obsolete outputs cause a problem;
  reporting and deletion are separate capabilities requiring ownership rules.
- Automatic bundle attachments: outside initial scope; non-blocking
  candidate only if explicitly reconsidered. Current explicit static rules
  remain the alternative.

Source: original Codex first-release boundary and follow-through discussions.
Do not turn these proposals into a promised next release.
