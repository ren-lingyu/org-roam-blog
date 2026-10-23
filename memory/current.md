# Org-roam Blog current memory

## Recovery point

This is a retrospective reconstruction of the **native theindex implementation review** state, authored
at reconstruction time. It describes knowledge recoverable at this point,
not a claim that later work had already happened.

Native collector/generator plus the scoped HTML href mapper is adopted
and implemented. Custom generation, shadow symlinks and advice are retired
alternatives. The implementation commits were reviewed against explicit HEAD.

## Reading order

Read `memory/publishing.md` for purpose, output semantics and boundaries;
then the available topic memories relevant to the task. Read
`memory/backlog.md` for unfinished work and `memory/sources.md` for the
evidence horizon and its limitations. Paths are formal-worktree-relative.

## Validation and next action

The historical source reports 6 focused and 58 full ERT after this
implementation. The associated project snapshot grounds the implementation
review; README was unstaged and is not part of that exact code-review state.

Next: add missing headline-ID coverage, exercise the real publication
command, and finish release checks/documentation.
