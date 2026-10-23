# Test infrastructure and validation boundaries

## Current runners

ERT and package-lint Nix derivations generate executable Guile runners with
`pkgs.replaceVarsWith`. The ERT runner invokes batch Emacs with the selected
test file. The lint runner recursively collects `.el` files, fails for an
empty set and passes arguments with `system*`, replacing shell/find/mapfile
assembly. Both establish a temporary HOME, propagate failure and create the
derivation output only after success. Scheme runner files are tracked via
the repository's test-file ignore exceptions.

## Historical evidence

The third requested session contains the four-file runner refactor, a typo
correction and successful `nix flake check path:. --no-update-lock-file`
(`all checks passed!`). Earlier sandbox-cache failure and Git-flake exclusion
of untracked `.scm` files were environmental/source-selection issues; the
path flake included them without changing the index. The user subsequently
provided a successful ordinary `nix flake check` result and requested a staged
commit review. Do not infer all-platform coverage or fresh execution here.

For ERT, do not put `tests/ert` on the load path: its `ert.el` can shadow the
built-in ERT library. Historical focused tests fixed that invocation issue;
it was not a concept-index implementation failure.

This reconstruction inspected current runner source and the relevant DAG,
but ran no project builds, ERT, lint, GUI publication or deployment. Earlier
50/54/58/61-test reports belong to different development stages, not one
revalidated current snapshot.
