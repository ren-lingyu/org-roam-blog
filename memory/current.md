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

The package source now lives at `lisp/org-roam-blog.el`. The flake uses the
personal-nixpkgs framework: `llib` inherits only the `tests` and `packages`
attributes, `lpkgs` imports the `pkgs/` overlays, and `specialArgs.src` is the
`./lisp` fileset. The public outputs are the `org-roam-blog` melpaBuild package
and the `emacs` wrapper, both built against the default Emacs package set
rather than an explicitly pinned Emacs version. The `emacsPackages` overlay is
exported. Checks use `tests.mkChecks` with `test-overlay.nix` leaves for ERT
and package-lint. Treefmt formatting is part of flake checks through
`treefmt.flakeCheck`. Read `memory/testing.md` for the check structure.

## Reading order and next action

Read `memory/publishing.md` for output/safety boundaries, `memory/export.md`
for metadata and extension contracts, and `memory/index.md` for index design
reasons and scope. Consult `memory/backlog.md` for unimplemented work and
blocking conditions; `memory/sources.md` states coverage and source limits.

The framework alignment is complete: package/check overlay migration,
repository formatting, the treefmt check gate, and README alignment are all
committed. `llib` was already narrowed to `tests` and `packages` during the
migration. No further alignment step remains.

Changelog work is complete and committed in three user-created project
commits: initial historical summary/manuscript, tagged-source manuscript
expansion, and the root Unreleased summary. The project worktree is clean.
The user confirms v0.1.0 was the first version and release. Local and public
GitHub v0.1.0 tag objects agree; the public release is not a draft or prerelease.
Historical content uses the tag's source, README and tests as primary evidence,
with existing platform notes as supplementary evidence. Detailed manuscripts
are the source of truth for later regeneration of existing and future platform
notes; platform writes and release tooling are outside this work.

`CHANGELOG.org` contains a historical v0.1.0 summary and a root-only
`TODO Unreleased`. `CHANGELOGS/v0.1.0.org` contains the complete standalone
manuscript, reorganized into Overview, Added (grouped capabilities, including
Nix packaging), Requirements (runtime and roots), and Limitations. First-release
Nix packaging describes the default package and Emacs 31 as they existed at
the tag. No current implementation changes are attributed to the first release.
The Unreleased summary instead covers source migration to `lisp/`, the default
Nix package renamed to `org-roam-blog`, a new independent `emacs` output,
personal-nixpkgs composition, Nixpkgs `melpaBuild`, default Emacs selection,
overlay/legacy package outputs and treefmt checking. No next version or release
time was selected, and no Unreleased detail file was created.

Editorial decisions: prioritize user-visible capabilities and actionable
migration/failure boundaries. Omit self-referential changelog additions, pure
formatting, ignore maintenance, lock refresh and check-runner internals from
the Unreleased inventory. Keep the wrapper addition with the output migration
while explicitly distinguishing rename from addition. Name `melpaBuild`
precisely to avoid implying MELPA publication. Detailed release notes need not
preserve the original platform-note structure. Compress exhaustive public
result keys, exact internal promotion order, cleanup mechanics and private
artifact lists; these belong in usage/reference documentation when useful.
The returned plist is a public interface, not private merely because its full
field list is omitted from release notes.

Validation was static tagged/current source, historical test-body and document
diff inspection, plus Git whitespace checks. A read-only token comparison found
the v0.1.0 and current publisher source token streams equal after ignoring
comments and whitespace outside strings; this is not an Emacs reader or runtime
test. No new ERT, Nix, formatting, deployment or publication run was performed.

The next task is the user's authorized README update, after first persisting
this changelog-completion checkpoint. Use the current committed HEAD as the
README implementation baseline, not v0.1.0. Audit existing README coverage
before editing, avoid duplication, and add or correct useful detailed public
interfaces, configuration semantics, result fields, publication sequencing,
partial-failure and staging behavior omitted from release notes. Preserve
accurate existing text and limit project edits to `README.org`. Project staging
and commits remain human operations. Generate requested commit-message claims
from the staged candidate only.

Use version identity and human-only state/time boundaries from the adopted
profile. The new historical CLOSED is derived from the tagged commit's UTC
committer time, `[2026-07-31 Fri 09:11]`. The user explicitly rejects adding
explanations in the root about CLOSED versus platform publication times.
Detailed manuscripts remain standalone: no root backlinks, generic reference
sections or source/comparison/release-page links. Neighboring org-roam-organize
and git-agent-workflow changelog histories were consulted as editorial examples;
their later navigation cleanups and missed interface-renaming corrections
justify applying these boundaries at initial creation. Project staging and
commits remain human operations. No new build, test or formatting run is
authorized or needed for these documentation changes.

## Validation limits

Historical source reports include focused/full ERT, flake checks and real
publication with user-observed parity; the Guile session records successful
path-flake checks and user-supplied ordinary flake success. For the migrated
flake, the user ran `nix flake check`; it evaluated the package, wrapper,
overlay, ERT and package-lint check derivations, devShells and the treefmt
formatter, and exited successfully with zero failures on x86_64-linux. The
run reported zero executed flake checks, so no check derivation was actually
built in that invocation; only evaluation was verified. That run predates the
treefmt check gate, which is now enabled but has not been freshly re-validated
by a reported `nix flake check`. Other systems were omitted. Reconstruction
performed source/DAG and GAW snapshot validation only, with no new project
build, test, deployment or release verification beyond the user check.
Missing original web chronology and cross-session predecessor context are
bounded in `memory/sources.md`.
