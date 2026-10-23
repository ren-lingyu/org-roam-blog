# Native concept-index publication

## Adopted pipeline

Use manifest-selected content rules with `:theindex t`. During ordinary
content export native `org-publish-collect-index` fills one dynamically bound
in-memory Publish cache containing real source paths. A private Publish
project uses absolute manifest `:include` with `:exclude ".*"` and native
`org-publish-index-generate-theindex`. Generated `theindex.org`, `.inc` and
timestamp work live in private staging, not the source tree or public output.

Let normal Org/ox-html inspect real sources and resolve file, ID, CUSTOM_ID
and ordinary-headline destinations. A locally scoped
`org-export-filter-link-functions` adapter then maps exact known source href
bases to store href bases, preserving fragments and unrelated links. Its
input is a transcoded HTML link string, not a raw URL or theindex.inc AST.
Account for attribute escaping and encode the replacement store URL at the
appropriate stage; do not pre-encode the lookup key speculatively.

The final HTML participates in output planning, conflict checks, staging and
promotion. Public index options include `:path`, optional Org-source `:preamble`,
`:template`, `:bindings` and `:body`. Put `#+TITLE` in `:preamble` when wanted;
the dedicated `:title` field has been removed. The public publish driver now enables index generation; an earlier
unconditional not-implemented rejection was removed.

## Reasons and scope

Native generation retains upstream sorting, grouping, `!` hierarchy and
position-sensitive anchors. Rewriting .inc links to HTML before transcoding
loses the Org source needed to resolve ordinary headlines. The local filter
changes routing only after native semantics have been resolved.

The custom generator was superseded because it duplicates upstream logic;
shadow symlinks were superseded because of filesystem/platform and cleanup
costs. Global/local advice and bypassing other users' advice were explored
but not adopted. No shadow tree, global project registration, persistent
Publish cache or schema extension is required by the adopted implementation.

Selection/node publication metadata stay DB-backed. `#+INDEX` is a selected
document's positional export annotation. This distinction does not allow
scanning unselected content or installing a companion metadata database.
The scoped index mapper does not promise generalized ordinary-content `id:`
rewriting or repair upstream fragment behavior in other pages.

## Historical verification

The source reports 6/6 focused index ERT and 58/58 full ERT plus package-lint
and flake checks after implementation. Later evidence adds explicit headline-ID ERT and a real publish run
whose index output was promoted without diagnostics and whose successful
staging was cleaned. The user reports parity with the prior site output.
Final preflight/capability work reports 61 ERT. These are later historical
results, not results rerun during reconstruction.
