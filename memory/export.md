# Metadata and scoped export customization

## Authority

Selection and node-level metadata come from the synchronized Org-roam DB.
`org-roam-blog-published-property` defaults to `PUBLISHED`, read from node
properties; modification time comes from DB `files.mtime`. Do not fall back
to reading `#+DATE` or filesystem timestamps. The publisher never inserts,
updates or infers publication time; local export does not mean deployment.

The adopted manifest fields are `:published-time` and `:modified-time`.
Earlier `:published-at`/`:modified` names were superseded. Sitemap date
display/sorting uses publication time, with undated entries after dated ones
under anti-chronological sorting.

## Export environment

`org-roam-blog-export-default` is one default object shared by content,
sitemap and theindex. `:template` merges native external option plists by
key; `:bindings` merges dynamic variable bindings by symbol, object values
overriding defaults. `:body` appends object functions after default functions.
Absent/nil/empty object body lists add nothing; nil does not disable defaults.

Each body function receives a context plist with the current `:body`,
backend, object and publication metadata and returns a string. Native body
filters run before the package adapter. Transformation precedes final HTML
template assembly; head/navigation/footer remain native options/bindings or
site configuration. Keep native hooks/filters and file options participating,
and restore dynamic state after export.

## Sitemap

`:visible-tags` is a strict display whitelist: absent/nil/empty means display
no tags. Projection affects neither selected pages nor content-rule matching.
The custom `:renderer` receives one context with prepared `:entries` and
`:config`, returning an Org source fragment. Entries are already selected,
sorted and projected. `:preamble` supplies static source before that fragment,
including optional `#+TITLE`, abstract or metadata. A renderer may return
supporting Org keywords such as `#+HTML_HEAD_EXTRA` together with its body.
Prefer returning such source rather than mutating export variables.

The same optional Org-source `:preamble` precedes the native index include.
Sitemap and theindex no longer have dedicated `:title`; sitemap `:generator`
was renamed/narrowed to `:renderer`. This public interface change requires
configuration migration, not aliases that silently preserve draft schemas.
Renderer and export share the object's scoped bindings. The renderer
consumes already sorted entries; personal renderers need not sort again.

The package supplies publication context and lifecycle, not a site theme.
Keep status markup, CSS, navigation, license and tag-filter UI in user config.
