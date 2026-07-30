;;; org-roam-blog.el --- Publish an Org-roam based blog -*- lexical-binding: t; -*-

;; Copyright (C) 2026 aRenCoco

;; Author: aRenCoco
;; Maintainer: aRenCoco
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (org "9.5") (org-roam "2.3.1"))
;; Keywords: outlines, hypermedia
;; URL: https://github.com/ren-lingyu/org-roam-blog
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Org-roam Blog publishes blog content selected from the Org-roam database
;; while preserving standard Org export behavior.  Export templates and
;; dynamically scoped variable bindings customize generated documents.  A
;; context-aware body pipeline supports publication-specific transformations
;; without permanently changing Org or export-backend global state.
;; Link resolution, including the HTML anchors emitted for `id:' links,
;; remains the responsibility of Org and the selected export backend.
;;
;; The implementation and user-facing configuration are under development.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'org-id)
(require 'ox)
(require 'ox-html)
(require 'ox-publish)
(require 'org-roam)
(require 'subr-x)
(require 'url-parse)
(require 'url-util)

(defgroup org-roam-blog
  nil
  "Publish an Org-roam database selection as a static HTML blog."
  :group 'org-roam
  :prefix "org-roam-blog-")

(defcustom org-roam-blog-directory
  nil
  "Root directory containing Org files eligible for blog publication.

The Org-roam database is the only source used to select files.  This
directory limits that selection and provides the base from which
source-relative store paths are calculated.  The value must name an
existing absolute directory and must not be a symbolic link.
Org-roam Blog does not synchronize the Org-roam database."
  :type '(choice (const :tag "Not configured" nil)
                 directory)
  :group 'org-roam-blog)

(defcustom org-roam-blog-publish-directory
  nil
  "Root directory for all published website files.

Content store files, redirects, sitemap, theindex, and static files
must resolve below this directory.  The value must name an existing
absolute directory and must not be a symbolic link.  Org-roam Blog
does not create this publication root."
  :type '(choice (const :tag "Not configured" nil)
                 directory)
  :group 'org-roam-blog)

(defcustom org-roam-blog-publish-store
  "_store"
  "Directory below `org-roam-blog-publish-directory' for content.

The value is a non-empty relative directory name.  It may name a
missing directory, which publication creates as needed.  When it
already exists, it must be a non-symlink directory below
`org-roam-blog-publish-directory'.  Published Org files mirror their
paths relative to `org-roam-blog-directory' below this directory."
  :type 'string
  :group 'org-roam-blog)

(defcustom org-roam-blog-site-url
  nil
  "Absolute public URL corresponding to the publish directory.

The value may be nil when the final website URL is unknown.  A
non-nil value must use HTTP or HTTPS, contain no query or fragment,
and end with a slash.  It may include a deployment subpath, such as
\"https://example.org/blog/\".

Org-roam Blog prefers relative URLs for internal links and redirects.
This value is reserved for output that requires an absolute URL, such
as canonical metadata or a future feed."
  :type '(choice (const :tag "Unknown" nil)
                 string)
  :group 'org-roam-blog)

