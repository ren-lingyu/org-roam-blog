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
and package-lint. Read `memory/testing.md` for the check structure.

## Reading order and next action

Read `memory/publishing.md` for output/safety boundaries, `memory/export.md`
for metadata and extension contracts, and `memory/index.md` for index design
reasons and scope. Consult `memory/backlog.md` for unimplemented work and
blocking conditions; `memory/sources.md` states coverage and source limits.

The framework packaging migration is committed through the `pkgs/` and
`tests/` overlay change. Remaining planned alignment steps are repository
formatting, the treefmt check gate, README alignment, and narrowing `llib`.
Resume by confirming the next step and current source state.

## Validation limits

Historical source reports include focused/full ERT, flake checks and real
publication with user-observed parity; the Guile session records successful
path-flake checks and user-supplied ordinary flake success. For the migrated
flake, the user ran `nix flake check`; it evaluated the package, wrapper,
overlay, ERT and package-lint check derivations, devShells and the treefmt
formatter, and exited successfully with zero failures on x86_64-linux. The
run reported zero executed flake checks, so no check derivation was actually
built in that invocation; only evaluation was verified. Other systems were
omitted. Reconstruction performed source/DAG and GAW snapshot validation
only, with no new project build, test, deployment or release verification
beyond that user check. Missing original web chronology and cross-session
predecessor context are bounded in `memory/sources.md`.
