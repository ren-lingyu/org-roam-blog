# Concept-index work: native generator and shadow-source experiment

## Objective

Retain manifest-selected `#+INDEX` membership, native `!` hierarchy and
file/headline destinations. Sitemap is a page listing; theindex is a concept
index. DB node metadata and positional source export annotations have
different authority boundaries; only selected files are parsed/exported.

## Experimental result and provisional choice

Reuse native `org-publish-collect-index`,
`org-publish-index-generate-theindex` and ox-html rather than duplicate native
sorting/grouping. Probes used absolute manifest `:include`, `:exclude ".*"`,
dynamic in-memory Publish cache, temporary timestamp location and local ID
locations. A store-shaped shadow `.org` symlink tree lets ox-html inspect
actual source content while computing published-path-relative links.

The source reports successful file-level, CUSTOM_ID, ID and ordinary-headline
resolution with this approach. At this recovery point shadow-source native
generation is provisionally favored; this is a tested design, not completed
package implementation. No advice is required by the shadow approach.

## Open costs

Separate private work (`theindex.org`, `.inc`, timestamp data and shadow
sources) from promoted HTML. Mirror the configured index output directory
inside the shadow layout, or relative links will be wrong. Symlink support,
file handlers, filesystem/platform behavior and ownership-safe cleanup add
independent constraints. The user questions whether this cost is justified.

Custom fragment guessing already proved fragile because ox-html needs real
Org targets. Local advice and removing other users' advice are alternatives
under discussion, not an adopted package dependency.
