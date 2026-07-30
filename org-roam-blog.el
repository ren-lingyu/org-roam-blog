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
;; while preserving standard Org export behavior.
;; Link resolution, including the HTML anchors emitted for `id:' links,
;; remains the responsibility of Org and the selected export backend.
;;
;; The implementation and user-facing configuration are under development.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'ox)
(require 'ox-html)
(require 'ox-publish)
(require 'org-roam)
(require 'subr-x)
(require 'url-parse)
(require 'url-util)

(defgroup org-roam-blog nil
  "Publish an Org-roam database selection as a static HTML blog."
  :group 'org-roam
  :prefix "org-roam-blog-")

(defcustom org-roam-blog-directory nil
  "Root directory containing Org files eligible for blog publication.

The Org-roam database is the only source used to select files.  This
directory limits that selection and provides the base from which
source-relative store paths are calculated.  The value must be an
absolute directory name.  Org-roam Blog does not synchronize the
Org-roam database."
  :type '(choice (const :tag "Not configured" nil)
                 directory)
  :group 'org-roam-blog)

(defcustom org-roam-blog-publish-directory nil
  "Root directory for all published website files.

Content store files, redirects, sitemap, theindex, and static files
must resolve below this directory.  The value must be an absolute
directory name."
  :type '(choice (const :tag "Not configured" nil)
                 directory)
  :group 'org-roam-blog)

(defcustom org-roam-blog-publish-store "_org"
  "Directory below `org-roam-blog-publish-directory' for content.

The value is a non-empty relative directory name.  Published Org
files mirror their paths relative to `org-roam-blog-directory' below
this directory."
  :type 'string
  :group 'org-roam-blog)

(defcustom org-roam-blog-site-url nil
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

(defcustom org-roam-blog-temporary-directory nil
  "Parent directory for per-publication staging directories.

Nil means to use `temporary-file-directory'.  A non-nil value must be
an absolute directory name.  Each publication creates a unique child
directory for generated content, sitemap, theindex, and redirects.
Static files do not pass through this staging directory."
  :type '(choice (const :tag "Emacs temporary directory" nil)
                 directory)
  :group 'org-roam-blog)

