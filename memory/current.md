# Org-roam Blog current memory

## Supported current state

The independent publisher selects level-0 Org-roam nodes using all-of tag
rules, mirrors source-relative HTML into `_store`, creates optional relative
redirects and publishes manifest-driven sitemap, native concept index and
explicit static resources. It supplies localized template/bindings/body
customization rather than a site theme or content/deployment manager.

Node publication metadata comes from the synchronized DB. `PUBLISHED` is
user-managed and read-only to the publisher. Sitemap tag display is an
explicit whitelist. The final generated-page API uses optional Org-source
`:preamble` and sitemap `:renderer`. Theindex uses native collector/generator
with a scoped source-to-store HTML link mapper, without advice or shadow
symlinks. Ordinary content-link semantics remain Org's responsibility.

Full publication preflight precedes generated staging and direct static
copies. Per-file promotion can leave partial output after failure; preserve
diagnostics/staging rather than claim transactional website replacement.
There is no automatic stale-output cleanup or attachment discovery.

`site-url` is reserved and validated but does not affect current production
output. Multiple independent targets can use separate locally bound calls;
a unified target registry remains a conditional backlog proposal.

The local tagged v0.1.0 API predates current main's lock/ignore updates and
Guile test runners. Read `memory/testing.md` for the runner behavior and
validation evidence. No known implementation blocker to the agreed release
feature scope remains in these inputs; no next feature has been selected.

## Reading order and next action

Read `memory/publishing.md` for output/safety boundaries, `memory/export.md`
for metadata and extension contracts, and `memory/index.md` for index design
reasons and scope. Consult `memory/backlog.md` for unimplemented work and
blocking conditions; `memory/sources.md` states coverage and source limits.

Reconstruction is complete for the requested available inputs. Resume by
confirming the new task and current source state, then select only the
relevant topic/backlog material. Do not restart retired index approaches or
treat optional proposals as an agreed next milestone.

## Validation limits

Historical source reports include focused/full ERT, flake checks and real
publication with user-observed parity; the Guile session records successful
path-flake checks and user-supplied ordinary flake success. Reconstruction
performed source/DAG and GAW snapshot validation only, with no new project
build, test, deployment or external release verification. Missing original
web chronology and cross-session predecessor context are bounded in sources.
