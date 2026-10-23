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

## Unified multi-site configuration

- Status: discussed proposal, not adopted or implemented.
- Level: conditional blocker only if a new objective requires unified
  management of multiple independent publication targets. It does not block
  current single-site publishing or sequential dynamically bound calls.
- Motivation: avoid scattered per-site root/URL and export configuration
  when genuinely managing separate sites, rather than domains sharing output.
- Existing alternative: bind the relevant site variables around separate
  publish invocations; hosting handles aliases for the same output.
- Proposed direction: a site/target-level registry, not a URL per content
  rule. Suggested names such as `org-roam-blog-sites` are not public APIs.
- Reconsider when an explicit multiple-target use case establishes needed
  configuration, invocation and inheritance behavior. Do not predesign it
  merely because `site-url` exists.
- Source: the second Codex session's new site-url/multiple-domain discussion.

## Consuming the reserved site URL

- Status: no production caller; no implementation commitment.
- Level: conditional blocker for a future feature requiring absolute site
  URLs, such as canonical metadata or a locally generated feed.
- Next: define the consumer's requirements before expanding URL scope or
  claiming that the current variable affects publishing output.
