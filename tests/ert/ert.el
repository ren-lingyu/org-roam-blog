;;; org-roam-blog-test.el --- Tests for org-roam-blog -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for Org-roam Blog.

;;; Code:

(require 'ert)
(require 'org-roam-blog)

(ert-deftest org-roam-blog-test-merge-template-overrides-nil ()
  (should
   (equal (org-roam-blog--merge-template
           '(:with-toc t :section-numbers t)
           '(:with-toc nil))
          '(:with-toc nil :section-numbers t))))

(ert-deftest org-roam-blog-test-relative-path-validation ()
  (should (org-roam-blog--relative-path-p "_org"))
  (should (org-roam-blog--relative-path-p "." t))
  (should-not (org-roam-blog--relative-path-p "."))
  (should-not (org-roam-blog--relative-path-p "../public"))
  (should-not (org-roam-blog--relative-path-p "/tmp/public")))

(ert-deftest org-roam-blog-test-site-url-validation ()
  (should (org-roam-blog--valid-site-url-p nil))
  (should
   (org-roam-blog--valid-site-url-p "https://example.org/blog/"))
  (should-not
   (org-roam-blog--valid-site-url-p "https://example.org/blog"))
  (should-not
   (org-roam-blog--valid-site-url-p "https://example.org/blog/?x=1"))
  (should-not
   (org-roam-blog--valid-site-url-p "file:///tmp/public/")))

(ert-deftest org-roam-blog-test-site-url-encodes-path-segments ()
  (let ((org-roam-blog-site-url "https://example.org/blog/"))
    (should
     (equal (org-roam-blog--site-url "文章/a b.html")
            "https://example.org/blog/%E6%96%87%E7%AB%A0/a%20b.html"))))

(ert-deftest org-roam-blog-test-variable-validation-accepts-minimum ()
  (let ((org-roam-blog-directory "/tmp/source/")
        (org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-publish-store "_org")
        (org-roam-blog-site-url nil)
        (org-roam-blog-temporary-directory nil)
        (org-roam-blog-default-template nil)
        (org-roam-blog-content nil)
        (org-roam-blog-static nil)
        (org-roam-blog-sitemap '(:enable nil))
        (org-roam-blog-theindex '(:enable nil)))
    (should-not (org-roam-blog--validate-variables))))

(ert-deftest org-roam-blog-test-variable-validation-reports-unknown-key ()
  (let ((org-roam-blog-directory "/tmp/source/")
        (org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-publish-store "_org")
        (org-roam-blog-site-url nil)
        (org-roam-blog-temporary-directory nil)
        (org-roam-blog-default-template nil)
        (org-roam-blog-content
         '((:name "post" :tags ("blog" "post") :unknown t)))
        (org-roam-blog-static nil)
        (org-roam-blog-sitemap '(:enable nil))
        (org-roam-blog-theindex '(:enable nil)))
    (should
     (cl-find-if
      (lambda (diagnostic)
        (string-match-p
         "Unknown key"
         (plist-get diagnostic :message)))
      (org-roam-blog--validate-variables)))))

(ert-deftest org-roam-blog-test-query-rule-nodes-matches-all-tags ()
  (let ((nodes
         (list
          (org-roam-node-create
           :id "post" :level 0 :tags '("blog" "post"))
          (org-roam-node-create
           :id "index" :level 0 :tags '("blog" "index"))
          (org-roam-node-create
           :id "headline" :level 1 :tags '("blog" "post")))))
    (cl-letf (((symbol-function 'org-roam-node-list)
               (lambda () nodes)))
      (should
       (equal
        (mapcar #'org-roam-node-id
                (org-roam-blog--query-rule-nodes
                 '(:tags ("blog" "post"))))
        '("post"))))))

(ert-deftest org-roam-blog-test-manifest-mirrors-source-path ()
  (let* ((source-root (make-temp-file "org-roam-blog-source-" t))
         (nested (expand-file-name "permanent/id" source-root))
         (source (expand-file-name "post.org" nested))
         (org-roam-blog-directory source-root)
         (org-roam-blog-publish-directory "/tmp/public/")
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-default-template '(:with-toc nil))
         (org-roam-blog-content
          '((:name "post" :tags ("blog" "post")
             :directory "posts" :sitemap t
             :template (:with-toc t)))))
    (unwind-protect
        (progn
          (make-directory nested t)
          (write-region "" nil source nil 'silent)
          (cl-letf (((symbol-function 'org-roam-node-list)
                     (lambda ()
                       (list
                        (org-roam-node-create
                         :id "id" :title "Post" :file source :level 0
                         :tags '("blog" "post"))))))
            (let* ((manifest (org-roam-blog--build-manifest))
                   (entry (car (plist-get manifest :entries))))
              (should-not (plist-get manifest :diagnostics))
              (should
               (equal (plist-get entry :source-relative)
                      "permanent/id/post.org"))
              (should
               (equal (plist-get entry :store-relative)
                      "_org/permanent/id/post.html"))
              (should
               (equal (plist-get entry :redirect-relative)
                      "posts/post.html"))
              (should (plist-get entry :sitemap))
              (should
               (equal (plist-get entry :template)
                      '(:with-toc t))))))
      (delete-directory source-root t))))

(ert-deftest org-roam-blog-test-manifest-reports-overlapping-rules ()
  (let* ((source-root (make-temp-file "org-roam-blog-source-" t))
         (source (expand-file-name "post.org" source-root))
         (node nil)
         (org-roam-blog-directory source-root)
         (org-roam-blog-publish-directory "/tmp/public/")
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-default-template nil)
         (org-roam-blog-content
          '((:name "post" :tags ("blog" "post"))
            (:name "index" :tags ("blog" "index")))))
    (unwind-protect
        (progn
          (write-region "" nil source nil 'silent)
          (setq node
                (org-roam-node-create
                 :id "id" :title "Post" :file source :level 0
                 :tags '("blog" "post" "index")))
          (cl-letf (((symbol-function 'org-roam-node-list)
                     (lambda () (list node))))
            (let ((diagnostics
                   (plist-get (org-roam-blog--build-manifest)
                              :diagnostics)))
              (should
               (cl-find-if
                (lambda (diagnostic)
                  (string-match-p
                   "matches content rules"
                   (plist-get diagnostic :message)))
                diagnostics)))))
      (delete-directory source-root t))))

(ert-deftest org-roam-blog-test-output-plan-detects-redirect-conflict ()
  (let ((org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-sitemap '(:enable t :path "index.html"))
        (org-roam-blog-theindex '(:enable nil))
        (entries
         '((:source "/tmp/source/index.org"
            :store-output "/tmp/public/_org/id/index.html"
            :redirect-relative "index.html"
            :content-name "index"))))
    (let* ((plan (org-roam-blog--generated-output-plan entries))
           (diagnostics (org-roam-blog--output-conflicts plan)))
      (should (= (length diagnostics) 1))
      (should
       (string-match-p
        "Output conflict"
        (plist-get (car diagnostics) :message))))))

(ert-deftest org-roam-blog-test-staging-directory-uses-configured-parent ()
  (let* ((parent (make-temp-file "org-roam-blog-staging-parent-" t))
         (org-roam-blog-temporary-directory parent)
         first second)
    (unwind-protect
        (progn
          (setq first (org-roam-blog--make-staging-directory)
                second (org-roam-blog--make-staging-directory))
          (should (org-roam-blog--path-inside-p first parent))
          (should (org-roam-blog--path-inside-p second parent))
          (should-not (equal first second))
          (should
           (string-match-p
            "org-roam-blog-[0-9]\\{8\\}T[0-9]\\{6\\}-"
            (file-name-nondirectory first))))
      (delete-directory parent t))))

(ert-deftest org-roam-blog-test-content-export-uses-disk-state-and-hooks ()
  (let* ((root (make-temp-file "org-roam-blog-export-" t))
         (source (expand-file-name "post.org" root))
         (staging (expand-file-name "staging" root))
         (visiting nil)
         (hook-ran nil)
         (org-export-before-processing-hook
          (list (lambda (_backend) (setq hook-ran t))))
         (entry
          (list :source source
                :store-relative "_org/post.html"
                :template '(:with-author nil))))
    (unwind-protect
        (progn
          (write-region
           "#+TITLE: Disk title\n\nDisk body\n"
           nil source nil 'silent)
          (make-directory staging)
          (setq visiting (find-file-noselect source))
          (with-current-buffer visiting
            (goto-char (point-max))
            (insert "\nUnsaved marker\n"))
          (let ((output
                 (org-roam-blog--export-content-entry entry staging)))
            (should hook-ran)
            (with-temp-buffer
              (insert-file-contents output)
              (should (search-forward "Disk body" nil t))
              (should-not (search-forward "Unsaved marker" nil t)))))
      (when (buffer-live-p visiting)
        (with-current-buffer visiting
          (set-buffer-modified-p nil))
        (kill-buffer visiting))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-content-batch-promotes-and-cleans-staging ()
  (let* ((root (make-temp-file "org-roam-blog-batch-" t))
         (source (expand-file-name "post.org" root))
         (publish (expand-file-name "public" root))
         (temporary (expand-file-name "temporary" root))
         (target (expand-file-name "_org/post.html" publish))
         (org-roam-blog-temporary-directory temporary)
         (entry
          (list :source source
                :store-relative "_org/post.html"
                :store-output target
                :template '(:with-author nil))))
    (unwind-protect
        (progn
          (make-directory temporary)
          (write-region "#+TITLE: Post\n\nBody\n"
                        nil source nil 'silent)
          (let ((result
                 (org-roam-blog--publish-content-batch
                  (list entry))))
            (should (eq (plist-get result :status) 'success))
            (should-not (plist-get result :staging))
            (should (equal (plist-get result :promoted)
                           (list target)))
            (should (file-regular-p target))
            (should-not
             (directory-files temporary nil
                              "\\`org-roam-blog-" t))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-content-batch-retains-failed-staging ()
  (let* ((root (make-temp-file "org-roam-blog-batch-" t))
         (temporary (expand-file-name "temporary" root))
         (target (expand-file-name "public/_org/post.html" root))
         (org-roam-blog-temporary-directory temporary)
         (entry
          (list :source (expand-file-name "missing.org" root)
                :store-relative "_org/post.html"
                :store-output target
                :template nil)))
    (unwind-protect
        (progn
          (make-directory temporary)
          (let* ((result
                  (org-roam-blog--publish-content-batch
                   (list entry)))
                 (staging (plist-get result :staging)))
            (should (eq (plist-get result :status) 'failure))
            (should (file-directory-p staging))
            (should-not (file-exists-p target))
            (should (plist-get result :diagnostics))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-promote-file-rejects-symlink-target ()
  (let* ((root (make-temp-file "org-roam-blog-promote-" t))
         (staged (expand-file-name "staged.html" root))
         (actual (expand-file-name "actual.html" root))
         (target (expand-file-name "target.html" root)))
    (unwind-protect
        (progn
          (write-region "new" nil staged nil 'silent)
          (write-region "old" nil actual nil 'silent)
          (make-symbolic-link actual target)
          (should-error
           (org-roam-blog--promote-file staged target))
          (with-temp-buffer
            (insert-file-contents actual)
            (should (equal (buffer-string) "old"))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-relative-url-preserves-layout ()
  (should
   (equal
    (org-roam-blog--relative-url
     "pages/index.html" "_org/permanent/a b.html")
    "../_org/permanent/a%20b.html")))

(ert-deftest org-roam-blog-test-redirect-html-uses-relative-store-url ()
  (let ((html
         (org-roam-blog--redirect-html
          '(:title "Index"
            :redirect-relative "pages/index.html"
            :store-relative "_org/permanent/id/index.html"))))
    (should
     (string-match-p
      "location\\.replace(\"\\.\\./_org/permanent/id/index\\.html\")"
      html))
    (should
     (string-match-p
      "rel=\"canonical\" href=\"\\.\\./_org/permanent/id/index\\.html\""
      html))))

(ert-deftest org-roam-blog-test-sitemap-projects-tags ()
  (should
   (equal
    (org-roam-blog--project-sitemap-tags
     '("blog" "post" "emacs" "linux")
     '(:include-tags ("post" "emacs" "linux")
       :exclude-tags ("post" "linux")))
    '("emacs"))))

(ert-deftest org-roam-blog-test-default-sitemap-uses-relative-urls ()
  (let* ((config
          '(:path "pages/sitemap.html" :title "Posts"
            :include-tags nil :exclude-tags ("blog")))
         (entries
          '((:title "Post" :source-relative "post.org"
             :store-relative "_org/id/post.html"
             :tags ("blog" "emacs") :sitemap t)))
         (prepared
          (org-roam-blog--prepare-sitemap-entries entries config))
         (content
          (org-roam-blog--default-sitemap-content prepared config)))
    (should
     (string-match-p
      "\\[\\[file:\\.\\./_org/id/post\\.html\\]\\[Post\\]\\]"
      content))
    (should (string-match-p "(emacs)" content))
    (should-not (string-match-p "blog" content))))

(ert-deftest org-roam-blog-test-sitemap-content-function-receives-prepared ()
  (let* ((received nil)
         (org-roam-blog-sitemap
          (list :enable t :path "sitemap.html"
                :include-tags '("emacs")
                :content-function
                (lambda (entries _config)
                  (setq received entries)
                  "#+TITLE: Custom\n"))))
    (should
     (equal
      (org-roam-blog--sitemap-content
       '((:title "Post" :store-relative "_org/post.html"
          :tags ("blog" "emacs") :sitemap t)))
      "#+TITLE: Custom\n"))
    (should
     (equal (plist-get (car received) :tags)
            '("emacs")))))

(ert-deftest org-roam-blog-test-generated-batch-promotes-entry-pages-last ()
  (let* ((root (make-temp-file "org-roam-blog-generated-" t))
         (source (expand-file-name "index.org" root))
         (publish (expand-file-name "public" root))
         (temporary (expand-file-name "temporary" root))
         (store-output
          (expand-file-name "_org/id/index.html" publish))
         (org-roam-blog-publish-directory publish)
         (org-roam-blog-temporary-directory temporary)
         (org-roam-blog-default-template '(:with-author nil))
         (org-roam-blog-sitemap
          '(:enable t :path "sitemap.html" :title "Posts"
            :sort anti-chronologically
            :exclude-tags ("blog")))
         (org-roam-blog-theindex '(:enable nil))
         (entry
          (list :title "Index"
                :source source
                :source-relative "id/index.org"
                :store-relative "_org/id/index.html"
                :store-output store-output
                :redirect-relative "index.html"
                :tags '("blog" "index")
                :sitemap t
                :template '(:with-author nil))))
    (unwind-protect
        (progn
          (make-directory temporary)
          (write-region "#+TITLE: Index\n\nBody\n"
                        nil source nil 'silent)
          (let ((result
                 (org-roam-blog--publish-generated-batch
                  (list entry))))
            (ert-info ((format "Batch result: %S" result))
              (should (eq (plist-get result :status) 'success)))
            (should (file-regular-p store-output))
            (should
             (file-regular-p
              (expand-file-name "sitemap.html" publish)))
            (should
             (file-regular-p
              (expand-file-name "index.html" publish)))
            (should
             (equal
              (plist-get result :promoted)
              (list store-output
                    (expand-file-name "sitemap.html" publish)
                    (expand-file-name "index.html" publish))))))
      (delete-directory root t))))

;;; org-roam-blog-test.el ends here