(defcustom org-roam-blog-temporary-directory
  nil
  "Parent directory for per-publication staging directories.

Nil means to use `temporary-file-directory'.  A non-nil value must
name an existing absolute directory and must not be a symbolic link.
Org-roam Blog does not create this staging root.  Each publication
creates a unique child directory for generated content, sitemap,
theindex, and redirects.  Static files do not pass through this
staging directory."
  :type '(choice (const :tag "Emacs temporary directory" nil)
                 directory)
  :group 'org-roam-blog)

(defcustom org-roam-blog-export-default
  nil
  "Default configuration applied to generated Org documents.

The supported schema is:

  (:template PLIST :bindings ALIST :body FUNCTION-LIST)

TEMPLATE is a plist of external options accepted by Org Export and
the selected backend.  Org-roam Blog does not interpret or whitelist
exporter-specific option keys.  An object's `:template' shallowly
overrides this default, including explicitly present nil values.

BINDINGS is an alist keyed by variable symbols.  Each binding is
active only while Org-roam Blog prepares and exports one generated
Org document, and the previous dynamic value is restored afterwards.
An object's `:bindings' overrides entries with the same symbol,
including explicitly present nil values.

BODY is a list of functions applied in order after the effective
native Org body filters.  Each function receives one context plist
and must return the replacement body string.  Object body functions
are appended after these defaults.  A missing, nil, or empty object
value adds no functions and therefore only inherits this list.

The context contains `:kind', `:body', `:backend', `:export-info',
`:entry', and `:config'.  It also contains the entry convenience
fields `:title', `:source', `:source-relative', `:content-name',
`:tags', `:published-time', `:modified-time', `:store-relative', and
`:redirect-relative'.  `:entry' and its convenience fields are nil
for generated documents without a current content entry.  Treat the
context and referenced configuration data as read-only."
  :type 'plist
  :group 'org-roam-blog)

(defcustom org-roam-blog-published-property
  "PUBLISHED"
  "Org-roam node property containing the publication time.

The value is a non-empty property name.  Org-roam Blog reads this
property from the Org-roam database and stores its value as manifest
metadata.  The package never creates, updates, or infers this
property, because a local export does not establish when content was
actually deployed."
  :type 'string
  :group 'org-roam-blog)

(defcustom org-roam-blog-content
  nil
  "Rules selecting Org-roam files and describing their publication.

Each element is a plist with this schema:

  (:name NAME :tags TAGS :directory DIRECTORY
   :sitemap BOOLEAN :theindex BOOLEAN :template PLIST
   :bindings ALIST :body FUNCTION-LIST)

NAME is a unique non-empty string.  TAGS is a non-empty list of
strings, all of which must occur on a level-0 Org-roam node.
DIRECTORY is nil or a directory relative to
`org-roam-blog-publish-directory' in which a redirect is generated.
The two boolean fields select generated indexes.  TEMPLATE, BINDINGS,
and BODY extend `org-roam-blog-export-default' according to their
documented merge rules.

A file matching more than one rule is an unsupported configuration
and will be diagnosed before publication."
  :type '(repeat plist)
  :group 'org-roam-blog)

(defcustom org-roam-blog-static
  nil
  "Mappings of static source directories to publication directories.

Each element has the form:

  (:source DIRECTORY :directory RELATIVE-DIRECTORY
   :extensions REGEXP-OR-NIL)

Static files are copied directly to their final destinations with
`org-publish-attachment'; they do not pass through the generated
content staging directory."
  :type '(repeat plist)
  :group 'org-roam-blog)

(defcustom org-roam-blog-sitemap
  '(:enable nil)
  "Configuration for the generated sitemap.

The supported schema is:

  (:enable BOOLEAN :path RELATIVE-FILE :title STRING :sort SYMBOL
   :visible-tags TAGS-OR-NIL
   :generator FUNCTION-OR-NIL :template PLIST :bindings ALIST
   :body FUNCTION-LIST)

Only tags explicitly listed in `:visible-tags' are displayed by the
sitemap.  A missing or nil value displays no tags.  This whitelist
never selects content.  When non-nil, `:generator' receives one plist
containing `:entries' and `:config', and must return a complete Org
source string.  The entries have already been selected, sorted, and
projected through `:visible-tags'.  An empty returned string is valid.
TEMPLATE, BINDINGS, and BODY extend `org-roam-blog-export-default'."
  :type 'plist
  :group 'org-roam-blog)

(defcustom org-roam-blog-theindex
  '(:enable nil)
  "Configuration for the optional generated Org index.

The supported schema is:

  (:enable BOOLEAN :path RELATIVE-FILE :title STRING
   :template PLIST :bindings ALIST :body FUNCTION-LIST)

When disabled, capabilities needed only for index collection are not
required.  Index collection reuses `org-publish-collect-index' with
an in-memory, dynamically bound Org Publish cache.  Generation reuses
`org-publish-index-generate-theindex' and the standard HTML exporter.
Only manifest entries whose content rule has non-nil `:theindex' are
included.

The generated Org source and include file are private staging
artifacts.  The final HTML file is written at `:path'.  Links generated
from real source paths are mapped to their corresponding publication
store URLs by a local HTML link filter; fragments remain under Org's
control.  TEMPLATE, BINDINGS, and BODY extend
`org-roam-blog-export-default'.  No advice, symbolic links, persistent
Publish cache, or global Publish project registration is used."
  :type 'plist
  :group 'org-roam-blog)

(defconst org-roam-blog--content-keys
  '(:name :tags :directory :sitemap :theindex :template :bindings :body))

(defconst org-roam-blog--export-default-keys
  '(:template :bindings :body))

(defconst org-roam-blog--static-keys
  '(:source :directory :extensions))

(defconst org-roam-blog--default-static-extensions
  "css\\|js\\|png\\|svg\\|jpg\\|jpeg\\|gif\\|webp\\|ico\\|pdf\\|woff\\|woff2"
  "Default regexp matching static file extensions.")

(defconst org-roam-blog--sitemap-keys
  '(:enable :path :title :sort :visible-tags :generator :template :bindings :body))

(defconst org-roam-blog--theindex-keys
  '(:enable :path :title :template :bindings :body))

(defvar org-roam-blog--body-context
  nil
  "Base context for the current Org-roam Blog body pipeline.")

(defvar org-roam-blog--body-functions
  nil
  "Body functions for the current Org-roam Blog export.")

(defvar org-roam-blog--collect-theindex
  nil
  "Non-nil while content export should collect native index entries.")

(defvar org-roam-blog--theindex-href-map
  nil
  "Alist mapping native theindex link targets to publication URLs.

Keys are the unencoded href values observed by Org's HTML link-filter
stage, without fragments.  Values are encoded publication-relative
URLs.  This variable is dynamically bound only while exporting the
generated theindex document.")

(defun org-roam-blog--diagnostic (severity subject message)
  "Return a diagnostic with SEVERITY, SUBJECT, and MESSAGE.

SEVERITY is normally `error' or `warning'.  SUBJECT identifies the
variable, rule, or capability being checked.  MESSAGE is a
human-readable explanation."
  (list :severity severity :subject subject :message message))

(defun org-roam-blog--plist-p (value)
  "Return non-nil when VALUE is a proper even-length plist."
  (and (listp value)
       (proper-list-p value)
       (cl-evenp (length value))))

(defun org-roam-blog--bindings-p (value)
  "Return non-nil when VALUE is an alist keyed by variable symbols."
  (and (proper-list-p value)
       (cl-every (lambda (binding)
                   (and (consp binding)
                        (symbolp (car binding))))
                 value)))

(defun org-roam-blog--function-list-p (value)
  "Return non-nil when VALUE is a proper list of functions."
  (and (proper-list-p value)
       (cl-every #'functionp
                 value)))

(defun org-roam-blog--unknown-keys (plist allowed)
  "Return keys in PLIST that do not occur in ALLOWED."
  (let (unknown)
    (while plist
      (unless (memq (car plist) allowed)
        (push (car plist) unknown))
      (setq plist (cddr plist)))
    (nreverse unknown)))

(defun org-roam-blog--string-list-p (value &optional nonempty)
  "Return non-nil when VALUE is a string list.

When NONEMPTY is non-nil, require at least one string."
  (and (listp value)
       (or (not nonempty) value)
       (cl-every #'stringp value)))

(defun org-roam-blog--absolute-directory-p (value)
  "Return non-nil when VALUE names an absolute directory path.

The directory need not exist."
  (and (stringp value)
       (not (string-empty-p value))
       (file-name-absolute-p value)))

(defun org-roam-blog--existing-real-directory-p (value)
  "Return non-nil when VALUE names an existing non-symlink directory."
  (and (org-roam-blog--absolute-directory-p value)
       (file-directory-p value)
       (not (file-symlink-p (directory-file-name (expand-file-name value))))))

(defun org-roam-blog--relative-path-p (value &optional allow-dot)
  "Return non-nil when VALUE is a safe relative path.

When ALLOW-DOT is non-nil, accept \".\".  Empty and absolute paths,
and paths containing a parent-directory component, are rejected."
  (and (stringp value)
       (not (string-empty-p value))
       (not (file-name-absolute-p value))
       (or allow-dot (not (string= value ".")))
       (not (member ".." (split-string value "/" t)))))

(defun org-roam-blog--relative-file-p (value)
  "Return non-nil when VALUE is a safe relative file path."
  (and (org-roam-blog--relative-path-p value)
       (not (string-suffix-p "/" value))))

(defun org-roam-blog--encode-url-path (path)
  "Encode each segment of relative URL PATH while preserving slashes."
  (mapconcat #'url-hexify-string (split-string path "/" nil) "/"))

(defun org-roam-blog--relative-url (from-file to-file)
  "Return an encoded relative URL from FROM-FILE to TO-FILE.

Both arguments are paths relative to the publication root."
  (unless (and (org-roam-blog--relative-file-p from-file)
               (org-roam-blog--relative-file-p to-file))
    (error "Unsafe relative URL paths: %S and %S"
           from-file
           to-file))
  (org-roam-blog--encode-url-path
   (file-relative-name to-file (file-name-directory from-file))))

(defun org-roam-blog--site-url (relative-path)
  "Return an absolute site URL for RELATIVE-PATH.

Signal an error when `org-roam-blog-site-url' is nil or
RELATIVE-PATH is unsafe.  Internal links should remain relative unless
an absolute URL is explicitly required."
  (unless org-roam-blog-site-url
    (error "`org-roam-blog-site-url' is not configured"))
  (unless (org-roam-blog--relative-file-p relative-path)
    (error "Unsafe relative URL path: %S"
           relative-path))
  (concat org-roam-blog-site-url
          (org-roam-blog--encode-url-path relative-path)))

(defun org-roam-blog--replace-extension (path extension)
  "Return PATH with its extension replaced by EXTENSION."
  (concat (file-name-sans-extension path) extension))

(defun org-roam-blog--path-inside-p (path directory)
  "Return non-nil when existing PATH is inside existing DIRECTORY.

Both values are resolved with `file-truename', so a symlink cannot
make a source appear to be within the configured directory."
  (let ((true-path (file-truename path))
        (true-directory
         (file-name-as-directory (file-truename directory))))
    (string-prefix-p true-directory true-path)))

(defun org-roam-blog--output-path (relative-path)
  "Expand safe RELATIVE-PATH below the publication directory."
  (unless (org-roam-blog--relative-file-p relative-path)
    (error "Unsafe relative output path: %S"
           relative-path))
  (expand-file-name relative-path org-roam-blog-publish-directory))

(defun org-roam-blog--valid-site-url-p (value)
  "Return non-nil when VALUE is a valid `org-roam-blog-site-url'."
  (or (null value)
      (and (stringp value)
           (not (string-match-p "[?#]" value))
           (condition-case nil
               (let ((url (url-generic-parse-url value)))
                 (and (member (url-type url) '("http" "https"))
                      (stringp (url-host url))
                      (not (string-empty-p (url-host url)))
                      (string-suffix-p "/" (url-filename url))))
             (error nil)))))

(defun org-roam-blog--merge-template (base override)
  "Shallowly merge template plist OVERRIDE over BASE.

An explicitly present nil value in OVERRIDE replaces the value from
BASE.  Neither argument is modified."
  (let ((result (copy-sequence base))
        (tail override))
    (while tail
      (setq result (plist-put result (car tail) (cadr tail))
            tail (cddr tail)))
    result))

(defun org-roam-blog--merge-bindings (base override)
  "Merge dynamic binding alist OVERRIDE over BASE by variable symbol.

An explicitly present nil value in OVERRIDE replaces the value from
BASE.  Neither argument is modified."
  (let ((result (copy-tree base)))
    (dolist (binding override)
      (if-let* ((existing (assq (car binding)
                                result)))
          (setcdr existing
                  (cdr binding))
        (setq result (append result
                             (list (copy-tree binding))))))
    result))

(defun org-roam-blog--export-configuration (object)
  "Return effective export configuration for OBJECT.

OBJECT is a content rule, sitemap configuration, or theindex
configuration.  Return a plist containing merged `:template',
`:bindings', and `:body' values.  Default body functions precede
OBJECT's functions.  Neither configuration is modified."
  (list :template (org-roam-blog--merge-template (plist-get org-roam-blog-export-default
                                                            :template)
                                                 (plist-get object
                                                            :template))
        :bindings (org-roam-blog--merge-bindings (plist-get org-roam-blog-export-default
                                                            :bindings)
                                                 (plist-get object
                                                            :bindings))
        :body (append (copy-sequence (plist-get org-roam-blog-export-default
                                                :body))
                      (copy-sequence (plist-get object
                                                :body)))))

(defun org-roam-blog--call-with-export-bindings (bindings function)
  "Call FUNCTION with dynamic variable BINDINGS.

BINDINGS is an alist mapping variable symbols to values.  Restore all
previous dynamic values when FUNCTION returns or signals an error."
  (cl-progv (mapcar #'car
                    bindings)
      (mapcar #'cdr
              bindings)
    (funcall function)))

(defun org-roam-blog--make-body-context (kind entry config)
  "Return a body-function context for KIND, ENTRY, and CONFIG."
  (list :kind kind
        :entry entry
        :config config
        :title (plist-get entry
                          :title)
        :source (plist-get entry
                           :source)
        :source-relative (plist-get entry
                                    :source-relative)
        :content-name (plist-get entry
                                 :content-name)
        :tags (plist-get entry
                         :tags)
        :published-time (plist-get entry
                                   :published-time)
        :modified-time (plist-get entry
                                  :modified-time)
        :store-relative (plist-get entry
                                   :store-relative)
        :redirect-relative (plist-get entry
                                      :redirect-relative)))

(defun org-roam-blog--body-filter (body backend export-info)
  "Apply the current Org-roam Blog body pipeline.

BODY, BACKEND, and EXPORT-INFO have the meanings defined by
`org-export-filter-body-functions'.  Each configured function
receives a context plist and must return the body passed to the next
function."
  (dolist (function org-roam-blog--body-functions
                    body)
    (setq body (funcall function
                        (append (list :body body
                                      :backend backend
                                      :export-info export-info)
                                org-roam-blog--body-context)))
    (unless (stringp body)
      (error "Org-roam Blog body function %S returned a non-string value"
             function))))

(defun org-roam-blog--export-to-file (output template body-functions context)
  "Export the current Org buffer as HTML to OUTPUT.

TEMPLATE contains external export options.  Append the Org-roam Blog
BODY-FUNCTIONS adapter after the effective native body filters and
pass CONTEXT to each body function.  Do not modify global filter
state."
  (let ((org-roam-blog--body-context context)
        (org-roam-blog--body-functions body-functions)
        (org-export-filter-body-functions
         (if body-functions
             (append org-export-filter-body-functions
                     (list #'org-roam-blog--body-filter))
           org-export-filter-body-functions)))
    (org-export-to-file 'html output nil nil nil nil template)))

(defun org-roam-blog--html-href-range (html)
  "Return the value range of the first href attribute in HTML.

HTML is one link fragment passed through
`org-export-filter-link-functions'.  Return a cons of zero-based
start and end positions, excluding quotes, or nil when no
double-quoted or single-quoted href attribute is present.  The
scanner preserves every byte outside the attribute value."
  (let ((position (string-search "href"
                                 html)))
    (when position
      (setq position (+ position
                        4))
      (while (and (< position
                     (length html))
                  (memq (aref html
                              position)
                        '(?\s ?\t ?\n ?\r)))
        (setq position (1+ position)))
      (when (and (< position
                    (length html))
                 (= (aref html
                          position)
                    ?=))
        (setq position (1+ position))
        (while (and (< position
                       (length html))
                    (memq (aref html
                                position)
                          '(?\s ?\t ?\n ?\r)))
          (setq position (1+ position)))
        (when (< position
                 (length html))
          (let ((quote (aref html
                             position)))
            (when (memq quote
                        '(?\" ?\'))
              (let* ((start (1+ position))
                     (end (string-search (char-to-string quote)
                                         html
                                         start)))
                (and end
                     (cons start
                           end))))))))))

(defun org-roam-blog--theindex-link-filter (output backend _export-info)
  "Map a native theindex link OUTPUT to its publication store URL.

BACKEND and EXPORT-INFO follow
`org-export-filter-link-functions'.  Only HTML-derived backends and
exact href bases present in `org-roam-blog--theindex-href-map' are
changed.  A fragment, when present, is copied unchanged.  Return
OUTPUT unchanged for every other link."
  (if (not (org-export-derived-backend-p backend
                                         'html))
      output
    (let ((range (org-roam-blog--html-href-range output)))
      (if (not range)
          output
        (let* ((href (substring output
                                (car range)
                                (cdr range)))
               (fragment-position (string-search "#"
                                                 href))
               (base (if fragment-position
                         (substring href
                                    0
                                    fragment-position)
                       href))
               (fragment (and fragment-position
                              (substring href
                                         fragment-position)))
               (mapping (assoc-string base
                                      org-roam-blog--theindex-href-map)))
          (if (not mapping)
              output
            (concat (substring output
                               0
                               (car range))
                    (cdr mapping)
                    fragment
                    (substring output
                               (cdr range)))))))))

(defun org-roam-blog--node-matches-tags-p (node tags)
  "Return non-nil when level-0 NODE contains all configured TAGS."
  (and (= (org-roam-node-level node) 0)
       (cl-every (lambda (tag)
                   (member tag (org-roam-node-tags node)))
                 tags)))

(defun org-roam-blog--query-rule-nodes (rule)
  "Return database nodes selected by content RULE.

The function uses `org-roam-node-list' and does not synchronize the
database or scan the source directory."
  (let ((tags (plist-get rule
                         :tags)))
    (cl-remove-if-not
     (lambda (node)
       (org-roam-blog--node-matches-tags-p node tags))
     (org-roam-node-list))))

(defun org-roam-blog--node-published (node)
  "Return publication metadata cached for Org-roam NODE, or nil."
  (cdr (assoc-string org-roam-blog-published-property
                     (org-roam-node-properties node)
                     t)))

(defun org-roam-blog--file-modified-time (source)
  "Return the cached Org-roam file modification time for SOURCE.

Return nil when the Org-roam files table has no row for SOURCE."
  (when-let* ((row (car (org-roam-db-query (vector :select 'mtime
                                                   :from 'files
                                                   :where '(= file $s1))
                                           source))))
    (elt row 0)))

(defun org-roam-blog--manifest-entry (node rule)
  "Build a manifest entry for Org-roam NODE selected by RULE.

Return a cons whose car is the entry and whose cdr is nil on success.
On failure return a cons whose car is nil and whose cdr is a
diagnostic."
  (let* ((source (expand-file-name (org-roam-node-file node)))
         (source-root (file-name-as-directory (expand-file-name org-roam-blog-directory))))
    (condition-case error-data
        (if (not (org-roam-blog--path-inside-p source
                                               source-root))
            (cons nil
                  (org-roam-blog--diagnostic 'error
                                             (plist-get rule
                                                        :name)
                                             (format "Source is outside the blog directory: %s"
                                                     source)))
          (let* ((source-relative (file-relative-name source
                                                      source-root))
                 (store-relative (org-roam-blog--replace-extension (concat (file-name-as-directory org-roam-blog-publish-store)
                                                                           source-relative)
                                                                   ".html"))
                 (store-output (org-roam-blog--output-path store-relative))
                 (export-configuration (org-roam-blog--export-configuration rule))
                 (directory (plist-get rule
                                       :directory))
                 (redirect-relative (when directory
                                      (concat (unless (string= directory
                                                               ".")
                                                (file-name-as-directory directory))
                                              (org-roam-blog--replace-extension (file-name-nondirectory source)
                                                                                ".html")))))
            (cons (list :id (org-roam-node-id node)
                        :title (org-roam-node-title node)
                        :source source
                        :source-truename (file-truename source)
                        :source-relative source-relative
                        :store-output store-output
                        :store-relative store-relative
                        :store-url (org-roam-blog--encode-url-path store-relative)
                        :redirect-relative redirect-relative
                        :content-name (plist-get rule
                                                 :name)
                        :tags (copy-sequence (org-roam-node-tags node))
                        :published-time (org-roam-blog--node-published node)
                        :modified-time (org-roam-blog--file-modified-time source)
                        :sitemap (and (plist-get rule
                                                 :sitemap)
                                      t)
                        :theindex (and (plist-get rule
                                                  :theindex)
                                       t)
                        :config rule
                        :template (plist-get export-configuration
                                             :template)
                        :bindings (plist-get export-configuration
                                             :bindings)
                        :body (plist-get export-configuration
                                         :body))
                  nil)))
      (file-error (cons nil
                        (org-roam-blog--diagnostic 'error
                                                   (plist-get rule
                                                              :name)
                                                   (format "Cannot resolve source file %s: %s"
                                                           source
                                                           (error-message-string error-data))))))))

(defun org-roam-blog--build-manifest ()
  "Build and return the current publication manifest.

The return value is a plist with `:entries' and `:diagnostics'.  Files
are selected only through the Org-roam database.  A real source file
matching multiple content rules is diagnosed as unsupported.  A
second database node for the same real file and rule is ignored and
reported as a warning.  Publication and modification times are read
from cached node properties and the Org-roam files table; the
manifest builder does not parse Org files for metadata."
  (let ((by-truename (make-hash-table :test #'equal))
        entries diagnostics)
    (dolist (rule org-roam-blog-content)
      (dolist (node (org-roam-blog--query-rule-nodes rule))
        (pcase-let ((`(,entry . ,diagnostic)
                     (org-roam-blog--manifest-entry node rule)))
          (if diagnostic
              (push diagnostic
                    diagnostics)
            (let* ((truename (plist-get entry
                                        :source-truename))
                   (previous (gethash truename
                                      by-truename)))
              (cond ((null previous)
                     (puthash truename
                              entry
                              by-truename)
                     (push entry
                           entries))
                    ((not (equal (plist-get previous
                                            :content-name)
                                 (plist-get entry
                                            :content-name)))
                     (push (org-roam-blog--diagnostic 'error
                                                      truename
                                                      (format "File matches content rules %S and %S."
                                                              (plist-get previous
                                                                         :content-name)
                                                              (plist-get entry
                                                                         :content-name)))
                           diagnostics))
                    (t
                     (push (org-roam-blog--diagnostic 'warning
                                                      truename
                                                      "Multiple database nodes resolve to the same source file.")
                           diagnostics))))))))
    (list :entries (nreverse entries)
          :diagnostics (nreverse diagnostics))))

(defun org-roam-blog--plan-item (kind source target owner)
  "Return an output plan item.

KIND identifies the output type.  SOURCE describes its input.  TARGET
is the absolute output file and OWNER identifies its configuration."
  (list :kind kind :source source :target target :owner owner))

(defun org-roam-blog--generated-output-plan (entries)
  "Return an output plan for generated manifest ENTRIES.

The plan includes content store files, redirects, and enabled sitemap
and theindex targets."
  (let (items)
    (dolist (entry entries)
      (push (org-roam-blog--plan-item 'content
                                      (plist-get entry
                                                 :source)
                                      (plist-get entry
                                                 :store-output)
                                      (plist-get entry
                                                 :content-name))
            items)
      (when-let* ((redirect (plist-get entry
                                       :redirect-relative)))
        (push
         (org-roam-blog--plan-item 'redirect
                                   (plist-get entry
                                              :source)
                                   (org-roam-blog--output-path redirect)
                                   (plist-get entry
                                              :content-name))
         items)))
    (when (plist-get org-roam-blog-sitemap
                     :enable)
      (push (org-roam-blog--plan-item 'sitemap
                                      'manifest
                                      (org-roam-blog--output-path (plist-get org-roam-blog-sitemap
                                                                             :path))
                                      'org-roam-blog-sitemap)
            items))
    (when (plist-get org-roam-blog-theindex
                     :enable)
      (push (org-roam-blog--plan-item 'theindex
                                      'manifest
                                      (org-roam-blog--output-path (plist-get org-roam-blog-theindex
                                                                             :path))
                                      'org-roam-blog-theindex)
            items))
    (nreverse items)))

(defun org-roam-blog--static-extension-regexp (mapping)
  "Return the complete file regexp for static MAPPING."
  (format "\\.\\(?:%s\\)\\'"
          (or (plist-get mapping
                         :extensions)
              org-roam-blog--default-static-extensions)))

(defun org-roam-blog--static-target-relative (mapping source-relative)
  "Return publication-relative target for MAPPING and SOURCE-RELATIVE."
  (let ((directory (plist-get mapping
                              :directory)))
    (if (equal directory
               ".")
        source-relative
      (concat (file-name-as-directory directory)
              source-relative))))

(defun org-roam-blog--static-files ()
  "Return static file records selected by `org-roam-blog-static'.

Each record contains `:source', `:source-relative', `:target',
`:target-relative', `:mapping', and `:owner'.  Directory traversal is
recursive and does not follow symlinked directories.  A selected file
whose true path escapes its configured source directory signals an
error."
  (let (records)
    (cl-loop for mapping in org-roam-blog-static
             for index from 0
             for owner = (format "org-roam-blog-static[%d]"
                                 index)
             for base = (file-name-as-directory (expand-file-name (plist-get mapping
                                                                             :source)))
             for regexp = (org-roam-blog--static-extension-regexp mapping)
             do
             (unless (file-directory-p base)
               (error "Static source directory does not exist: %s"
                      base))
             (dolist (source (directory-files-recursively base
                                                          regexp
                                                          nil
                                                          nil
                                                          nil))
               (unless (and (file-regular-p source)
                            (org-roam-blog--path-inside-p (file-truename source)
                                                          (file-truename base)))
                 (error "Static source escapes its configured directory: %s"
                        source))
               (let* ((source-relative (file-relative-name source base))
                      (target-relative (org-roam-blog--static-target-relative mapping
                                                                              source-relative)))
                 (push (list :source source
                             :source-relative source-relative
                             :target (org-roam-blog--output-path target-relative)
                             :target-relative target-relative
                             :mapping mapping
                             :owner owner)
                       records)))
             finally return (nreverse records))))

(defun org-roam-blog--static-output-plan (records)
  "Return output plan items for static file RECORDS."
  (mapcar (lambda (record)
            (org-roam-blog--plan-item 'static
                                      (plist-get record
                                                 :source)
                                      (plist-get record
                                                 :target)
                                      (plist-get record
                                                 :owner)))
          records))

(defun org-roam-blog--publish-static (records)
  "Publish static file RECORDS directly to their final targets.

Use `org-publish-attachment' for copying while preserving the source
tree below each mapping.  Return the final target paths in publication
order.  This function does not modify `org-publish-project-alist'."
  (let (published)
    (dolist (record records)
      (push (org-roam-blog--publish-static-record record)
            published))
    (nreverse published)))

(defun org-roam-blog--publish-static-record (record)
  "Publish one static RECORD and return its final target."
  (let* ((source (plist-get record
                            :source))
         (target (plist-get record
                            :target))
         (mapping (plist-get record
                             :mapping))
         (project (list :base-directory (file-name-as-directory (expand-file-name (plist-get mapping
                                                                                             :source)))
                        :publishing-directory (file-name-directory target))))
    (unless (org-roam-blog--promotable-target-p target)
      (error "Refusing to replace non-regular static target: %s"
             target))
    (make-directory (file-name-directory target)
                    t)
    (org-publish-attachment project
                            source
                            (file-name-directory target))
    target))

(defun org-roam-blog--publish-static-batch (records)
  "Publish static RECORDS and return a result plist.

The result contains `:status', `:published', and `:diagnostics'.  On
failure, `:published' lists the targets copied before the error."
  (let (published diagnostics)
    (condition-case error-data
        (progn (dolist (record records)
                 (push (org-roam-blog--publish-static-record record)
                       published))
               (list :status 'success
                     :published (nreverse published)
                     :diagnostics nil))
      (error (push (org-roam-blog--diagnostic 'error
                                              'static
                                              (error-message-string error-data))
                   diagnostics)
             (list :status 'failure
                   :published (nreverse published)
                   :diagnostics (nreverse diagnostics))))))

(defun org-roam-blog--output-conflicts (items)
  "Return diagnostics for exact target collisions in plan ITEMS."
  (let ((targets (make-hash-table :test #'equal))
        diagnostics)
    (dolist (item items)
      (let* ((target (expand-file-name (plist-get item
                                                  :target)))
             (previous (gethash target targets)))
        (if previous
            (push (org-roam-blog--diagnostic 'error
                                             target
                                             (format "Output conflict between %S (%S) and %S (%S)."
                                                     (plist-get previous
                                                                :kind)
                                                     (plist-get previous
                                                                :owner)
                                                     (plist-get item
                                                                :kind)
                                                     (plist-get item
                                                                :owner)))
                  diagnostics)
          (puthash target item targets))))
    (nreverse diagnostics)))

(defun org-roam-blog--output-target-diagnostics (items)
  "Return diagnostics for unsafe or non-promotable plan ITEMS."
  (let (diagnostics)
    (dolist (item items)
      (let ((target (plist-get item
                               :target)))
        (unless (file-in-directory-p target org-roam-blog-publish-directory)
          (push (org-roam-blog--diagnostic 'error
                                           target
                                           "Output target escapes the publication directory.")
                diagnostics))
        (unless (org-roam-blog--promotable-target-p target)
          (push (org-roam-blog--diagnostic 'error
                                           target
                                           "Existing output target is a directory, symlink, or special file.")
                diagnostics))))
    (nreverse diagnostics)))

(defun org-roam-blog--make-staging-directory ()
  "Create and return a unique staging directory for one publication.

Create the directory below `org-roam-blog-temporary-directory', or
below `temporary-file-directory' when that option is nil.  Its name
contains a timestamp followed by the unique suffix generated by
`make-temp-file'."
  (let* ((parent (or org-roam-blog-temporary-directory
                     temporary-file-directory))
         (temporary-file-directory (file-name-as-directory (expand-file-name parent)))
         (prefix (format "org-roam-blog-%s-"
                         (format-time-string "%Y%m%dT%H%M%S"))))
    (make-temp-file prefix t)))

(defun org-roam-blog--staging-output (staging relative-path)
  "Return the output path below STAGING for RELATIVE-PATH."
  (unless (org-roam-blog--relative-file-p relative-path)
    (error "Unsafe staging output path: %S"
           relative-path))
  (expand-file-name relative-path
                    (file-name-as-directory staging)))

(defun org-roam-blog--export-content-entry (entry staging)
  "Export manifest ENTRY from disk into STAGING.

The source file is read into a fresh temporary buffer, so unsaved
changes in an existing visiting buffer are ignored.  Standard Org
export hooks and filters remain active under the entry's dynamic
`:bindings' environment.  Effective native body filters run before
the entry's merged `:body' functions.  Links are passed to Org
unchanged; in particular, this package does not repair or reinterpret
`id:' links or their HTML anchors.  Return the staged output file."
  (let* ((source (plist-get entry
                            :source))
         (relative (plist-get entry
                              :store-relative))
         (output (org-roam-blog--staging-output staging
                                                relative))
         (template (plist-get entry
                              :template))
         (bindings (plist-get entry
                              :bindings))
         (body (plist-get entry
                          :body))
         (context (org-roam-blog--make-body-context 'content
                                                    entry
                                                    (plist-get entry
                                                               :config))))
    (make-directory (file-name-directory output)
                    t)
    (with-temp-buffer
      (insert-file-contents source)
      (setq buffer-file-name source)
      (setq default-directory (file-name-directory source))
      (org-mode)
      (org-roam-blog--call-with-export-bindings
       bindings
       (lambda ()
         (let ((org-export-filter-final-output-functions
                (if (and org-roam-blog--collect-theindex
                         (plist-get entry
                                    :theindex))
                    (append org-export-filter-final-output-functions
                            (list #'org-publish-collect-index))
                  org-export-filter-final-output-functions)))
           (org-roam-blog--export-to-file output
                                          template
                                          body
                                          context)))))
    (when (and org-roam-blog--collect-theindex
               (plist-get entry
                          :theindex))
      (org-publish-update-timestamp (plist-get entry
                                               :source-truename)))
    output))

(defun org-roam-blog--stage-content (entries staging)
  "Export manifest ENTRIES into STAGING.

Return a list of cons cells pairing each entry with its staged output.
Signal the original export error on failure."
  (mapcar (lambda (entry)
            (cons entry
                  (org-roam-blog--export-content-entry entry staging)))
          entries))

(defun org-roam-blog--html-attribute-escape (value)
  "Escape VALUE for a double-quoted HTML attribute."
  (let ((escaped (org-html-encode-plain-text value)))
    (setq escaped (replace-regexp-in-string "\""
                                            "&quot;"
                                            escaped
                                            t
                                            t))
    (replace-regexp-in-string "'"
                              "&#39;"
                              escaped
                              t
                              t)))

(defun org-roam-blog--redirect-html (entry)
  "Return a static HTML redirect document for manifest ENTRY."
  (let* ((redirect (plist-get entry
                              :redirect-relative))
         (store (plist-get entry
                           :store-relative))
         (target (org-roam-blog--relative-url redirect
                                              store))
         (attribute-target (org-roam-blog--html-attribute-escape target))
         (title (org-roam-blog--html-attribute-escape (or (plist-get entry
                                                                     :title)
                                                          "Redirect")))
         (javascript-target (json-serialize target)))
    (concat "<!doctype html>\n"
            "<html lang=\"en\">\n"
            "<head>\n"
            "<meta charset=\"utf-8\">\n"
            "<meta http-equiv=\"refresh\" content=\"0; url=" attribute-target "\">\n"
            "<link rel=\"canonical\" href=\"" attribute-target "\">\n"
            "<title>" title "</title>\n"
            "<script>location.replace(" javascript-target ");</script>\n"
            "</head>\n"
            "<body><p><a href=\"" attribute-target "\">" title "</a></p></body>\n"
            "</html>\n")))

(defun org-roam-blog--stage-redirects (entries staging)
  "Generate redirects for manifest ENTRIES below STAGING.

Return a list of cons cells pairing each entry with its staged
redirect file."
  (let (staged)
    (dolist (entry entries)
      (when-let* ((relative (plist-get entry
                                       :redirect-relative)))
        (let ((output (org-roam-blog--staging-output staging
                                                     relative)))
          (make-directory (file-name-directory output)
                          t)
          (write-region (org-roam-blog--redirect-html entry)
                        nil
                        output
                        nil
                        'silent)
          (push (cons entry
                      output)
                staged))))
    (nreverse staged)))

(defun org-roam-blog--sitemap-project-tags (tags config)
  "Return members of TAGS listed by sitemap CONFIG as visible."
  (let ((visible (plist-get config
                            :visible-tags)))
    (cl-remove-if-not (lambda (tag)
                        (member tag
                                visible))
                      tags)))

(defun org-roam-blog--sitemap-entry-time (entry)
  "Return a sortable time value from sitemap ENTRY, or nil."
  (let ((published (plist-get entry
                              :published-time)))
    (cond ((null published)
           nil)
          ((stringp published)
           (condition-case nil
               (org-time-string-to-time published)
             (error nil)))
          ((listp published) published)
          (t
           nil))))

(defun org-roam-blog--sitemap-prepare-entries (entries config)
  "Filter and prepare manifest ENTRIES according to sitemap CONFIG."
  (let ((prepared (mapcar (lambda (entry)
                            (let ((copy (copy-sequence entry)))
                              (plist-put copy
                                         :tags
                                         (org-roam-blog--sitemap-project-tags (plist-get copy
                                                                                         :tags)
                                                                              config))))
                          (cl-remove-if-not (lambda (entry)
                                              (plist-get entry
                                                         :sitemap))
                                            entries))))
    (if (eq (plist-get config
                       :sort)
            'anti-chronologically)
        (cl-stable-sort prepared
                        (lambda (left right)
                          (let ((left-time (org-roam-blog--sitemap-entry-time left))
                                (right-time (org-roam-blog--sitemap-entry-time right)))
                            (cond ((and left-time right-time)
                                   (time-less-p right-time left-time))
                                  (left-time t)
                                  (t nil)))))
      prepared)))

(defun org-roam-blog--sitemap-link-description (value)
  "Escape VALUE for use as an Org link description."
  (replace-regexp-in-string "]"
                            "\\\\]"
                            (replace-regexp-in-string "[\n\r]+"
                                                      " "
                                                      (or value "")
                                                      t
                                                      t)
                            t
                            t))

(defun org-roam-blog--sitemap-default-generator (context)
  "Return default Org sitemap content for CONTEXT.

Display each entry's `:published-time' value when present.  The
filesystem `:modified-time' remains manifest metadata and is not
included in the default sitemap."
  (let* ((entries (plist-get context
                             :entries))
         (config (plist-get context
                            :config))
         (path (plist-get config
                          :path))
         (title (or (plist-get config
                               :title)
                    "Sitemap")))
    (concat "#+TITLE: "
            (replace-regexp-in-string "[\n\r]+"
                                      " "
                                      title
                                      t
                                      t)
            "\n\n"
            (mapconcat (lambda (entry)
                         (let* ((url (org-roam-blog--relative-url path
                                                                  (plist-get entry
                                                                             :store-relative)))
                                (description (org-roam-blog--sitemap-link-description (or (plist-get entry
                                                                                                     :title)
                                                                                          (plist-get entry
                                                                                                     :source-relative))))
                                (published (plist-get entry
                                                      :published-time))
                                (tags (plist-get entry
                                                 :tags)))
                           (concat "- [[file:" url "][" description "]]"
                                   (when published
                                     (concat " "
                                             (replace-regexp-in-string "[\n\r]+"
                                                                       " "
                                                                       published
                                                                       t
                                                                       t)))
                                   (when tags
                                     (concat " ("
                                             (mapconcat #'org-roam-blog--sitemap-link-description
                                                        tags
                                                        ", ")
                                             ")")))))
                       entries
                       "\n")
            (when entries "\n"))))

(defun org-roam-blog--sitemap-source (entries)
  "Return Org sitemap source for manifest ENTRIES.

The configured generator receives one plist containing `:entries'
and `:config'.  Entries have already been filtered, sorted, and had
their displayed tags projected.  The generator must return a complete
Org source string.  Entries retain both `:published-time' and
filesystem `:modified-time' metadata; the default generator only
displays `:published-time'."
  (let* ((config org-roam-blog-sitemap)
         (prepared (org-roam-blog--sitemap-prepare-entries entries
                                                           config))
         (generator (or (plist-get config
                                   :generator)
                        #'org-roam-blog--sitemap-default-generator))
         (context (list :entries prepared
                        :config config))
         (source (funcall generator
                          context)))
    (unless (stringp source)
      (error "Sitemap generator must return a string"))
    source))

(defun org-roam-blog--sitemap-stage (entries staging)
  "Generate and stage the configured sitemap from manifest ENTRIES.

Return a cons pairing the sitemap target-relative path with its staged
file, or nil when sitemap generation is disabled.  Source generation
and export run under the effective dynamic bindings.  Effective native
body filters run before the merged sitemap body functions."
  (when (plist-get org-roam-blog-sitemap
                   :enable)
    (let* ((relative (plist-get org-roam-blog-sitemap
                                :path))
           (output (org-roam-blog--staging-output staging
                                                  relative))
           (export-configuration (org-roam-blog--export-configuration org-roam-blog-sitemap))
           (template (plist-get export-configuration
                                :template))
           (bindings (plist-get export-configuration
                                :bindings))
           (body (plist-get export-configuration
                            :body))
           (context (org-roam-blog--make-body-context 'sitemap
                                                      nil
                                                      org-roam-blog-sitemap)))
      (make-directory (file-name-directory output)
                      t)
      (with-temp-buffer
        (org-mode)
        ;; `org-mode' establishes buffer-local path state.  Set the
        ;; virtual source location afterwards so relative links are
        ;; checked from the staged sitemap's directory.
        (setq buffer-file-name (org-roam-blog--replace-extension output
                                                                 ".org"))
        (setq default-directory (file-name-directory output))
        (org-roam-blog--call-with-export-bindings
         bindings
         (lambda ()
           (insert (org-roam-blog--sitemap-source entries))
           (org-roam-blog--export-to-file output
                                          template
                                          body
                                          context))))
      (cons relative
            output))))

(defun org-roam-blog--theindex-entries (entries)
  "Return manifest ENTRIES selected for the generated theindex."
  (cl-remove-if-not (lambda (entry)
                      (plist-get entry
                                 :theindex))
                    entries))

(defun org-roam-blog--theindex-project (entries work-directory output-directory)
  "Return a private Org Publish project for theindex ENTRIES.

WORK-DIRECTORY contains the generated Org source and include file.
OUTPUT-DIRECTORY is the directory containing the staged HTML result.
Absolute `:include' paths restrict native Publish enumeration to the
selected manifest files."
  (list "org-roam-blog-theindex"
        :base-directory work-directory
        :base-extension "org"
        :publishing-directory output-directory
        :recursive nil
        :exclude ".*"
        :include (mapcar (lambda (entry)
                           (plist-get entry
                                      :source))
                         entries)))

(defun org-roam-blog--theindex-href-map (entries work-directory relative)
  "Return native-to-store href mappings for ENTRIES.

WORK-DIRECTORY is the virtual directory of generated theindex Org
source.  RELATIVE is the final publication-relative theindex HTML
path.  Mapping keys intentionally retain the unencoded representation
seen by Org's HTML link-filter stage.  Mapping values are encoded URLs
relative to RELATIVE."
  (mapcar
   (lambda (entry)
     (let* ((source (plist-get entry
                               :source))
            (native-html (concat (file-name-sans-extension source)
                                 ".html"))
            (native-href (file-relative-name native-html
                                             work-directory))
            (store-href (org-roam-blog--relative-url relative
                                                     (plist-get entry
                                                                :store-relative))))
       (cons native-href
             store-href)))
   entries))

(defun org-roam-blog--theindex-source (work-directory config)
  "Create and return the generated theindex Org file.

WORK-DIRECTORY is private build state.  CONFIG is the validated
`org-roam-blog-theindex' plist.  The source delegates index content
to the native generator's `theindex.inc' file."
  (let ((source (expand-file-name "theindex.org"
                                  work-directory))
        (title (or (plist-get config
                              :title)
                   "Index")))
    (write-region (format "#+TITLE: %s\n\n#+INCLUDE: \"theindex.inc\"\n"
                          title)
                  nil
                  source
                  nil
                  'silent)
    source))

(defun org-roam-blog--theindex-stage (entries staging work-directory project)
  "Generate and stage the configured theindex.

ENTRIES are the selected manifest entries whose index data have
already been collected into the dynamically bound Publish cache.
STAGING is the generated-output staging root.  WORK-DIRECTORY holds
private native generator files, and PROJECT is its private Publish
project.  Return a cons pairing the configured target-relative path
with its staged HTML file, or nil when generation is disabled.

Generation and export run under the effective theindex bindings.
User link filters run before the package's exact href mapper.  Native
body filters run before the merged theindex body functions."
  (when (plist-get org-roam-blog-theindex
                   :enable)
    (let* ((relative (plist-get org-roam-blog-theindex
                                :path))
           (output (org-roam-blog--staging-output staging
                                                  relative))
           (output-directory (file-name-directory output))
           (export-configuration
            (org-roam-blog--export-configuration org-roam-blog-theindex))
           (template (plist-get export-configuration
                                :template))
           (bindings (plist-get export-configuration
                                :bindings))
           (body (plist-get export-configuration
                            :body))
           (context (org-roam-blog--make-body-context 'theindex
                                                      nil
                                                      org-roam-blog-theindex))
           (source (org-roam-blog--theindex-source work-directory
                                                   org-roam-blog-theindex))
           (org-roam-blog--theindex-href-map
            (org-roam-blog--theindex-href-map entries
                                              work-directory
                                              relative)))
      (make-directory output-directory
                      t)
      (org-roam-blog--call-with-export-bindings
       bindings
       (lambda ()
         (org-publish-index-generate-theindex project
                                              work-directory)
         (with-temp-buffer
           (insert-file-contents source)
           (setq buffer-file-name source)
           (setq default-directory work-directory)
           (org-mode)
           (let ((org-export-filter-link-functions
                  (append org-export-filter-link-functions
                          (list #'org-roam-blog--theindex-link-filter))))
             (org-roam-blog--export-to-file output
                                            template
                                            body
                                            context)))))
      (cons relative
            output))))

(defun org-roam-blog--promotable-target-p (target)
  "Return non-nil when TARGET may be replaced by generated content.

A missing target or an existing regular non-symlink file is
promotable.  Directories, symlinks, and special files are rejected."
  (or (not (file-exists-p target))
      (and (file-regular-p target)
           (not (file-symlink-p target)))))

(defun org-roam-blog--promote-file (staged target)
  "Copy STAGED to publication TARGET, replacing a regular file.

Create missing parent directories.  Reject an existing directory,
symlink, or special file.  Return TARGET."
  (unless (org-roam-blog--promotable-target-p target)
    (error "Refusing to replace non-regular publication target: %s"
           target))
  (make-directory (file-name-directory target)
                  t)
  (copy-file staged
             target
             t
             t
             nil
             t)
  target)

(defun org-roam-blog--stage-generated-batch (entries)
  "Stage all generated output for manifest ENTRIES.

Return a result plist containing `:status', `:staging', staged
`:content', `:sitemap', `:theindex', `:redirects', and
`:diagnostics'.  Theindex collection shares one dynamically bound
in-memory Publish cache with content export.  Failure leaves the
staging directory, including private theindex work files, for
inspection."
  (let ((staging (org-roam-blog--make-staging-directory))
        staged-content staged-sitemap staged-theindex staged-redirects diagnostics)
    (condition-case error-data
        (let* ((theindex-enabled (plist-get org-roam-blog-theindex
                                            :enable))
               (theindex-entries (and theindex-enabled
                                      (org-roam-blog--theindex-entries entries)))
               (work-root (and theindex-enabled
                               (expand-file-name ".org-roam-blog-work"
                                                 staging)))
               (work-directory (and work-root
                                    (expand-file-name "theindex"
                                                      work-root)))
               (timestamp-directory (and work-root
                                         (expand-file-name "timestamps"
                                                           work-root)))
               (theindex-relative (and theindex-enabled
                                       (plist-get org-roam-blog-theindex
                                                  :path)))
               (theindex-output-directory
                (and theindex-enabled
                     (file-name-directory
                      (org-roam-blog--staging-output staging
                                                     theindex-relative))))
               (project (and theindex-enabled
                             (org-roam-blog--theindex-project
                              theindex-entries
                              work-directory
                              theindex-output-directory)))
               (org-publish-cache (if theindex-enabled
                                      (make-hash-table :test #'equal
                                                       :weakness nil
                                                       :size 30)
                                    org-publish-cache))
               (org-publish-timestamp-directory
                (or timestamp-directory
                    org-publish-timestamp-directory))
               (org-id-locations (if (hash-table-p org-id-locations)
                                     (copy-hash-table org-id-locations)
                                   (copy-tree org-id-locations)))
               (org-id-locations-file (if work-root
                                          (expand-file-name "org-id-locations"
                                                            work-root)
                                        org-id-locations-file))
               (org-roam-blog--collect-theindex theindex-enabled))
          (when theindex-enabled
            (make-directory work-directory
                            t)
            (org-publish-cache-set ":project:"
                                   (car project))
            (org-publish-cache-set ":cache-file:"
                                   (expand-file-name "unused.cache"
                                                     timestamp-directory)))
          (setq staged-content (org-roam-blog--stage-content entries
                                                             staging)
                staged-sitemap (org-roam-blog--sitemap-stage entries
                                                             staging)
                staged-theindex (org-roam-blog--theindex-stage theindex-entries
                                                               staging
                                                               work-directory
                                                               project)
                staged-redirects (org-roam-blog--stage-redirects entries
                                                                 staging))
          (list :status 'success
                :staging staging
                :content staged-content
                :sitemap staged-sitemap
                :theindex staged-theindex
                :redirects staged-redirects
                :diagnostics nil))
      (error (push (org-roam-blog--diagnostic 'error
                                              'content
                                              (error-message-string error-data))
                   diagnostics)
             (list :status 'failure
                   :staging staging
                   :diagnostics (nreverse diagnostics))))))

(defun org-roam-blog--promote-generated-batch (staged)
  "Promote a successful STAGED generated-output result.

Return a result plist with `:status', `:staging', `:promoted', and
`:diagnostics'.  Content is promoted first, followed by sitemap,
theindex, and redirects.  Failure preserves the staging directory
and reports targets already promoted."
  (let ((staging (plist-get staged
                            :staging))
        promoted diagnostics)
    (condition-case error-data
        (progn
          (dolist (pair (plist-get staged
                                   :content))
            (let ((target (plist-get (car pair)
                                     :store-output)))
              (org-roam-blog--promote-file (cdr pair)
                                           target)
              (push target
                    promoted)))
          (when-let* ((sitemap (plist-get staged
                                          :sitemap)))
            (let ((target (org-roam-blog--output-path (car sitemap))))
              (org-roam-blog--promote-file (cdr sitemap)
                                           target)
              (push target
                    promoted)))
          (when-let* ((theindex (plist-get staged
                                           :theindex)))
            (let ((target (org-roam-blog--output-path (car theindex))))
              (org-roam-blog--promote-file (cdr theindex)
                                           target)
              (push target
                    promoted)))
          (dolist (pair (plist-get staged
                                   :redirects))
            (let ((target (org-roam-blog--output-path (plist-get (car pair)
                                                                 :redirect-relative))))
              (org-roam-blog--promote-file (cdr pair)
                                           target)
              (push target
                    promoted)))
          (delete-directory staging
                            t)
          (list :status 'success
                :staging nil
                :promoted (nreverse promoted)
                :diagnostics nil))
      (error (push (org-roam-blog--diagnostic 'error
                                              'promotion
                                              (error-message-string error-data))
                   diagnostics)
             (list :status 'failure
                   :staging staging
                   :promoted (nreverse promoted)
                   :diagnostics (nreverse diagnostics))))))

(defun org-roam-blog--publish-generated-batch (entries)
  "Stage and promote all generated output for manifest ENTRIES.

This compatibility entry point performs both phases without publishing
static files.  Generation failure leaves staging intact; promotion
failure also reports targets already promoted."
  (let ((staged (org-roam-blog--stage-generated-batch entries)))
    (if (eq (plist-get staged
                       :status)
            'success)
        (org-roam-blog--promote-generated-batch staged)
      staged)))

(defun org-roam-blog--publish-content-batch (entries)
  "Stage and promote generated output for manifest ENTRIES.

This compatibility wrapper delegates to
`org-roam-blog--publish-generated-batch'."
  (org-roam-blog--publish-generated-batch entries))

(defun org-roam-blog--validate-known-plist (value allowed subject diagnostics)
  "Validate VALUE as a plist whose keys occur in ALLOWED.

SUBJECT identifies VALUE in generated messages.  Append diagnostics
to DIAGNOSTICS and return the resulting list."
  (if (not (org-roam-blog--plist-p value))
      (cons (org-roam-blog--diagnostic 'error
                                       subject
                                       "Value must be a proper even-length plist.")
            diagnostics)
    (dolist (key (org-roam-blog--unknown-keys value allowed)
                 diagnostics)
      (push (org-roam-blog--diagnostic 'error
                                       subject
                                       (format "Unknown key: %S"
                                               key))
            diagnostics))))

(defun org-roam-blog--validate-content (diagnostics)
  "Append content-rule diagnostics to DIAGNOSTICS."
  (if (not (listp org-roam-blog-content))
      (cons (org-roam-blog--diagnostic 'error
                                       'org-roam-blog-content
                                       "Value must be a list.")
            diagnostics)
    (let ((seen-names (make-hash-table :test #'equal)))
      (cl-loop for rule in org-roam-blog-content
               for index from 0
               for subject = (format "org-roam-blog-content[%d]"
                                     index)
               do
               (setq diagnostics (org-roam-blog--validate-known-plist rule
                                                                      org-roam-blog--content-keys
                                                                      subject
                                                                      diagnostics))
               (when (org-roam-blog--plist-p rule)
                 (let ((name (plist-get rule
                                        :name))
                       (tags (plist-get rule
                                        :tags))
                       (directory (plist-get rule
                                             :directory))
                       (template (plist-get rule
                                            :template))
                       (bindings (plist-get rule
                                            :bindings))
                       (body (plist-get rule
                                        :body)))
                   (if (and (stringp name)
                            (not (string-empty-p name)))
                       (if (gethash name
                                    seen-names)
                           (push (org-roam-blog--diagnostic 'error
                                                            subject
                                                            (format "Duplicate content name: %S"
                                                                    name))
                                 diagnostics)
                         (puthash name
                                  t
                                  seen-names))
                     (push (org-roam-blog--diagnostic 'error
                                                      subject
                                                      "The :name field must be non-empty.")
                           diagnostics))
                   (unless (org-roam-blog--string-list-p tags
                                                         t)
                     (push (org-roam-blog--diagnostic 'error
                                                      subject
                                                      "The :tags field must be a non-empty string list.")
                           diagnostics))
                   (unless (or (null directory)
                               (org-roam-blog--relative-path-p directory
                                                               t))
                     (push (org-roam-blog--diagnostic 'error
                                                      subject
                                                      (concat "The :directory field must be nil or a safe "
                                                              "relative path."))
                           diagnostics))
                   (when (and (plist-member rule
                                            :template)
                              (not (org-roam-blog--plist-p template)))
                     (push (org-roam-blog--diagnostic 'error
                                                      subject
                                                      "The :template field must be a plist.")
                           diagnostics))
                   (when (and (plist-member rule
                                            :bindings)
                              (not (org-roam-blog--bindings-p bindings)))
                     (push (org-roam-blog--diagnostic 'error
                                                      subject
                                                      "The :bindings field must be an alist keyed by symbols.")
                           diagnostics))
                   (when (and (plist-member rule
                                            :body)
                              (not (org-roam-blog--function-list-p body)))
                     (push (org-roam-blog--diagnostic 'error
                                                      subject
                                                      "The :body field must be a list of functions.")
                           diagnostics))
                   (dolist (key '(:sitemap :theindex))
                     (when (and (plist-member rule
                                              key)
                                (not (booleanp (plist-get rule
                                                          key))))
                       (push (org-roam-blog--diagnostic 'error
                                                        subject
                                                        (format "The %S field must be boolean."
                                                                key))
                             diagnostics)))))
               finally return diagnostics))))

(defun org-roam-blog--validate-static (diagnostics)
  "Append static-mapping diagnostics to DIAGNOSTICS."
  (if (not (listp org-roam-blog-static))
      (cons (org-roam-blog--diagnostic 'error
                                       'org-roam-blog-static
                                       "Value must be a list.")
            diagnostics)
    (cl-loop for mapping in org-roam-blog-static
             for index from 0
             for subject = (format "org-roam-blog-static[%d]"
                                   index)
             do
             (setq diagnostics (org-roam-blog--validate-known-plist mapping
                                                                    org-roam-blog--static-keys
                                                                    subject
                                                                    diagnostics))
             (when (org-roam-blog--plist-p mapping)
               (unless (org-roam-blog--absolute-directory-p (plist-get mapping
                                                                       :source))
                 (push (org-roam-blog--diagnostic 'error
                                                  subject
                                                  "The :source field must be absolute.")
                       diagnostics))
               (unless (org-roam-blog--relative-path-p (plist-get mapping
                                                                  :directory)
                                                       t)
                 (push (org-roam-blog--diagnostic 'error
                                                  subject
                                                  "The :directory field must be a safe relative path.")
                       diagnostics))
               (let ((extensions (plist-get mapping
                                            :extensions)))
                 (unless (or (null extensions)
                             (stringp extensions))
                   (push (org-roam-blog--diagnostic 'error
                                                    subject
                                                    "The :extensions field must be nil or a regexp string.")
                         diagnostics))
                 (when (stringp extensions)
                   (condition-case nil
                       (string-match-p extensions
                                       "")
                     (invalid-regexp (push (org-roam-blog--diagnostic 'error
                                                                      subject
                                                                      "The :extensions field is not a valid regexp.")
                                           diagnostics))))))
             finally return diagnostics)))

(defun org-roam-blog--validate-sitemap (diagnostics)
  "Append sitemap diagnostics to DIAGNOSTICS."
  (let ((subject 'org-roam-blog-sitemap))
    (setq diagnostics (org-roam-blog--validate-known-plist org-roam-blog-sitemap
                                                           org-roam-blog--sitemap-keys
                                                           subject
                                                           diagnostics))
    (when (org-roam-blog--plist-p org-roam-blog-sitemap)
      (let ((enabled (plist-get org-roam-blog-sitemap
                                :enable)))
        (unless (booleanp enabled)
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :enable field must be boolean.")
                diagnostics))
        (when enabled
          (unless (org-roam-blog--relative-file-p (plist-get org-roam-blog-sitemap
                                                             :path))
            (push (org-roam-blog--diagnostic 'error
                                             subject
                                             "Enabled sitemap requires a safe relative :path.")
                  diagnostics)))
        (when (and (plist-member org-roam-blog-sitemap
                                 :visible-tags)
                   (not (org-roam-blog--string-list-p (plist-get org-roam-blog-sitemap
                                                                 :visible-tags))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :visible-tags field must be nil or a string list.")
                diagnostics))
        (when (and (plist-member org-roam-blog-sitemap
                                 :generator)
                   (let ((generator (plist-get org-roam-blog-sitemap
                                               :generator)))
                     (not (or (null generator)
                              (functionp generator)))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :generator field must be nil or a function.")
                diagnostics))
        (when (and (plist-member org-roam-blog-sitemap
                                 :template)
                   (not (org-roam-blog--plist-p (plist-get org-roam-blog-sitemap
                                                           :template))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :template field must be a plist.")
                diagnostics))
        (when (and (plist-member org-roam-blog-sitemap
                                 :bindings)
                   (not (org-roam-blog--bindings-p (plist-get org-roam-blog-sitemap
                                                              :bindings))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :bindings field must be an alist keyed by symbols.")
                diagnostics))
        (when (and (plist-member org-roam-blog-sitemap
                                 :body)
                   (not (org-roam-blog--function-list-p (plist-get org-roam-blog-sitemap
                                                                   :body))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :body field must be a list of functions.")
                diagnostics))))
    diagnostics))

(defun org-roam-blog--validate-theindex (diagnostics)
  "Append theindex diagnostics to DIAGNOSTICS."
  (let ((subject 'org-roam-blog-theindex))
    (setq diagnostics (org-roam-blog--validate-known-plist org-roam-blog-theindex
                                                           org-roam-blog--theindex-keys
                                                           subject
                                                           diagnostics))
    (when (org-roam-blog--plist-p org-roam-blog-theindex)
      (let ((enabled (plist-get org-roam-blog-theindex
                                :enable)))
        (unless (booleanp enabled)
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :enable field must be boolean.")
                diagnostics))
        (when (and enabled
                   (not (org-roam-blog--relative-file-p (plist-get org-roam-blog-theindex
                                                                   :path))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "Enabled theindex requires a safe relative :path.")
                diagnostics))
        (when (and (plist-member org-roam-blog-theindex
                                 :title)
                   (not (stringp (plist-get org-roam-blog-theindex
                                            :title))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :title field must be a string.")
                diagnostics))
        (when (and (plist-member org-roam-blog-theindex
                                 :template)
                   (not (org-roam-blog--plist-p (plist-get org-roam-blog-theindex
                                                           :template))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :template field must be a plist.")
                diagnostics))
        (when (and (plist-member org-roam-blog-theindex
                                 :bindings)
                   (not (org-roam-blog--bindings-p (plist-get org-roam-blog-theindex
                                                              :bindings))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :bindings field must be an alist keyed by symbols.")
                diagnostics))
        (when (and (plist-member org-roam-blog-theindex
                                 :body)
                   (not (org-roam-blog--function-list-p (plist-get org-roam-blog-theindex
                                                                   :body))))
          (push (org-roam-blog--diagnostic 'error
                                           subject
                                           "The :body field must be a list of functions.")
                diagnostics))))
    diagnostics))

(defun org-roam-blog--validate-variables ()
  "Return diagnostics for all Org-roam Blog configuration variables.

This function is read-only.  It does not create directories,
synchronize Org-roam, or repair configuration."
  (let (diagnostics)
    (dolist (entry `((org-roam-blog-directory . ,org-roam-blog-directory)
                     (org-roam-blog-publish-directory . ,org-roam-blog-publish-directory)))
      (unless (org-roam-blog--existing-real-directory-p (cdr entry))
        (push (org-roam-blog--diagnostic 'error
                                         (car entry)
                                         (concat "Value must name an existing absolute directory "
                                                 "and must not be a symbolic link."))
              diagnostics)))
    (if (not (org-roam-blog--relative-path-p org-roam-blog-publish-store))
        (push (org-roam-blog--diagnostic 'error
                                         'org-roam-blog-publish-store
                                         "Value must be a non-empty safe relative directory.")
              diagnostics)
      (when (org-roam-blog--existing-real-directory-p org-roam-blog-publish-directory)
        (let ((store (expand-file-name org-roam-blog-publish-store
                                       org-roam-blog-publish-directory)))
          (when (or (file-exists-p store)
                    (file-symlink-p store))
            (unless (and (file-directory-p store)
                         (not (file-symlink-p store))
                         (file-in-directory-p store
                                              org-roam-blog-publish-directory))
              (push (org-roam-blog--diagnostic 'error
                                               'org-roam-blog-publish-store
                                               (concat "An existing store must be a non-symlink "
                                                       "directory below the publication directory."))
                    diagnostics))))))
    (unless (org-roam-blog--valid-site-url-p org-roam-blog-site-url)
      (push (org-roam-blog--diagnostic 'error
                                       'org-roam-blog-site-url
                                       (concat "Value must be nil or an absolute HTTP(S) URL ending "
                                               "in / without query or fragment."))
            diagnostics))
    (unless (or (null org-roam-blog-temporary-directory)
                (org-roam-blog--existing-real-directory-p
                 org-roam-blog-temporary-directory))
      (push (org-roam-blog--diagnostic 'error
                                       'org-roam-blog-temporary-directory
                                       (concat "Value must be nil or name an existing absolute "
                                               "non-symlink directory."))
            diagnostics))
    (setq diagnostics
          (org-roam-blog--validate-known-plist org-roam-blog-export-default
                                               org-roam-blog--export-default-keys
                                               'org-roam-blog-export-default
                                               diagnostics))
    (when (org-roam-blog--plist-p org-roam-blog-export-default)
      (unless (org-roam-blog--plist-p (plist-get org-roam-blog-export-default
                                                 :template))
        (push (org-roam-blog--diagnostic 'error
                                         'org-roam-blog-export-default
                                         "The :template field must be a plist.")
              diagnostics))
      (unless (org-roam-blog--bindings-p (plist-get org-roam-blog-export-default
                                                    :bindings))
        (push (org-roam-blog--diagnostic 'error
                                         'org-roam-blog-export-default
                                         "The :bindings field must be an alist keyed by symbols.")
              diagnostics))
      (unless (org-roam-blog--function-list-p (plist-get org-roam-blog-export-default
                                                         :body))
        (push (org-roam-blog--diagnostic 'error
                                         'org-roam-blog-export-default
                                         "The :body field must be a list of functions.")
              diagnostics)))
    (unless (and (stringp org-roam-blog-published-property)
                 (not (string-empty-p org-roam-blog-published-property)))
      (push (org-roam-blog--diagnostic 'error
                                       'org-roam-blog-published-property
                                       "Value must be a non-empty property name.")
            diagnostics))
    (setq diagnostics (org-roam-blog--validate-content diagnostics))
    (setq diagnostics (org-roam-blog--validate-static diagnostics))
    (setq diagnostics (org-roam-blog--validate-sitemap diagnostics))
    (setq diagnostics (org-roam-blog--validate-theindex diagnostics))
    (nreverse diagnostics)))

(defun org-roam-blog--capability (name available required detail)
  "Return a capability record.

NAME identifies the capability.  AVAILABLE and REQUIRED are booleans.
DETAIL describes the API being checked."
  (list :name name
        :available (and available
                        t)
        :required (and required
                       t)
        :detail detail))

(defun org-roam-blog--check-capabilities ()
  "Return capability records required by the current configuration.

The probes are read-only and do not export files, write caches, or
synchronize the Org-roam database."
  (let ((theindex-enabled (and (org-roam-blog--plist-p org-roam-blog-theindex)
                               (plist-get org-roam-blog-theindex
                                          :enable))))
    (list (org-roam-blog--capability 'org-export
                                     (fboundp 'org-export-to-file)
                                     t
                                     "Required function `org-export-to-file' is unavailable.")
          (org-roam-blog--capability 'ox-html
                                     (fboundp 'org-html-export-to-html)
                                     t
                                     "Required function `org-html-export-to-html' is unavailable.")
          (org-roam-blog--capability 'org-publish
                                     (fboundp 'org-publish-attachment)
                                     t
                                     "Required function `org-publish-attachment' is unavailable.")
          (org-roam-blog--capability 'org-roam-node-list
                                     (fboundp 'org-roam-node-list)
                                     t
                                     "Required function `org-roam-node-list' is unavailable.")
          (org-roam-blog--capability 'org-roam-db-query
                                     (fboundp 'org-roam-db-query)
                                     t
                                     "Required function `org-roam-db-query' is unavailable.")
          (org-roam-blog--capability 'url-parse
                                     (fboundp 'url-generic-parse-url)
                                     t
                                     "Required function `url-generic-parse-url' is unavailable.")
          (org-roam-blog--capability 'real-path
                                     (fboundp 'file-truename)
                                     t
                                     "Required function `file-truename' is unavailable.")
          (org-roam-blog--capability 'staging
                                     (and (fboundp 'make-temp-file)
                                          (fboundp 'rename-file)
                                          (fboundp 'copy-file))
                                     t
                                     "Required staging and file-promotion functions are unavailable.")
          (org-roam-blog--capability 'org-publish-index
                                     (and (fboundp 'org-publish-collect-index)
                                          (fboundp 'org-publish-index-generate-theindex)
                                          (fboundp 'org-publish-cache-get)
                                          (fboundp 'org-publish-cache-set)
                                          (fboundp 'org-publish-update-timestamp)
                                          (fboundp 'org-publish-get-base-files))
                                     theindex-enabled
                                     (concat "One or more required native Org index APIs are "
                                             "unavailable: `org-publish-collect-index', "
                                             "`org-publish-index-generate-theindex', "
                                             "`org-publish-cache-get', `org-publish-cache-set', "
                                             "`org-publish-update-timestamp', or "
                                             "`org-publish-get-base-files'.")))))

(defun org-roam-blog--collect-diagnostics ()
  "Return variable and required-capability diagnostics."
  (let ((diagnostics (org-roam-blog--validate-variables)))
    (dolist (capability (org-roam-blog--check-capabilities))
      (when (and (plist-get capability
                            :required)
                 (not (plist-get capability
                                 :available)))
        (push (org-roam-blog--diagnostic 'error
                                         (plist-get capability
                                                    :name)
                                         (plist-get capability
                                                    :detail))
              diagnostics)))
    (nreverse diagnostics)))

(defun org-roam-blog--diagnostics-have-errors-p (diagnostics)
  "Return non-nil when DIAGNOSTICS contains an error."
  (cl-some (lambda (diagnostic)
             (eq (plist-get diagnostic
                            :severity)
                 'error))
           diagnostics))

(defun org-roam-blog--prepare-publication ()
  "Build and validate a publication plan without writing output.

Return a plist containing `:status', `:entries', `:static', `:plan',
and `:diagnostics'.  Configuration or capability errors prevent
database queries.  Manifest, static enumeration, target, and conflict
errors prevent publication."
  (let ((diagnostics (org-roam-blog--collect-diagnostics))
        entries static plan)
    (unless (org-roam-blog--diagnostics-have-errors-p diagnostics)
      (let ((manifest (org-roam-blog--build-manifest)))
        (setq entries (plist-get manifest
                                 :entries))
        (setq diagnostics (append diagnostics
                                  (plist-get manifest
                                             :diagnostics)))))
    (unless (org-roam-blog--diagnostics-have-errors-p diagnostics)
      (condition-case error-data
          (setq static (org-roam-blog--static-files)
                plan (append (org-roam-blog--generated-output-plan entries)
                             (org-roam-blog--static-output-plan static))
                diagnostics (append diagnostics
                                    (org-roam-blog--output-conflicts plan)
                                    (org-roam-blog--output-target-diagnostics plan)))
        (error (setq diagnostics (append diagnostics
                                         (list (org-roam-blog--diagnostic 'error
                                                                          'publication-plan
                                                                          (error-message-string error-data))))))))
    (list :status (if (org-roam-blog--diagnostics-have-errors-p diagnostics)
                      'failure
                    'success)
          :entries entries
          :static static
          :plan plan
          :diagnostics diagnostics)))

(defun org-roam-blog--publish ()
  "Run one complete Org-roam Blog publication and return its result.

The result records `:status', `:staging', `:static-published',
`:promoted', `:plan', and `:diagnostics'.  Preflight failure performs
no publication writes.  Generated output is fully staged before
static files are copied, then generated content is promoted in
content, sitemap, and redirect order."
  (let* ((prepared (org-roam-blog--prepare-publication))
         (diagnostics (plist-get prepared
                                 :diagnostics))
         (plan (plist-get prepared
                          :plan)))
    (if (eq (plist-get prepared
                       :status)
            'failure)
        (list :status 'failure
              :staging nil
              :static-published nil
              :promoted nil
              :plan plan
              :diagnostics diagnostics)
      (let ((staged (org-roam-blog--stage-generated-batch (plist-get prepared
                                                                     :entries))))
        (if (eq (plist-get staged
                           :status)
                'failure)
            (list :status 'failure
                  :staging (plist-get staged
                                      :staging)
                  :static-published nil
                  :promoted nil
                  :plan plan
                  :diagnostics (append diagnostics
                                       (plist-get staged
                                                  :diagnostics)))
          (let ((static-result (org-roam-blog--publish-static-batch (plist-get prepared
                                                                               :static))))
            (if (eq (plist-get static-result
                               :status)
                    'failure)
                (list :status 'failure
                      :staging (plist-get staged
                                          :staging)
                      :static-published (plist-get static-result
                                                   :published)
                      :promoted nil
                      :plan plan
                      :diagnostics (append diagnostics
                                           (plist-get static-result
                                                      :diagnostics)))
              (let ((promoted (org-roam-blog--promote-generated-batch staged)))
                (list :status (plist-get promoted
                                         :status)
                      :staging (plist-get promoted
                                          :staging)
                      :static-published (plist-get static-result
                                                   :published)
                      :promoted (plist-get promoted
                                           :promoted)
                      :plan plan
                      :diagnostics (append diagnostics
                                           (plist-get promoted
                                                      :diagnostics)))))))))))

(define-derived-mode org-roam-blog-diagnostics-mode
  special-mode
  "Org-roam-Blog-Diagnostics"
  "Major mode for an Org-roam Blog diagnostics report.")

(defun org-roam-blog--render-diagnostics (diagnostics)
  "Display DIAGNOSTICS in a read-only report buffer."
  (let ((buffer (get-buffer-create "*Org-roam Blog Diagnostics*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Org-roam Blog diagnostics\n\n")
        (dolist (diagnostic diagnostics)
          (insert (format "%s  %s\n  %s\n\n"
                          (upcase (symbol-name (plist-get diagnostic
                                                          :severity)))
                          (plist-get diagnostic
                                     :subject)
                          (plist-get diagnostic
                                     :message))))
        (goto-char (point-min))
        (org-roam-blog-diagnostics-mode)))
    (display-buffer buffer)))

;;;###autoload
(defun org-roam-blog-check ()
  "Validate Org-roam Blog configuration and required capabilities.

The command is read-only: it does not synchronize Org-roam, create
directories, export files, or alter global Org Publish state.  On
failure it displays a diagnostics buffer and returns nil.  On success
it reports a short message and returns non-nil."
  (interactive)
  (let ((diagnostics (org-roam-blog--collect-diagnostics)))
    (if diagnostics
        (progn
          (org-roam-blog--render-diagnostics diagnostics)
          nil)
      (message "Org-roam Blog configuration and capabilities are valid")
      t)))

;;;###autoload
(defun org-roam-blog-publish ()
  "Publish the configured Org-roam blog and return a result plist.

Validate configuration and capabilities, query Org-roam, construct
the complete output plan, and reject conflicts before writing.  Stage
all generated Org output, publish static attachments directly, and
then promote generated content.  Apply configured export variable
bindings dynamically for each generated Org document and restore
their previous values afterwards.  The command never synchronizes
the Org-roam database or permanently modifies Org Publish
configuration.  Org links retain the selected export backend's native
semantics; this package does not rewrite `id:' links or compensate
for mismatches between their fragments and exported anchors.

On failure, display the unified diagnostics report.  A retained
staging directory and any partially published targets are included in
the returned result."
  (interactive)
  (let ((result (org-roam-blog--publish)))
    (if (eq (plist-get result
                       :status)
            'success)
        (message "Org-roam Blog publication completed")
      (org-roam-blog--render-diagnostics (plist-get result
                                                    :diagnostics)))
    result))

(provide 'org-roam-blog)

;;; org-roam-blog.el ends here
