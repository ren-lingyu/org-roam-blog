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

;;; org-roam-blog-test.el ends here
