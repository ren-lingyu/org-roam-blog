# Concept-index work: collector and custom generator plan

## Objective and authority boundary

Theindex is a concept/location index, distinct from the sitemap's published
page list. The user now wants it in v0.1.0. Preserve native `#+INDEX` terms,
`!` hierarchy and file/headline locations rather than replace it with titles.
The manifest's `:theindex t` rules alone determine participating sources.

## Current plan

During ordinary selected-content export, attach native
`org-publish-collect-index` to a dynamically bound in-memory
`org-publish-cache`. A custom generator would consume `(TERM FILE PARENT)`
records, organize terms and map source files to canonical store HTML. Its
Org output would use normal export customization and staging/promotion.
Avoid source-side generated files and persistent timestamp/cache artifacts.

This plan intentionally avoids native `org-publish-index-generate-theindex`
at this point. It is not the implemented generator. ID/CUSTOM_ID and ordinary
headline targets still require validation: changing an Org source target to
HTML too early may lose the information ox-html needs to resolve fragments.

DB selection remains authoritative. `#+INDEX` is document-internal positional
export information, unlike node-level publication metadata. Collecting it
while exporting already selected sources does not authorize broader scans.
