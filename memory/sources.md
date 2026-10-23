# Evidence and reconstruction boundaries

## Sources used for this state

The original Codex discussion is session
`019fadeb-10b0-7d90-943e-a8dc72977f57` in the user's Codex session archive.
Record numbers below are one-based JSONL record positions in that source.
They locate evidence; they are not a replay log or checkpoint identifiers.

Covered scope at this recovery point: the entire requested Codex horizon, fork-only additions, runner refactor and separate web-summary integration.

The original archive contains 6,823 records spanning extraction design,
incremental implementation, link limits, tag policy, metadata, export APIs,
real configuration migration, index experiments/implementation, release
preflight and final preamble/renderer alignment. Its ten compaction records
occur alongside earlier retained records; reconstruction did not substitute
only the compacted tail for the original discussion. Formatting and commit-
message intervals were examined; reusable semantic lessons were retained
where relevant, without checkpointing each formatting or staging action.

The second session, `019fd0d1-0aba-7722-9f3b-535e0a12caa0`, contains the
inherited discussion plus site-url and
multiple-domain analysis. Its first 330 user messages match the original;
the fork-only analysis is retained without duplicating development history.

The third session is `01a089e7-2f3d-7b62-ac1d-f429b6f3e5ba` (267 records).
It covers Guile runners, replacement-variable wiring, source inclusion and
successful path-flake checks. Its opening refers to an earlier session not
included in the requested inputs; that cross-project context is not recovered.
The local changes, constraints and test results remain supported within the
requested session. It ends with staged-message review, not a recorded commit.

`gaw-input.md` is a user-provided retrospective summary of a separate ChatGPT
web discussion, not a summary of these Codex sessions. Its original web
transcript and exact discussion chronology are unavailable here. Its useful
architectural reasoning is integrated as supplementary explanation; claims
about released behavior are checked against local source/tag, not treated
as earlier Codex observations or independently reproduced release evidence.

The local DAG orders the tagged API before lock-input refresh, Scheme ignore
exceptions and Guile runners. Current source inspection was performed on
`778d410f55710bca22a2d84a301a72b7b099b874`; the local `v0.1.0` tag resolves to
`2c7140eab0d22a7a7706e3b26f3fe1628fab093f`. These locators support independent
source lookup, not semantic checkpoint IDs or a parallel graph inventory.

## Interpretation

Historical tool output and user reports establish what was observed or
reported then. Reconstruction itself has not rerun project builds, ERT,
GUI publishing or deployment. A staged/dirty tree is not an exact committed
project snapshot. The project DAG establishes commit order, not the exact
state used by every experiment. Omit unsupported project-parent claims.

Material is distilled rather than copied from transcripts. Personal site
content, identifying configuration and irrelevant machine details are not
needed to resume work. Raw conversations are not archived in GAW.

## Retention and current interpretation

Candidate project-parent ancestor closures were screened through Git object
inspection. No credential value/private-key pattern was found by that scan;
it is not a proof of universal secret absence. Personal absolute paths are
not classified as sensitive by the user. Public source authorship metadata
is retained with associated project history; memory prose omits unnecessary
personal paths/site details. Exact parents identify observed contexts, not
approval or test certificates. Earlier uncertain dirty-tree provenance was
not filled in from nearby commits.

Coverage is complete for the requested available inputs, with the missing
original web transcript and third session's external predecessor explicitly
bounded above. Proposed extensions do not become accepted tasks because a
summary lists them. No raw source archive, Auxiliary or lifecycle rewrite
was needed. Future work starts from current memory and backlog, not from
draft TODOs or superseded snapshot plans.