(defcustom org-roam-blog-default-template nil
  "Default external Org export options used for generated HTML.

The value is a plist of options accepted by Org Export and `ox-html'.
Org-roam Blog shallowly merges an object's `:template' over this
value.  An explicitly present nil value is an override.  The package
does not interpret or whitelist exporter-specific option keys."
  :type 'plist
  :group 'org-roam-blog)

(defcustom org-roam-blog-content nil
  "Rules selecting Org-roam files and describing their publication.

Each element is a plist with this schema:

  (:name NAME :tags TAGS :directory DIRECTORY
   :sitemap BOOLEAN :theindex BOOLEAN :template PLIST)

NAME is a unique non-empty string.  TAGS is a non-empty list of
strings, all of which must occur on a level-0 Org-roam node.
DIRECTORY is nil or a directory relative to
`org-roam-blog-publish-directory' in which a redirect is generated.
The two boolean fields select generated indexes.  TEMPLATE shallowly
overrides `org-roam-blog-default-template'.

A file matching more than one rule is an unsupported configuration
and will be diagnosed before publication."
  :type '(repeat plist)
  :group 'org-roam-blog)

(defcustom org-roam-blog-static nil
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
   :content-function FUNCTION-OR-NIL :template PLIST)

Only tags explicitly listed in `:visible-tags' are displayed by the
sitemap.  A missing or nil value displays no tags.  This whitelist
never selects content.  When non-nil, `:content-function' is called
with the prepared manifest entries and this configuration plist, and
must return an Org source string."
  :type 'plist
  :group 'org-roam-blog)

(defcustom org-roam-blog-theindex
  '(:enable nil)
  "Configuration for the optional generated Org index.

The supported schema is:

  (:enable BOOLEAN :path RELATIVE-FILE :title STRING :template PLIST)

When disabled, capabilities needed only for index collection are not
required."
  :type 'plist
  :group 'org-roam-blog)

(defconst org-roam-blog--content-keys
  '(:name :tags :directory :sitemap :theindex :template))

(defconst org-roam-blog--static-keys
  '(:source :directory :extensions))

(defconst org-roam-blog--default-static-extensions
  "css\\|js\\|png\\|svg\\|jpg\\|jpeg\\|gif\\|webp\\|ico\\|pdf\\|woff\\|woff2"
  "Default regexp matching static file extensions.")

(defconst org-roam-blog--sitemap-keys
  '(:enable :path :title :sort :visible-tags :content-function
    :template))

(defconst org-roam-blog--theindex-keys
  '(:enable :path :title :template))

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
    (error "Unsafe relative URL paths: %S and %S" from-file to-file))
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
    (error "Unsafe relative URL path: %S" relative-path))
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
    (error "Unsafe relative output path: %S" relative-path))
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
  (let ((tags (plist-get rule :tags)))
    (cl-remove-if-not
     (lambda (node)
       (org-roam-blog--node-matches-tags-p node tags))
     (org-roam-node-list))))

(defun org-roam-blog--manifest-entry (node rule)
  "Build a manifest entry for Org-roam NODE selected by RULE.

Return a cons whose car is the entry and whose cdr is nil on success.
On failure return a cons whose car is nil and whose cdr is a
diagnostic."
  (let* ((source (expand-file-name (org-roam-node-file node)))
         (source-root
          (file-name-as-directory
           (expand-file-name org-roam-blog-directory))))
    (condition-case error-data
        (if (not (org-roam-blog--path-inside-p source source-root))
            (cons nil
                  (org-roam-blog--diagnostic
                   'error (plist-get rule :name)
                   (format "Source is outside the blog directory: %s"
                           source)))
          (let* ((source-relative (file-relative-name source source-root))
                 (store-relative
                  (org-roam-blog--replace-extension
                   (concat
                    (file-name-as-directory org-roam-blog-publish-store)
                    source-relative)
                   ".html"))
                 (store-output
                  (org-roam-blog--output-path store-relative))
                 (directory (plist-get rule :directory))
                 (redirect-relative
                  (when directory
                    (concat
                     (unless (string= directory ".")
                       (file-name-as-directory directory))
                     (org-roam-blog--replace-extension
                      (file-name-nondirectory source) ".html")))))
            (cons
             (list
              :id (org-roam-node-id node)
              :title (org-roam-node-title node)
              :source source
              :source-truename (file-truename source)
              :source-relative source-relative
              :store-output store-output
              :store-relative store-relative
              :store-url (org-roam-blog--encode-url-path store-relative)
              :redirect-relative redirect-relative
              :content-name (plist-get rule :name)
              :tags (copy-sequence (org-roam-node-tags node))
              :date nil
              :sitemap (and (plist-get rule :sitemap) t)
              :theindex (and (plist-get rule :theindex) t)
              :template
              (org-roam-blog--merge-template
               org-roam-blog-default-template
               (plist-get rule :template)))
             nil)))
      (file-error
       (cons nil
             (org-roam-blog--diagnostic
              'error (plist-get rule :name)
              (format "Cannot resolve source file %s: %s"
                      source (error-message-string error-data))))))))

(defun org-roam-blog--build-manifest ()
  "Build and return the current publication manifest.

The return value is a plist with `:entries' and `:diagnostics'.  Files
are selected only through the Org-roam database.  A real source file
matching multiple content rules is diagnosed as unsupported.  A
second database node for the same real file and rule is ignored and
reported as a warning."
  (let ((by-truename (make-hash-table :test #'equal))
        entries diagnostics)
    (dolist (rule org-roam-blog-content)
      (dolist (node (org-roam-blog--query-rule-nodes rule))
        (pcase-let ((`(,entry . ,diagnostic)
                     (org-roam-blog--manifest-entry node rule)))
          (if diagnostic
              (push diagnostic diagnostics)
            (let* ((truename (plist-get entry :source-truename))
                   (previous (gethash truename by-truename)))
              (cond
               ((null previous)
                (puthash truename entry by-truename)
                (push entry entries))
               ((not (equal (plist-get previous :content-name)
                            (plist-get entry :content-name)))
                (push
                 (org-roam-blog--diagnostic
                  'error truename
                  (format "File matches content rules %S and %S."
                          (plist-get previous :content-name)
                          (plist-get entry :content-name)))
                 diagnostics))
               (t
                (push
                 (org-roam-blog--diagnostic
                  'warning truename
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
      (push
       (org-roam-blog--plan-item
        'content (plist-get entry :source)
        (plist-get entry :store-output)
        (plist-get entry :content-name))
       items)
      (when-let* ((redirect (plist-get entry :redirect-relative)))
        (push
         (org-roam-blog--plan-item
          'redirect (plist-get entry :source)
          (org-roam-blog--output-path redirect)
          (plist-get entry :content-name))
         items)))
    (when (plist-get org-roam-blog-sitemap :enable)
      (push
       (org-roam-blog--plan-item
        'sitemap 'manifest
        (org-roam-blog--output-path
         (plist-get org-roam-blog-sitemap :path))
        'org-roam-blog-sitemap)
       items))
    (when (plist-get org-roam-blog-theindex :enable)
      (push
       (org-roam-blog--plan-item
        'theindex 'manifest
        (org-roam-blog--output-path
         (plist-get org-roam-blog-theindex :path))
        'org-roam-blog-theindex)
       items))
    (nreverse items)))

(defun org-roam-blog--static-extension-regexp (mapping)
  "Return the complete file regexp for static MAPPING."
  (format
   "\\.\\(?:%s\\)\\'"
   (or (plist-get mapping :extensions)
       org-roam-blog--default-static-extensions)))

(defun org-roam-blog--static-target-relative (mapping source-relative)
  "Return publication-relative target for MAPPING and SOURCE-RELATIVE."
  (let ((directory (plist-get mapping :directory)))
    (if (equal directory ".")
        source-relative
      (concat (file-name-as-directory directory) source-relative))))

(defun org-roam-blog--static-files ()
  "Return static file records selected by `org-roam-blog-static'.

Each record contains `:source', `:source-relative', `:target',
`:target-relative', `:mapping', and `:owner'.  Directory traversal is
recursive and does not follow symlinked directories.  A selected file
whose true path escapes its configured source directory signals an
error."
  (let (records)
    (cl-loop
     for mapping in org-roam-blog-static
     for index from 0
     for owner = (format "org-roam-blog-static[%d]" index)
     for base = (file-name-as-directory
                 (expand-file-name (plist-get mapping :source)))
     for regexp = (org-roam-blog--static-extension-regexp mapping)
     do
     (unless (file-directory-p base)
       (error "Static source directory does not exist: %s" base))
     (dolist (source
              (directory-files-recursively base regexp nil nil nil))
       (unless (and (file-regular-p source)
                    (org-roam-blog--path-inside-p
                     (file-truename source) (file-truename base)))
         (error "Static source escapes its configured directory: %s"
                source))
       (let* ((source-relative (file-relative-name source base))
              (target-relative
               (org-roam-blog--static-target-relative
                mapping source-relative)))
         (push
          (list :source source
                :source-relative source-relative
                :target (org-roam-blog--output-path target-relative)
                :target-relative target-relative
                :mapping mapping
                :owner owner)
          records)))
     finally return (nreverse records))))

(defun org-roam-blog--static-output-plan (records)
  "Return output plan items for static file RECORDS."
  (mapcar
   (lambda (record)
     (org-roam-blog--plan-item
      'static (plist-get record :source)
      (plist-get record :target)
      (plist-get record :owner)))
   records))

(defun org-roam-blog--publish-static (records)
  "Publish static file RECORDS directly to their final targets.

Use `org-publish-attachment' for copying while preserving the source
tree below each mapping.  Return the final target paths in publication
order.  This function does not modify `org-publish-project-alist'."
  (let (published)
    (dolist (record records)
      (push (org-roam-blog--publish-static-record record) published))
    (nreverse published)))

(defun org-roam-blog--publish-static-record (record)
  "Publish one static RECORD and return its final target."
  (let* ((source (plist-get record :source))
         (target (plist-get record :target))
         (mapping (plist-get record :mapping))
         (project
          (list :base-directory
                (file-name-as-directory
                 (expand-file-name (plist-get mapping :source)))
                :publishing-directory
                (file-name-directory target))))
    (unless (org-roam-blog--promotable-target-p target)
      (error "Refusing to replace non-regular static target: %s"
             target))
    (make-directory (file-name-directory target) t)
    (org-publish-attachment
     project source (file-name-directory target))
    target))

(defun org-roam-blog--publish-static-batch (records)
  "Publish static RECORDS and return a result plist.

The result contains `:status', `:published', and `:diagnostics'.  On
failure, `:published' lists the targets copied before the error."
  (let (published diagnostics)
    (condition-case error-data
        (progn
          (dolist (record records)
            (push (org-roam-blog--publish-static-record record)
                  published))
          (list :status 'success
                :published (nreverse published)
                :diagnostics nil))
      (error
       (push
        (org-roam-blog--diagnostic
         'error 'static (error-message-string error-data))
        diagnostics)
       (list :status 'failure
             :published (nreverse published)
             :diagnostics (nreverse diagnostics))))))

(defun org-roam-blog--output-conflicts (items)
  "Return diagnostics for exact target collisions in plan ITEMS."
  (let ((targets (make-hash-table :test #'equal))
        diagnostics)
    (dolist (item items)
      (let* ((target (expand-file-name (plist-get item :target)))
             (previous (gethash target targets)))
        (if previous
            (push
             (org-roam-blog--diagnostic
              'error target
              (format "Output conflict between %S (%S) and %S (%S)."
                      (plist-get previous :kind)
                      (plist-get previous :owner)
                      (plist-get item :kind)
                      (plist-get item :owner)))
             diagnostics)
          (puthash target item targets))))
    (nreverse diagnostics)))

(defun org-roam-blog--output-target-diagnostics (items)
  "Return diagnostics for unsafe or non-promotable plan ITEMS."
  (let (diagnostics)
    (dolist (item items)
      (let ((target (plist-get item :target)))
        (unless (file-in-directory-p
                 target org-roam-blog-publish-directory)
          (push
           (org-roam-blog--diagnostic
            'error target "Output target escapes the publication directory.")
           diagnostics))
        (unless (org-roam-blog--promotable-target-p target)
          (push
           (org-roam-blog--diagnostic
            'error target
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
         (temporary-file-directory
          (file-name-as-directory (expand-file-name parent)))
         (prefix
          (format "org-roam-blog-%s-"
                  (format-time-string "%Y%m%dT%H%M%S"))))
    (make-temp-file prefix t)))

(defun org-roam-blog--staging-output (staging relative-path)
  "Return the output path below STAGING for RELATIVE-PATH."
  (unless (org-roam-blog--relative-file-p relative-path)
    (error "Unsafe staging output path: %S" relative-path))
  (expand-file-name relative-path
                    (file-name-as-directory staging)))

(defun org-roam-blog--export-content-entry (entry staging)
  "Export manifest ENTRY from disk into STAGING.

The source file is read into a fresh temporary buffer, so unsaved
changes in an existing visiting buffer are ignored.  Standard Org
export hooks and filters remain active.  Links are passed to Org
unchanged; in particular, this package does not repair or reinterpret
`id:' links or their HTML anchors.  Return the staged output file."
  (let* ((source (plist-get entry :source))
         (relative (plist-get entry :store-relative))
         (output (org-roam-blog--staging-output staging relative))
         (template (plist-get entry :template)))
    (make-directory (file-name-directory output) t)
    (with-temp-buffer
      (insert-file-contents source)
      (setq buffer-file-name source
            default-directory (file-name-directory source))
      (org-mode)
      (org-export-to-file
       'html output nil nil nil nil template))
    output))

(defun org-roam-blog--stage-content (entries staging)
  "Export manifest ENTRIES into STAGING.

Return a list of cons cells pairing each entry with its staged output.
Signal the original export error on failure."
  (mapcar
   (lambda (entry)
     (cons entry
           (org-roam-blog--export-content-entry entry staging)))
   entries))

(defun org-roam-blog--html-attribute-escape (value)
  "Escape VALUE for a double-quoted HTML attribute."
  (let ((escaped (org-html-encode-plain-text value)))
    (setq escaped
          (replace-regexp-in-string "\"" "&quot;" escaped t t))
    (replace-regexp-in-string "'" "&#39;" escaped t t)))

(defun org-roam-blog--redirect-html (entry)
  "Return a static HTML redirect document for manifest ENTRY."
  (let* ((redirect (plist-get entry :redirect-relative))
         (store (plist-get entry :store-relative))
         (target (org-roam-blog--relative-url redirect store))
         (attribute-target
          (org-roam-blog--html-attribute-escape target))
         (title
          (org-roam-blog--html-attribute-escape
           (or (plist-get entry :title) "Redirect")))
         (javascript-target (json-serialize target)))
    (concat
     "<!doctype html>\n"
     "<html lang=\"en\">\n"
     "<head>\n"
     "<meta charset=\"utf-8\">\n"
     "<meta http-equiv=\"refresh\" content=\"0; url="
     attribute-target "\">\n"
     "<link rel=\"canonical\" href=\"" attribute-target "\">\n"
     "<title>" title "</title>\n"
     "<script>location.replace(" javascript-target ");</script>\n"
     "</head>\n"
     "<body><p><a href=\"" attribute-target "\">"
     title "</a></p></body>\n"
     "</html>\n")))

(defun org-roam-blog--stage-redirects (entries staging)
  "Generate redirects for manifest ENTRIES below STAGING.

Return a list of cons cells pairing each entry with its staged
redirect file."
  (let (staged)
    (dolist (entry entries)
      (when-let* ((relative (plist-get entry :redirect-relative)))
        (let ((output
               (org-roam-blog--staging-output staging relative)))
          (make-directory (file-name-directory output) t)
          (write-region (org-roam-blog--redirect-html entry)
                        nil output nil 'silent)
          (push (cons entry output) staged))))
    (nreverse staged)))

(defun org-roam-blog--project-sitemap-tags (tags config)
  "Return members of TAGS listed by sitemap CONFIG as visible."
  (let ((visible (plist-get config :visible-tags)))
    (cl-remove-if-not
     (lambda (tag) (member tag visible))
     tags)))

(defun org-roam-blog--sitemap-entry-time (entry)
  "Return a sortable time value from sitemap ENTRY, or nil."
  (let ((date (plist-get entry :date)))
    (cond
     ((null date) nil)
     ((stringp date)
      (condition-case nil
          (org-time-string-to-time date)
        (error nil)))
     ((listp date) date)
     (t nil))))

(defun org-roam-blog--prepare-sitemap-entries (entries config)
  "Filter and prepare manifest ENTRIES according to sitemap CONFIG."
  (let ((prepared
         (mapcar
          (lambda (entry)
            (let ((copy (copy-sequence entry)))
              (plist-put
               copy :tags
               (org-roam-blog--project-sitemap-tags
                (plist-get copy :tags) config))))
          (cl-remove-if-not
           (lambda (entry) (plist-get entry :sitemap))
           entries))))
    (if (eq (plist-get config :sort) 'anti-chronologically)
        (cl-stable-sort
         prepared
         (lambda (left right)
           (let ((left-time
                  (org-roam-blog--sitemap-entry-time left))
                 (right-time
                  (org-roam-blog--sitemap-entry-time right)))
             (cond
              ((and left-time right-time)
               (time-less-p right-time left-time))
              (left-time t)
              (t nil)))))
      prepared)))

(defun org-roam-blog--org-link-description (value)
  "Escape VALUE for use as an Org link description."
  (replace-regexp-in-string
   "]" "\\\\]" (replace-regexp-in-string
                 "[\n\r]+" " " (or value "") t t)
   t t))

(defun org-roam-blog--default-sitemap-content (entries config)
  "Return default Org sitemap content for ENTRIES and CONFIG."
  (let ((path (plist-get config :path))
        (title (or (plist-get config :title) "Sitemap")))
    (concat
     "#+TITLE: " (replace-regexp-in-string "[\n\r]+" " " title t t)
     "\n\n"
     (mapconcat
      (lambda (entry)
        (let* ((url
                (org-roam-blog--relative-url
                 path (plist-get entry :store-relative)))
               (description
                (org-roam-blog--org-link-description
                 (or (plist-get entry :title)
                     (plist-get entry :source-relative))))
               (tags (plist-get entry :tags)))
          (concat "- [[file:" url "][" description "]]"
                  (when tags
                    (concat
                     " ("
                     (mapconcat
                      #'org-roam-blog--org-link-description
                      tags ", ")
                     ")")))))
      entries "\n")
     (when entries "\n"))))

(defun org-roam-blog--sitemap-content (entries)
  "Return Org sitemap source for manifest ENTRIES.

The configured content function is called as (FUNCTION ENTRIES
CONFIG), where ENTRIES have already been filtered, sorted, and had
their displayed tags projected.  It must return an Org source
string."
  (let* ((config org-roam-blog-sitemap)
         (prepared
          (org-roam-blog--prepare-sitemap-entries entries config))
         (function
          (or (plist-get config :content-function)
              #'org-roam-blog--default-sitemap-content))
         (content (funcall function prepared config)))
    (unless (stringp content)
      (error "Sitemap content function must return a string"))
    content))

(defun org-roam-blog--stage-sitemap (entries staging)
  "Generate and stage the configured sitemap from manifest ENTRIES.

Return a cons pairing the sitemap target-relative path with its staged
file, or nil when sitemap generation is disabled."
  (when (plist-get org-roam-blog-sitemap :enable)
    (let* ((relative (plist-get org-roam-blog-sitemap :path))
           (output
            (org-roam-blog--staging-output staging relative))
           (template
            (org-roam-blog--merge-template
             org-roam-blog-default-template
             (plist-get org-roam-blog-sitemap :template))))
      (make-directory (file-name-directory output) t)
      (with-temp-buffer
        (insert (org-roam-blog--sitemap-content entries))
        (org-mode)
        ;; `org-mode' establishes buffer-local path state.  Set the
        ;; virtual source location afterwards so relative links are
        ;; checked from the staged sitemap's directory.
        (setq buffer-file-name
              (org-roam-blog--replace-extension output ".org")
              default-directory (file-name-directory output))
        (org-export-to-file
         'html output nil nil nil nil template))
      (cons relative output))))

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
  (make-directory (file-name-directory target) t)
  (copy-file staged target t t nil t)
  target)

(defun org-roam-blog--stage-generated-batch (entries)
  "Stage all generated output for manifest ENTRIES.

Return a result plist containing `:status', `:staging', staged
`:content', `:sitemap', `:redirects', and `:diagnostics'.  Failure
leaves the staging directory for inspection."
  (when (plist-get org-roam-blog-theindex :enable)
    (error "Theindex generation is not implemented"))
  (let ((staging (org-roam-blog--make-staging-directory))
        staged-content staged-sitemap staged-redirects diagnostics)
    (condition-case error-data
        (progn
          (setq staged-content
                (org-roam-blog--stage-content entries staging)
                staged-sitemap
                (org-roam-blog--stage-sitemap entries staging)
                staged-redirects
                (org-roam-blog--stage-redirects entries staging))
          (list :status 'success
                :staging staging
                :content staged-content
                :sitemap staged-sitemap
                :redirects staged-redirects
                :diagnostics nil))
      (error
       (push
        (org-roam-blog--diagnostic
         'error 'content
         (error-message-string error-data))
        diagnostics)
       (list :status 'failure
             :staging staging
             :diagnostics (nreverse diagnostics))))))

(defun org-roam-blog--promote-generated-batch (staged)
  "Promote a successful STAGED generated-output result.

Return a result plist with `:status', `:staging', `:promoted', and
`:diagnostics'.  Content is promoted first, followed by sitemap and
redirects.  Failure preserves the staging directory and reports
targets already promoted."
  (let ((staging (plist-get staged :staging))
        promoted diagnostics)
    (condition-case error-data
        (progn
          (dolist (pair (plist-get staged :content))
            (let ((target (plist-get (car pair) :store-output)))
              (org-roam-blog--promote-file (cdr pair) target)
              (push target promoted)))
          (when-let* ((sitemap (plist-get staged :sitemap)))
            (let ((target
                   (org-roam-blog--output-path (car sitemap))))
              (org-roam-blog--promote-file (cdr sitemap) target)
              (push target promoted)))
          (dolist (pair (plist-get staged :redirects))
            (let ((target
                   (org-roam-blog--output-path
                    (plist-get (car pair) :redirect-relative))))
              (org-roam-blog--promote-file (cdr pair) target)
              (push target promoted)))
          (delete-directory staging t)
          (list :status 'success
                :staging nil
                :promoted (nreverse promoted)
                :diagnostics nil))
      (error
       (push
        (org-roam-blog--diagnostic
         'error 'promotion (error-message-string error-data))
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
    (if (eq (plist-get staged :status) 'success)
        (org-roam-blog--promote-generated-batch staged)
      staged)))

(defun org-roam-blog--publish-content-batch (entries)
  "Stage and promote generated output for manifest ENTRIES.

This compatibility wrapper delegates to
`org-roam-blog--publish-generated-batch'."
  (org-roam-blog--publish-generated-batch entries))

(defun org-roam-blog--validate-known-plist
    (value allowed subject diagnostics)
  "Validate VALUE as a plist whose keys occur in ALLOWED.

SUBJECT identifies VALUE in generated messages.  Append diagnostics
to DIAGNOSTICS and return the resulting list."
  (if (not (org-roam-blog--plist-p value))
      (cons (org-roam-blog--diagnostic
             'error subject "Value must be a proper even-length plist.")
            diagnostics)
    (dolist (key (org-roam-blog--unknown-keys value allowed)
                 diagnostics)
      (push (org-roam-blog--diagnostic
             'error subject (format "Unknown key: %S" key))
            diagnostics))))

(defun org-roam-blog--validate-content (diagnostics)
  "Append content-rule diagnostics to DIAGNOSTICS."
  (if (not (listp org-roam-blog-content))
      (cons (org-roam-blog--diagnostic
             'error 'org-roam-blog-content "Value must be a list.")
            diagnostics)
    (let ((seen-names (make-hash-table :test #'equal)))
      (cl-loop
       for rule in org-roam-blog-content
       for index from 0
       for subject = (format "org-roam-blog-content[%d]" index)
       do
       (setq diagnostics
             (org-roam-blog--validate-known-plist
              rule org-roam-blog--content-keys subject diagnostics))
       (when (org-roam-blog--plist-p rule)
         (let ((name (plist-get rule :name))
               (tags (plist-get rule :tags))
               (directory (plist-get rule :directory))
               (template (plist-get rule :template)))
           (if (and (stringp name) (not (string-empty-p name)))
               (if (gethash name seen-names)
                   (push (org-roam-blog--diagnostic
                          'error subject
                          (format "Duplicate content name: %S" name))
                         diagnostics)
                 (puthash name t seen-names))
             (push (org-roam-blog--diagnostic
                    'error subject "The :name field must be non-empty.")
                   diagnostics))
           (unless (org-roam-blog--string-list-p tags t)
             (push (org-roam-blog--diagnostic
                    'error subject
                    "The :tags field must be a non-empty string list.")
                   diagnostics))
           (unless (or (null directory)
                       (org-roam-blog--relative-path-p directory t))
             (push (org-roam-blog--diagnostic
                    'error subject
                    (concat "The :directory field must be nil or a safe "
                            "relative path."))
                   diagnostics))
           (when (and (plist-member rule :template)
                      (not (org-roam-blog--plist-p template)))
             (push (org-roam-blog--diagnostic
                    'error subject "The :template field must be a plist.")
                   diagnostics))
           (dolist (key '(:sitemap :theindex))
             (when (and (plist-member rule key)
                        (not (booleanp (plist-get rule key))))
               (push (org-roam-blog--diagnostic
                      'error subject
                      (format "The %S field must be boolean." key))
                     diagnostics))))))
      diagnostics)))

(defun org-roam-blog--validate-static (diagnostics)
  "Append static-mapping diagnostics to DIAGNOSTICS."
  (if (not (listp org-roam-blog-static))
      (cons (org-roam-blog--diagnostic
             'error 'org-roam-blog-static "Value must be a list.")
            diagnostics)
    (cl-loop
     for mapping in org-roam-blog-static
     for index from 0
     for subject = (format "org-roam-blog-static[%d]" index)
     do
     (setq diagnostics
           (org-roam-blog--validate-known-plist
            mapping org-roam-blog--static-keys subject diagnostics))
     (when (org-roam-blog--plist-p mapping)
       (unless (org-roam-blog--absolute-directory-p
                (plist-get mapping :source))
         (push (org-roam-blog--diagnostic
                'error subject "The :source field must be absolute.")
               diagnostics))
       (unless (org-roam-blog--relative-path-p
                (plist-get mapping :directory) t)
         (push (org-roam-blog--diagnostic
                'error subject
                "The :directory field must be a safe relative path.")
               diagnostics))
       (let ((extensions (plist-get mapping :extensions)))
         (unless (or (null extensions) (stringp extensions))
           (push (org-roam-blog--diagnostic
                  'error subject
                  "The :extensions field must be nil or a regexp string.")
                 diagnostics))
         (when (stringp extensions)
           (condition-case nil
               (string-match-p extensions "")
             (invalid-regexp
              (push (org-roam-blog--diagnostic
                     'error subject
                     "The :extensions field is not a valid regexp.")
                    diagnostics))))))
     finally return diagnostics)))

(defun org-roam-blog--validate-sitemap (diagnostics)
  "Append sitemap diagnostics to DIAGNOSTICS."
  (let ((subject 'org-roam-blog-sitemap))
    (setq diagnostics
          (org-roam-blog--validate-known-plist
           org-roam-blog-sitemap org-roam-blog--sitemap-keys
           subject diagnostics))
    (when (org-roam-blog--plist-p org-roam-blog-sitemap)
      (let ((enabled (plist-get org-roam-blog-sitemap :enable)))
        (unless (booleanp enabled)
          (push (org-roam-blog--diagnostic
                 'error subject "The :enable field must be boolean.")
                diagnostics))
        (when enabled
          (unless (org-roam-blog--relative-file-p
                   (plist-get org-roam-blog-sitemap :path))
            (push (org-roam-blog--diagnostic
                   'error subject
                   "Enabled sitemap requires a safe relative :path.")
                  diagnostics)))
        (when (and (plist-member org-roam-blog-sitemap :visible-tags)
                   (not (org-roam-blog--string-list-p
                         (plist-get org-roam-blog-sitemap
                                    :visible-tags))))
          (push (org-roam-blog--diagnostic
                 'error subject
                 "The :visible-tags field must be nil or a string list.")
                diagnostics))
        (when (and (plist-member org-roam-blog-sitemap :content-function)
                   (let ((function
                          (plist-get org-roam-blog-sitemap
                                     :content-function)))
                     (not (or (null function) (functionp function)))))
          (push (org-roam-blog--diagnostic
                 'error subject
                 "The :content-function field must be nil or a function.")
                diagnostics))
        (when (and (plist-member org-roam-blog-sitemap :template)
                   (not (org-roam-blog--plist-p
                         (plist-get org-roam-blog-sitemap :template))))
          (push (org-roam-blog--diagnostic
                 'error subject "The :template field must be a plist.")
                diagnostics))))
    diagnostics))

(defun org-roam-blog--validate-theindex (diagnostics)
  "Append theindex diagnostics to DIAGNOSTICS."
  (let ((subject 'org-roam-blog-theindex))
    (setq diagnostics
          (org-roam-blog--validate-known-plist
           org-roam-blog-theindex org-roam-blog--theindex-keys
           subject diagnostics))
    (when (org-roam-blog--plist-p org-roam-blog-theindex)
      (let ((enabled (plist-get org-roam-blog-theindex :enable)))
        (unless (booleanp enabled)
          (push (org-roam-blog--diagnostic
                 'error subject "The :enable field must be boolean.")
                diagnostics))
        (when (and enabled
                   (not (org-roam-blog--relative-file-p
                         (plist-get org-roam-blog-theindex :path))))
          (push (org-roam-blog--diagnostic
                 'error subject
                 "Enabled theindex requires a safe relative :path.")
                diagnostics))
        (when (and (plist-member org-roam-blog-theindex :template)
                   (not (org-roam-blog--plist-p
                         (plist-get org-roam-blog-theindex :template))))
          (push (org-roam-blog--diagnostic
                 'error subject "The :template field must be a plist.")
                diagnostics))))
    diagnostics))

(defun org-roam-blog--validate-variables ()
  "Return diagnostics for all Org-roam Blog configuration variables.

This function is read-only.  It does not create directories,
synchronize Org-roam, or repair configuration."
  (let (diagnostics)
    (dolist (entry `((org-roam-blog-directory
                      . ,org-roam-blog-directory)
                     (org-roam-blog-publish-directory
                      . ,org-roam-blog-publish-directory)))
      (unless (org-roam-blog--absolute-directory-p (cdr entry))
        (push (org-roam-blog--diagnostic
               'error (car entry) "Value must be an absolute directory.")
              diagnostics)))
    (unless (org-roam-blog--relative-path-p
             org-roam-blog-publish-store)
      (push (org-roam-blog--diagnostic
             'error 'org-roam-blog-publish-store
             "Value must be a non-empty safe relative directory.")
            diagnostics))
    (unless (org-roam-blog--valid-site-url-p org-roam-blog-site-url)
      (push (org-roam-blog--diagnostic
             'error 'org-roam-blog-site-url
             (concat "Value must be nil or an absolute HTTP(S) URL ending "
                     "in / without query or fragment."))
            diagnostics))
    (unless (or (null org-roam-blog-temporary-directory)
                (org-roam-blog--absolute-directory-p
                 org-roam-blog-temporary-directory))
      (push (org-roam-blog--diagnostic
             'error 'org-roam-blog-temporary-directory
             "Value must be nil or an absolute directory.")
            diagnostics))
    (unless (org-roam-blog--plist-p org-roam-blog-default-template)
      (push (org-roam-blog--diagnostic
             'error 'org-roam-blog-default-template
             "Value must be a proper even-length plist.")
            diagnostics))
    (setq diagnostics (org-roam-blog--validate-content diagnostics)
          diagnostics (org-roam-blog--validate-static diagnostics)
          diagnostics (org-roam-blog--validate-sitemap diagnostics)
          diagnostics (org-roam-blog--validate-theindex diagnostics))
    (nreverse diagnostics)))

(defun org-roam-blog--capability (name available required detail)
  "Return a capability record.

NAME identifies the capability.  AVAILABLE and REQUIRED are booleans.
DETAIL describes the API being checked."
  (list :name name :available (and available t)
        :required (and required t) :detail detail))

(defun org-roam-blog--check-capabilities ()
  "Return capability records required by the current configuration.

The probes are read-only and do not export files, write caches, or
synchronize the Org-roam database."
  (let ((theindex-enabled
         (and (org-roam-blog--plist-p org-roam-blog-theindex)
              (plist-get org-roam-blog-theindex :enable))))
    (list
     (org-roam-blog--capability
      'org-export (fboundp 'org-export-to-file) t
      "`org-export-to-file' is available.")
     (org-roam-blog--capability
      'ox-html (fboundp 'org-html-export-to-html) t
      "`org-html-export-to-html' is available.")
     (org-roam-blog--capability
      'org-publish (fboundp 'org-publish-attachment) t
      "`org-publish-attachment' is available.")
     (org-roam-blog--capability
      'org-roam-db-query (fboundp 'org-roam-db-query) t
      "`org-roam-db-query' is available.")
     (org-roam-blog--capability
      'url-parse (fboundp 'url-generic-parse-url) t
      "`url-generic-parse-url' is available.")
     (org-roam-blog--capability
      'real-path (fboundp 'file-truename) t
      "`file-truename' is available.")
     (org-roam-blog--capability
      'staging (and (fboundp 'make-temp-file)
                    (fboundp 'rename-file)
                    (fboundp 'copy-file))
      t "Temporary directories and file promotion are available.")
     (org-roam-blog--capability
      'org-publish-index (fboundp 'org-publish-collect-index)
      theindex-enabled "`org-publish-collect-index' is available."))))

(defun org-roam-blog--collect-diagnostics ()
  "Return variable and required-capability diagnostics."
  (let ((diagnostics (org-roam-blog--validate-variables)))
    (dolist (capability (org-roam-blog--check-capabilities))
      (when (and (plist-get capability :required)
                 (not (plist-get capability :available)))
        (push (org-roam-blog--diagnostic
               'error (plist-get capability :name)
               (plist-get capability :detail))
              diagnostics)))
    (nreverse diagnostics)))

(defun org-roam-blog--diagnostics-have-errors-p (diagnostics)
  "Return non-nil when DIAGNOSTICS contains an error."
  (cl-some
   (lambda (diagnostic)
     (eq (plist-get diagnostic :severity) 'error))
   diagnostics))

(defun org-roam-blog--prepare-publication ()
  "Build and validate a publication plan without writing output.

Return a plist containing `:status', `:entries', `:static', `:plan',
and `:diagnostics'.  Configuration or capability errors prevent
database queries.  Manifest, static enumeration, target, and conflict
errors prevent publication."
  (let ((diagnostics (org-roam-blog--collect-diagnostics))
        entries static plan)
    (when (and (not (org-roam-blog--diagnostics-have-errors-p
                     diagnostics))
               (plist-get org-roam-blog-theindex :enable))
      (push
       (org-roam-blog--diagnostic
        'error 'org-roam-blog-theindex
        "Theindex publication is not implemented.")
       diagnostics))
    (unless (org-roam-blog--diagnostics-have-errors-p diagnostics)
      (let ((manifest (org-roam-blog--build-manifest)))
        (setq entries (plist-get manifest :entries)
              diagnostics
              (append diagnostics
                      (plist-get manifest :diagnostics)))))
    (unless (org-roam-blog--diagnostics-have-errors-p diagnostics)
      (condition-case error-data
          (setq static (org-roam-blog--static-files)
                plan
                (append
                 (org-roam-blog--generated-output-plan entries)
                 (org-roam-blog--static-output-plan static))
                diagnostics
                (append
                 diagnostics
                 (org-roam-blog--output-conflicts plan)
                 (org-roam-blog--output-target-diagnostics plan)))
        (error
         (setq diagnostics
               (append
                diagnostics
                (list
                 (org-roam-blog--diagnostic
                  'error 'publication-plan
                  (error-message-string error-data))))))))
    (list :status
          (if (org-roam-blog--diagnostics-have-errors-p diagnostics)
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
         (diagnostics (plist-get prepared :diagnostics))
         (plan (plist-get prepared :plan)))
    (if (eq (plist-get prepared :status) 'failure)
        (list :status 'failure :staging nil
              :static-published nil :promoted nil
              :plan plan :diagnostics diagnostics)
      (let ((staged
             (org-roam-blog--stage-generated-batch
              (plist-get prepared :entries))))
        (if (eq (plist-get staged :status) 'failure)
            (list :status 'failure
                  :staging (plist-get staged :staging)
                  :static-published nil :promoted nil
                  :plan plan
                  :diagnostics
                  (append diagnostics
                          (plist-get staged :diagnostics)))
          (let ((static-result
                 (org-roam-blog--publish-static-batch
                  (plist-get prepared :static))))
            (if (eq (plist-get static-result :status) 'failure)
                (list :status 'failure
                      :staging (plist-get staged :staging)
                      :static-published
                      (plist-get static-result :published)
                      :promoted nil :plan plan
                      :diagnostics
                      (append diagnostics
                              (plist-get static-result :diagnostics)))
              (let ((promoted
                     (org-roam-blog--promote-generated-batch staged)))
                (list
                 :status (plist-get promoted :status)
                 :staging (plist-get promoted :staging)
                 :static-published
                 (plist-get static-result :published)
                 :promoted (plist-get promoted :promoted)
                 :plan plan
                 :diagnostics
                 (append diagnostics
                         (plist-get promoted :diagnostics)))))))))))

(define-derived-mode org-roam-blog-diagnostics-mode special-mode
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
                          (upcase
                           (symbol-name
                            (plist-get diagnostic :severity)))
                          (plist-get diagnostic :subject)
                          (plist-get diagnostic :message))))
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
then promote generated content.  The command never synchronizes the
Org-roam database or permanently modifies Org Publish configuration.
Org links retain the selected export backend's native semantics; this
package does not rewrite `id:' links or compensate for mismatches
between their fragments and exported anchors.

On failure, display the unified diagnostics report.  A retained
staging directory and any partially published targets are included in
the returned result."
  (interactive)
  (let ((result (org-roam-blog--publish)))
    (if (eq (plist-get result :status) 'success)
        (message "Org-roam Blog publication completed")
      (org-roam-blog--render-diagnostics
       (plist-get result :diagnostics)))
    result))

(provide 'org-roam-blog)

;;; org-roam-blog.el ends here
