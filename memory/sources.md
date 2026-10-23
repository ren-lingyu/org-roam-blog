# Evidence and reconstruction boundaries

## Sources used for this state

The original Codex discussion is session
`019fadeb-10b0-7d90-943e-a8dc72977f57` in the user's Codex session archive.
Record numbers below are one-based JSONL record positions in that source.
They locate evidence; they are not a replay log or checkpoint identifiers.

Covered scope at this recovery point: native generator/filter decision, probes, implementation and exact implementation-commit review.

Records 5213–5394 replace the shadow approach with native generation
plus a scoped post-transcoding mapper and validate its boundaries. Records
5404–5593 cover implementation and commit review; 5540 reports 6 focused
and 58 full ERT. Tool output at 5585 explicitly identifies the reviewed HEAD
as `afb87383fe95ef98dcd2d355a36d65965d8d5d93`, with README still unstaged.
This supports the code implementation review context, not a claim that the
unstaged documentation or every earlier experiment equals that commit.

## Interpretation

Historical tool output and user reports establish what was observed or
reported then. Reconstruction itself has not rerun project builds, ERT,
GUI publishing or deployment. A staged/dirty tree is not an exact committed
project snapshot. The project DAG establishes commit order, not the exact
state used by every experiment. Omit unsupported project-parent claims.

Material is distilled rather than copied from transcripts. Personal site
content, identifying configuration and irrelevant machine details are not
needed to resume work. Raw conversations are not archived in GAW.
