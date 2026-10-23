# Publication model and design intent

## Purpose

Extract a reusable Org-roam-selected HTML publisher from a site-specific
Emacs configuration. The previous setup mixed database selection, global
Publish configuration/advice, HTML theme and save hooks. The package should
localize publication behavior without taking over content management.

Content rules select file-level (level-0) nodes matching **all** requested
tags. Rules provide export customization and independent sitemap/theindex
participation. A rule is not a page-role registry; the publisher does not
enforce homepage uniqueness or manage Org-roam capture/MOC/bundles.

## Canonical output and aliases

`org-roam-blog-directory` defines the source-relative path root;
`org-roam-blog-publish-directory` is the site output root;
`org-roam-blog-publish-store` is its relative canonical content directory.
Preserve source-relative hierarchy below the store and change `.org` to
`.html`. Public rule directories create optional HTML redirects using the
source basename; they do not create independent exported copies.

The isomorphic store preserves ordinary relative file-link relationships.
Relative redirect URLs also work when hosted below a deployment subpath.
Disk symlinks/server rewrites cannot change how browsers resolve relative
URLs at the requested alias. Duplicating pages with `<base>` complicates
fragment links and was rejected in favor of redirects for the first release.
No placeholder/slug expansion or per-rule output filename is needed.

## Configuration and boundaries

Use separate content, static, sitemap and theindex objects rather than one
heterogeneous registry. Pass native exporter options through `:template`;
retain normal Org hooks, filters and file-local export settings. Site-specific
navigation, CSS, license text and presentation belong to user configuration.

The manifest decides the publication set. Database synchronization, node
management, Git/deployment, arbitrary export backends and automatic bundle
attachment discovery are outside the first-release boundary. Referenced
unselected files need not be published automatically.

## Implemented publication core

The public publish operation checks configuration/capabilities, constructs a
database-selected manifest, enumerates explicit static inputs and builds the
combined output plan before publication writes. Reject conflicting targets,
unsafe paths and overlapping rule ownership rather than inventing precedence.
Generate content, sitemap and redirects into a unique staging directory;
only after successful generation copy static files directly to final targets
and promote generated files individually. A late failure can leave partial
output; report published targets and retain failed staging for diagnosis.
Success cleans staging. This is not an atomic website replacement.

`org-roam-blog-check` is a shape/root/capability check, not a full manifest
or static-file preflight. Full output planning belongs to publish. No stale
output deletion or durable publication cache is promised.

Export saved files. Ordinary relative `file:` links benefit from the mirrored
store. Experiments exposed upstream `id:`/fragment behavior; the package
does not install a generalized rewrite/workaround for ordinary content links.
Keep that distinct from the later concept-index integration problem.

Theindex configuration exists but generation is not implemented at this
point; enabling it fails before publication writes.

## Sitemap display and roots

Sitemap uses the explicit tag-display whitelist described in
`memory/export.md`. Its metadata comes from the manifest, not a second
directory scan. Source, publication and explicitly configured temporary roots
must already exist as real non-symlink directories; do not silently create
the publication root. Internal generated store subdirectories may be created.
The store default is now `_store`, avoiding the implication of raw Org output.
