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
;;
;; The implementation and user-facing configuration are under development.

;;; Code:

(require 'cl-lib)
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
   :include-tags TAGS-OR-NIL :exclude-tags TAGS-OR-NIL
   :content-function FUNCTION-OR-NIL :template PLIST)

Tag options affect only tags displayed by the sitemap and never
select content.  A nil `:include-tags' value disables the whitelist.
The content function protocol remains provisional during the first
implementation."
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

(defconst org-roam-blog--sitemap-keys
  '(:enable :path :title :sort :include-tags :exclude-tags
    :content-function :template))

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
and theindex targets.  Static targets are added later when static
source enumeration is implemented."
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
export hooks and filters remain active.  Return the staged output
file."
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

(defun org-roam-blog--publish-content-batch (entries)
  "Stage and promote all content manifest ENTRIES.

Return a result plist with `:status', `:staging', `:promoted', and
`:diagnostics'.  Status is `success' only when every entry was
generated, promoted, and the staging directory was removed.

Generation failure occurs before promotion and leaves the staging
directory for inspection.  Promotion failure may leave a partial
update; the result lists targets already promoted and also preserves
the staging directory."
  (let ((staging (org-roam-blog--make-staging-directory))
        staged promoted diagnostics)
    (condition-case error-data
        (progn
          (setq staged (org-roam-blog--stage-content entries staging))
          (dolist (pair staged)
            (let ((target (plist-get (car pair) :store-output)))
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
         'error 'content
         (error-message-string error-data))
        diagnostics)
       (list :status 'failure
             :staging staging
             :promoted (nreverse promoted)
             :diagnostics (nreverse diagnostics))))))

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
                 diagnostics))))
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
        (dolist (key '(:include-tags :exclude-tags))
          (when (and (plist-member org-roam-blog-sitemap key)
                     (not (org-roam-blog--string-list-p
                           (plist-get org-roam-blog-sitemap key))))
            (push (org-roam-blog--diagnostic
                   'error subject
                   (format "The %S field must be nil or a string list." key))
                  diagnostics)))
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

(provide 'org-roam-blog)

;;; org-roam-blog.el ends here
