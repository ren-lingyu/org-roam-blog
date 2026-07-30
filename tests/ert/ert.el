;;; org-roam-blog-test.el --- Tests for org-roam-blog -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for Org-roam Blog.

;;; Code:

(require 'ert)
(require 'org-roam-blog)

(ert-deftest org-roam-blog-test-merge-template-overrides-nil ()
  (should (equal (org-roam-blog--merge-template (list :with-toc t
                                                      :section-numbers t)
                                                (list :with-toc nil))
                 '(:with-toc nil :section-numbers t))))

(ert-deftest org-roam-blog-test-merge-template-replaces-list-value ()
  (should (equal (org-roam-blog--merge-template (list :html-head-extra '("base"))
                                                (list :html-head-extra '("override")))
                 '(:html-head-extra ("override")))))

(ert-deftest org-roam-blog-test-merge-bindings-overrides-by-symbol ()
  (let ((base (list (cons 'org-html-head "base")
                    (cons 'org-html-postamble t)))
        (override (list (cons 'org-html-head nil)
                        (cons 'org-html-preamble t))))
    (should (equal (org-roam-blog--merge-bindings base
                                                  override)
                   (list (cons 'org-html-head nil)
                         (cons 'org-html-postamble t)
                         (cons 'org-html-preamble t))))
    (should (equal base
                   (list (cons 'org-html-head "base")
                         (cons 'org-html-postamble t))))))

(ert-deftest org-roam-blog-test-export-configuration-appends-body-functions ()
  (let* ((default-function (lambda (context)
                             (plist-get context
                                        :body)))
         (object-function (lambda (context)
                            (plist-get context
                                       :body)))
         (org-roam-blog-export-default
          (list :template (list :with-toc nil)
                :bindings (list (cons 'org-html-head "default"))
                :body (list default-function)))
         (configuration (org-roam-blog--export-configuration
                         (list :template (list :with-toc t)
                               :bindings (list (cons 'org-html-head nil))
                               :body (list object-function)))))
    (should (equal (plist-get configuration
                              :template)
                   (list :with-toc t)))
    (should (equal (plist-get configuration
                              :bindings)
                   (list (cons 'org-html-head nil))))
    (should (equal (plist-get configuration
                              :body)
                   (list default-function
                         object-function)))))

(ert-deftest org-roam-blog-test-export-configuration-nil-body-inherits-default ()
  (let* ((default-function (lambda (context)
                             (plist-get context
                                        :body)))
         (org-roam-blog-export-default
          (list :body (list default-function))))
    (should (equal (plist-get (org-roam-blog--export-configuration
                               (list :body nil))
                              :body)
                   (list default-function)))))

(ert-deftest org-roam-blog-test-relative-path-validation ()
  (should (org-roam-blog--relative-path-p "_org"))
  (should (org-roam-blog--relative-path-p "."
                                          t))
  (should-not (org-roam-blog--relative-path-p "."))
  (should-not (org-roam-blog--relative-path-p "../public"))
  (should-not (org-roam-blog--relative-path-p "/tmp/public")))

(ert-deftest org-roam-blog-test-site-url-validation ()
  (should (org-roam-blog--valid-site-url-p nil))
  (should (org-roam-blog--valid-site-url-p "https://example.org/blog/"))
  (should-not (org-roam-blog--valid-site-url-p "https://example.org/blog"))
  (should-not (org-roam-blog--valid-site-url-p "https://example.org/blog/?x=1"))
  (should-not (org-roam-blog--valid-site-url-p "file:///tmp/public/")))

(ert-deftest org-roam-blog-test-site-url-encodes-path-segments ()
  (let ((org-roam-blog-site-url "https://example.org/blog/"))
    (should (equal (org-roam-blog--site-url "文章/a b.html")
                   "https://example.org/blog/%E6%96%87%E7%AB%A0/a%20b.html"))))

(ert-deftest org-roam-blog-test-variable-validation-accepts-minimum ()
  (let* ((root (make-temp-file "org-roam-blog-variables-" t))
         (source (expand-file-name "source"
                                   root))
         (publish (expand-file-name "public"
                                    root))
         (org-roam-blog-directory source)
         (org-roam-blog-publish-directory publish)
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-site-url nil)
         (org-roam-blog-temporary-directory nil)
         (org-roam-blog-export-default nil)
         (org-roam-blog-content nil)
         (org-roam-blog-static nil)
         (org-roam-blog-sitemap (list :enable nil))
         (org-roam-blog-theindex (list :enable nil)))
    (unwind-protect
        (progn (make-directory source)
               (make-directory publish)
               (should-not (org-roam-blog--validate-variables)))
      (delete-directory root
                        t))))

(ert-deftest org-roam-blog-test-variable-validation-requires-existing-roots ()
  (let* ((root (make-temp-file "org-roam-blog-missing-roots-" t))
         (org-roam-blog-directory (expand-file-name "source"
                                                    root))
         (org-roam-blog-publish-directory (expand-file-name "public"
                                                            root))
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-site-url nil)
         (org-roam-blog-temporary-directory (expand-file-name "staging"
                                                              root))
         (org-roam-blog-export-default nil)
         (org-roam-blog-content nil)
         (org-roam-blog-static nil)
         (org-roam-blog-sitemap (list :enable nil))
         (org-roam-blog-theindex (list :enable nil)))
    (unwind-protect
        (let ((diagnostics (org-roam-blog--validate-variables)))
          (dolist (subject '(org-roam-blog-directory
                             org-roam-blog-publish-directory
                             org-roam-blog-temporary-directory))
            (should (cl-find-if (lambda (diagnostic)
                                  (eq (plist-get diagnostic
                                                 :subject)
                                      subject))
                                diagnostics))))
      (delete-directory root
                        t))))

(ert-deftest org-roam-blog-test-variable-validation-rejects-store-symlink ()
  (let* ((root (make-temp-file "org-roam-blog-store-" t))
         (source (expand-file-name "source"
                                   root))
         (publish (expand-file-name "public"
                                    root))
         (outside (expand-file-name "outside"
                                    root))
         (store (expand-file-name "_org"
                                  publish))
         (org-roam-blog-directory source)
         (org-roam-blog-publish-directory publish)
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-site-url nil)
         (org-roam-blog-temporary-directory nil)
         (org-roam-blog-export-default nil)
         (org-roam-blog-content nil)
         (org-roam-blog-static nil)
         (org-roam-blog-sitemap (list :enable nil))
         (org-roam-blog-theindex (list :enable nil)))
    (unwind-protect
        (progn (make-directory source)
               (make-directory publish)
               (make-directory outside)
               (make-symbolic-link outside
                                   store)
               (should (cl-find-if
                        (lambda (diagnostic)
                          (eq (plist-get diagnostic
                                         :subject)
                              'org-roam-blog-publish-store))
                        (org-roam-blog--validate-variables))))
      (delete-directory root
                        t))))

(ert-deftest org-roam-blog-test-variable-validation-reports-unknown-key ()
  (let ((org-roam-blog-directory "/tmp/source/")
        (org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-publish-store "_org")
        (org-roam-blog-site-url nil)
        (org-roam-blog-temporary-directory nil)
        (org-roam-blog-export-default nil)
        (org-roam-blog-content (list (list :name "post"
                                           :tags '("blog" "post")
                                           :unknown t)))
        (org-roam-blog-static nil)
        (org-roam-blog-sitemap (list :enable nil))
        (org-roam-blog-theindex (list :enable nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (string-match-p "Unknown key"
                                          (plist-get diagnostic
                                                     :message)))
                        (org-roam-blog--validate-variables)))))

(ert-deftest org-roam-blog-test-variable-validation-rejects-empty-published-property ()
  (let ((org-roam-blog-directory "/tmp/source/")
        (org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-publish-store "_org")
        (org-roam-blog-site-url nil)
        (org-roam-blog-temporary-directory nil)
        (org-roam-blog-export-default nil)
        (org-roam-blog-published-property "")
        (org-roam-blog-content nil)
        (org-roam-blog-static nil)
        (org-roam-blog-sitemap (list :enable nil))
        (org-roam-blog-theindex (list :enable nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (eq (plist-get diagnostic
                                         :subject)
                              'org-roam-blog-published-property))
                        (org-roam-blog--validate-variables)))))

(ert-deftest org-roam-blog-test-variable-validation-rejects-invalid-bindings ()
  (let ((org-roam-blog-directory "/tmp/source/")
        (org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-publish-store "_org")
        (org-roam-blog-site-url nil)
        (org-roam-blog-temporary-directory nil)
        (org-roam-blog-export-default
         (list :bindings '(("org-html-head" . "invalid"))))
        (org-roam-blog-content nil)
        (org-roam-blog-static nil)
        (org-roam-blog-sitemap (list :enable nil))
        (org-roam-blog-theindex (list :enable nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (eq (plist-get diagnostic
                                         :subject)
                              'org-roam-blog-export-default))
                        (org-roam-blog--validate-variables)))))

(ert-deftest org-roam-blog-test-variable-validation-rejects-invalid-default-body ()
  (let ((org-roam-blog-directory "/tmp/source/")
        (org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-publish-store "_org")
        (org-roam-blog-site-url nil)
        (org-roam-blog-temporary-directory nil)
        (org-roam-blog-export-default
         (list :body (list "not-a-function")))
        (org-roam-blog-content nil)
        (org-roam-blog-static nil)
        (org-roam-blog-sitemap (list :enable nil))
        (org-roam-blog-theindex (list :enable nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (and (eq (plist-get diagnostic
                                              :subject)
                                   'org-roam-blog-export-default)
                               (string-match-p ":body field must be a list of functions"
                                               (plist-get diagnostic
                                                          :message))))
                        (org-roam-blog--validate-variables)))))

(ert-deftest org-roam-blog-test-object-validation-rejects-invalid-bindings ()
  (let* ((org-roam-blog-content (list (list :name "post"
                                            :tags '("blog" "post")
                                            :bindings '(("org-html-head" . "invalid")))))
         (diagnostics (org-roam-blog--validate-content nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (string-match-p ":bindings field must be an alist keyed by symbols"
                                          (plist-get diagnostic
                                                     :message)))
                        diagnostics)))
  (let* ((org-roam-blog-sitemap (list :enable nil
                                      :bindings '(("org-html-head" . "invalid"))))
         (diagnostics (org-roam-blog--validate-sitemap nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (string-match-p ":bindings field must be an alist keyed by symbols"
                                          (plist-get diagnostic
                                                     :message)))
                        diagnostics))))

(ert-deftest org-roam-blog-test-object-validation-rejects-invalid-body ()
  (let* ((org-roam-blog-content (list (list :name "post"
                                            :tags '("blog" "post")
                                            :body (list "not-a-function"))))
         (diagnostics (org-roam-blog--validate-content nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (string-match-p ":body field must be a list of functions"
                                          (plist-get diagnostic
                                                     :message)))
                        diagnostics)))
  (let* ((org-roam-blog-sitemap (list :enable nil
                                      :body (list "not-a-function")))
         (diagnostics (org-roam-blog--validate-sitemap nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (string-match-p ":body field must be a list of functions"
                                          (plist-get diagnostic
                                                     :message)))
                        diagnostics)))
  (let* ((org-roam-blog-theindex (list :enable nil
                                       :body (list "not-a-function")))
         (diagnostics (org-roam-blog--validate-theindex nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (string-match-p ":body field must be a list of functions"
                                          (plist-get diagnostic
                                                     :message)))
                        diagnostics))))

(ert-deftest org-roam-blog-test-capabilities-check-org-roam-database-apis ()
  (let ((capabilities (org-roam-blog--check-capabilities)))
    (should (cl-find-if (lambda (capability)
                          (eq (plist-get capability
                                         :name)
                              'org-roam-node-list))
                        capabilities))
    (should (cl-find-if (lambda (capability)
                          (eq (plist-get capability
                                         :name)
                              'org-roam-db-query))
                        capabilities))))

(ert-deftest org-roam-blog-test-capabilities-report-missing-node-list-api ()
  (cl-letf (((symbol-function 'org-roam-node-list) nil))
    (let* ((capabilities (org-roam-blog--check-capabilities))
           (capability (cl-find-if (lambda (candidate)
                                     (eq (plist-get candidate
                                                    :name)
                                         'org-roam-node-list))
                                   capabilities)))
      (should capability)
      (should (plist-get capability
                         :required))
      (should-not (plist-get capability
                             :available))
      (should (string-match-p "org-roam-node-list.*unavailable"
                              (plist-get capability
                                         :detail))))))

(ert-deftest org-roam-blog-test-capabilities-report-missing-db-query-api ()
  (cl-letf (((symbol-function 'org-roam-db-query) nil))
    (let* ((capabilities (org-roam-blog--check-capabilities))
           (capability (cl-find-if (lambda (candidate)
                                     (eq (plist-get candidate
                                                    :name)
                                         'org-roam-db-query))
                                   capabilities)))
      (should capability)
      (should (plist-get capability
                         :required))
      (should-not (plist-get capability
                             :available))
      (should (string-match-p "org-roam-db-query.*unavailable"
                              (plist-get capability
                                         :detail))))))

(ert-deftest org-roam-blog-test-theindex-validates-title ()
  (let* ((org-roam-blog-theindex (list :enable t
                                       :path "theindex.html"
                                       :title 1))
         (diagnostics (org-roam-blog--validate-theindex nil)))
    (should (cl-find-if
             (lambda (diagnostic)
               (string-match-p ":title field must be a string"
                               (plist-get diagnostic
                                          :message)))
             diagnostics))))

(ert-deftest org-roam-blog-test-theindex-capabilities-are-conditional ()
  (cl-letf (((symbol-function 'org-publish-collect-index) nil)
            ((symbol-function 'org-publish-cache-get) nil))
    (let* ((org-roam-blog-theindex (list :enable nil))
           (capabilities (org-roam-blog--check-capabilities))
           (capability (cl-find-if
                        (lambda (candidate)
                          (eq (plist-get candidate
                                         :name)
                              'org-publish-index))
                        capabilities)))
      (should capability)
      (should-not (plist-get capability
                             :required))
      (should-not (plist-get capability
                             :available)))
    (let* ((org-roam-blog-theindex (list :enable t
                                         :path "theindex.html"))
           (capabilities (org-roam-blog--check-capabilities))
           (capability (cl-find-if
                        (lambda (candidate)
                          (eq (plist-get candidate
                                         :name)
                              'org-publish-index))
                        capabilities)))
      (should capability)
      (should (plist-get capability
                         :required))
      (should-not (plist-get capability
                             :available)))))

(ert-deftest org-roam-blog-test-theindex-capabilities-require-native-generator ()
  (cl-letf (((symbol-function 'org-publish-index-generate-theindex) nil))
    (let* ((org-roam-blog-theindex (list :enable t
                                         :path "theindex.html"))
           (capabilities (org-roam-blog--check-capabilities))
           (capability (cl-find-if
                        (lambda (candidate)
                          (eq (plist-get candidate
                                         :name)
                              'org-publish-index))
                        capabilities)))
      (should capability)
      (should (plist-get capability
                         :required))
      (should-not (plist-get capability
                             :available))
      (should (string-match-p "org-publish-index-generate-theindex"
                              (plist-get capability
                                         :detail))))))

(ert-deftest org-roam-blog-test-theindex-link-filter-maps-exact-html-href ()
  (let ((org-roam-blog--theindex-href-map
         (list (cons "../../../source/a b中.html"
                     "../_store/id/a%20b%E4%B8%AD.html"))))
    (should
     (equal
      (org-roam-blog--theindex-link-filter
       "<a class=\"link\" href=\"../../../source/a b中.html#heading\">Entry</a>"
       'html
       nil)
      "<a class=\"link\" href=\"../_store/id/a%20b%E4%B8%AD.html#heading\">Entry</a>"))
    (should
     (equal
      (org-roam-blog--theindex-link-filter
       "<a href=\"../../../source/a b中-extra.html#heading\">Other</a>"
       'html
       nil)
      "<a href=\"../../../source/a b中-extra.html#heading\">Other</a>"))
    (should
     (equal
      (org-roam-blog--theindex-link-filter
       "<a href=\"../../../source/a b中.html#heading\">Entry</a>"
       'org
       nil)
      "<a href=\"../../../source/a b中.html#heading\">Entry</a>"))))

(ert-deftest org-roam-blog-test-theindex-project-includes-only-selected-sources ()
  (let* ((entries (list (list :source "/source/a.org"
                              :theindex t)
                        (list :source "/source/b.org"
                              :theindex nil)))
         (selected (org-roam-blog--theindex-entries entries))
         (project (org-roam-blog--theindex-project selected
                                                   "/work/"
                                                   "/output/")))
    (should (equal (plist-get (cdr project)
                              :include)
                   (list "/source/a.org")))
    (should (equal (plist-get (cdr project)
                              :exclude)
                   ".*"))))

(ert-deftest org-roam-blog-test-published-property-is-configurable ()
  (let ((org-roam-blog-published-property "PDATE")
        (node (org-roam-node-create
               :properties '(("PDATE" . "2026-07-30")))))
    (should (equal (org-roam-blog--node-published node)
                   "2026-07-30"))))

(ert-deftest org-roam-blog-test-sitemap-validates-visible-tags ()
  (dolist (config (list (list :enable nil
                              :visible-tags nil)
                        (list :enable nil
                              :visible-tags '("emacs" "lisp"))))
    (let ((org-roam-blog-sitemap config))
      (should-not (org-roam-blog--validate-sitemap nil))))
  (let* ((org-roam-blog-sitemap (list :enable nil
                                      :visible-tags '("emacs" 1)))
         (diagnostics (org-roam-blog--validate-sitemap nil)))
    (should (cl-find-if (lambda (diagnostic)
                          (string-match-p ":visible-tags field must be nil or a string list"
                                          (plist-get diagnostic
                                                     :message)))
                        diagnostics)))
  (dolist (key '(:include-tags :exclude-tags))
    (let* ((org-roam-blog-sitemap (list :enable nil
                                        key '("emacs")))
           (diagnostics (org-roam-blog--validate-sitemap nil)))
      (should (cl-find-if (lambda (diagnostic)
                            (string-match-p (format "Unknown key: %S"
                                                    key)
                                            (plist-get diagnostic
                                                       :message)))
                          diagnostics)))))

(ert-deftest org-roam-blog-test-query-rule-nodes-matches-all-tags ()
  (let ((nodes (list (org-roam-node-create
                      :id "post" :level 0 :tags '("blog" "post"))
                     (org-roam-node-create
                      :id "index" :level 0 :tags '("blog" "index"))
                     (org-roam-node-create
                      :id "headline" :level 1 :tags '("blog" "post")))))
    (cl-letf (((symbol-function 'org-roam-node-list)
               (lambda () nodes)))
      (should (equal (mapcar #'org-roam-node-id
                             (org-roam-blog--query-rule-nodes (list :tags '("blog" "post"))))
                     '("post"))))))

(ert-deftest org-roam-blog-test-manifest-mirrors-source-path ()
  (let* ((source-root (make-temp-file "org-roam-blog-source-" t))
         (nested (expand-file-name "permanent/id" source-root))
         (source (expand-file-name "post.org" nested))
         (org-roam-blog-directory source-root)
         (org-roam-blog-publish-directory "/tmp/public/")
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-export-default
          (list :template (list :with-toc nil)
                :bindings (list (cons 'org-html-head "default")
                                (cons 'org-html-postamble t))))
         (org-roam-blog-content (list (list :name "post"
                                            :tags '("blog" "post")
                                            :directory "posts"
                                            :sitemap t
                                            :template (list :with-toc t)
                                            :bindings (list (cons 'org-html-head nil))))))
    (unwind-protect
        (progn (make-directory nested
                               t)
               (write-region ""
                             nil
                             source
                             nil
                             'silent)
               (cl-letf (((symbol-function 'org-roam-node-list)
                          (lambda ()
                            (list (org-roam-node-create
                                   :id "id" :title "Post" :file source :level 0
                                   :tags '("blog" "post")))))
                         ((symbol-function 'org-roam-db-query)
                          (lambda (&rest _arguments)
                            nil)))
                 (let* ((manifest (org-roam-blog--build-manifest))
                        (entry (car (plist-get manifest
                                               :entries))))
                   (should-not (plist-get manifest
                                          :diagnostics))
                   (should (equal (plist-get entry
                                             :source-relative)
                                  "permanent/id/post.org"))
                   (should (equal (plist-get entry
                                             :store-relative)
                                  "_org/permanent/id/post.html"))
                   (should (equal (plist-get entry
                                             :redirect-relative)
                                  "posts/post.html"))
                   (should (plist-get entry
                                      :sitemap))
                   (should (equal (plist-get entry
                                             :template)
                                  '(:with-toc t)))
                   (should (equal (plist-get entry
                                             :bindings)
                                  (list (cons 'org-html-head nil)
                                        (cons 'org-html-postamble t)))))))
      (delete-directory source-root t))))

(ert-deftest org-roam-blog-test-manifest-reads-times-from-database ()
  (let* ((source-root (make-temp-file "org-roam-blog-date-" t))
         (source (expand-file-name "post.org"
                                   source-root))
         (modified '(27000 1000 0 0))
         (org-roam-blog-directory source-root)
         (org-roam-blog-publish-directory "/tmp/public/")
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-export-default nil)
         (org-roam-blog-published-property "PUBLISHED")
         (org-roam-blog-content (list (list :name "post"
                                            :tags '("blog" "post")
                                            :sitemap t))))
    (unwind-protect
        (progn (write-region "#+TITLE: Post\n#+DATE: 2000-01-01\n"
                             nil
                             source
                             nil
                             'silent)
               (cl-letf (((symbol-function 'org-roam-node-list)
                          (lambda ()
                            (list (org-roam-node-create
                                   :id "id"
                                   :title "Post"
                                   :file source
                                   :level 0
                                   :properties '(("PUBLISHED" . "2026-07-30"))
                                   :tags '("blog" "post")))))
                         ((symbol-function 'org-roam-db-query)
                          (lambda (&rest _arguments)
                            (list (vector modified)))))
                 (let* ((manifest (org-roam-blog--build-manifest))
                        (entry (car (plist-get manifest
                                               :entries))))
                   (should (equal (plist-get entry
                                             :published-time)
                                  "2026-07-30"))
                   (should (equal (plist-get entry
                                             :modified-time)
                                  modified)))))
      (delete-directory source-root
                        t))))

(ert-deftest org-roam-blog-test-manifest-reports-overlapping-rules ()
  (let* ((source-root (make-temp-file "org-roam-blog-source-" t))
         (source (expand-file-name "post.org" source-root))
         (node nil)
         (org-roam-blog-directory source-root)
         (org-roam-blog-publish-directory "/tmp/public/")
         (org-roam-blog-publish-store "_org")
         (org-roam-blog-export-default nil)
         (org-roam-blog-content (list (list :name "post"
                                            :tags '("blog" "post"))
                                      (list :name "index"
                                            :tags '("blog" "index")))))
    (unwind-protect
        (progn (write-region ""
                             nil
                             source
                             nil
                             'silent)
               (setq node
                     (org-roam-node-create
                      :id "id" :title "Post" :file source :level 0
                      :tags '("blog" "post" "index")))
               (cl-letf (((symbol-function 'org-roam-node-list)
                          (lambda () (list node)))
                         ((symbol-function 'org-roam-db-query)
                          (lambda (&rest _arguments)
                            nil)))
                 (let ((diagnostics (plist-get (org-roam-blog--build-manifest)
                                               :diagnostics)))
                   (should (cl-find-if (lambda (diagnostic)
                                         (string-match-p "matches content rules"
                                                         (plist-get diagnostic
                                                                    :message)))
                                       diagnostics)))))
      (delete-directory source-root t))))

(ert-deftest org-roam-blog-test-output-plan-detects-redirect-conflict ()
  (let ((org-roam-blog-publish-directory "/tmp/public/")
        (org-roam-blog-sitemap (list :enable t
                                     :path "index.html"))
        (org-roam-blog-theindex (list :enable nil))
        (entries (list (list :source "/tmp/source/index.org"
                             :store-output "/tmp/public/_org/id/index.html"
                             :redirect-relative "index.html"
                             :content-name "index"))))
    (let* ((plan (org-roam-blog--generated-output-plan entries))
           (diagnostics (org-roam-blog--output-conflicts plan)))
      (should (= (length diagnostics) 1))
      (should (string-match-p "Output conflict"
                              (plist-get (car diagnostics)
                                         :message))))))

(ert-deftest org-roam-blog-test-staging-directory-uses-configured-parent ()
  (let* ((parent (make-temp-file "org-roam-blog-staging-parent-" t))
         (org-roam-blog-temporary-directory parent)
         first second)
    (unwind-protect
        (progn (setq first (org-roam-blog--make-staging-directory)
                     second (org-roam-blog--make-staging-directory))
               (should (org-roam-blog--path-inside-p first
                                                     parent))
               (should (org-roam-blog--path-inside-p second
                                                     parent))
               (should-not (equal first second))
               (should (string-match-p "org-roam-blog-[0-9]\\{8\\}T[0-9]\\{6\\}-"
                                       (file-name-nondirectory first))))
      (delete-directory parent t))))

(ert-deftest org-roam-blog-test-path-inside-rejects-symlink-escape ()
  (let* ((root (make-temp-file "org-roam-blog-path-" t))
         (inside (expand-file-name "inside"
                                   root))
         (outside (expand-file-name "outside"
                                    root))
         (link (expand-file-name "link"
                                 inside))
         (source (expand-file-name "post.org"
                                   outside)))
    (unwind-protect
        (progn (make-directory inside)
               (make-directory outside)
               (write-region ""
                             nil
                             source
                             nil
                             'silent)
               (make-symbolic-link outside
                                   link)
               (should-not (org-roam-blog--path-inside-p (expand-file-name "post.org"
                                                                           link)
                                                         inside)))
      (delete-directory root
                        t))))

(ert-deftest org-roam-blog-test-content-export-uses-disk-state-and-hooks ()
  (let* ((root (make-temp-file "org-roam-blog-export-" t))
         (source (expand-file-name "post.org" root))
         (staging (expand-file-name "staging" root))
         (visiting nil)
         (hook-ran nil)
         (bound-head nil)
         (org-html-head "outside")
         (org-export-before-processing-hook (list (lambda (_backend)
                                                    (setq hook-ran t)
                                                    (setq bound-head org-html-head))))
         (entry (list :source source
                      :store-relative "_org/post.html"
                      :template (list :with-author nil)
                      :bindings (list (cons 'org-html-head "inside")))))
    (unwind-protect
        (progn (write-region "#+TITLE: Disk title\n\nDisk body\n"
                             nil
                             source
                             nil
                             'silent)
               (make-directory staging)
               (setq visiting (find-file-noselect source))
               (with-current-buffer visiting
                 (goto-char (point-max))
                 (insert "\nUnsaved marker\n"))
               (let ((output (org-roam-blog--export-content-entry entry
                                                                  staging)))
                 (should hook-ran)
                 (should (equal bound-head
                                "inside"))
                 (should (equal org-html-head
                                "outside"))
                 (with-temp-buffer
                   (insert-file-contents output)
                   (should (search-forward "Disk body" nil t))
                   (should-not (search-forward "Unsaved marker" nil t)))))
      (when (buffer-live-p visiting)
        (with-current-buffer visiting
          (set-buffer-modified-p nil))
        (kill-buffer visiting))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-content-body-functions-follow-native-filters ()
  (let* ((root (make-temp-file "org-roam-blog-body-" t))
         (source (expand-file-name "post.org"
                                   root))
         (staging (expand-file-name "staging"
                                    root))
         (observed nil)
         (org-export-filter-body-functions
          (list (lambda (body _backend _export-info)
                  (concat body
                          "\nNATIVE"))))
         (entry (list :title "Post"
                      :source source
                      :source-relative "post.org"
                      :store-relative "_org/post.html"
                      :content-name "post"
                      :published-time "2026-07-30"
                      :template (list :with-author nil)
                      :bindings nil
                      :config (list :name "post")
                      :body
                      (list (lambda (context)
                              (push (list (plist-get context
                                                     :kind)
                                          (plist-get context
                                                     :title)
                                          (and (string-match-p "NATIVE"
                                                               (plist-get context
                                                                          :body))
                                               t))
                                    observed)
                              (concat (plist-get context
                                                 :body)
                                      "\nFIRST"))
                            (lambda (context)
                              (push (and (string-match-p "FIRST"
                                                         (plist-get context
                                                                    :body))
                                         t)
                                    observed)
                              (concat (plist-get context
                                                 :body)
                                      "\nSECOND"))))))
    (unwind-protect
        (progn (write-region "#+TITLE: Post\n\nBody\n"
                             nil
                             source
                             nil
                             'silent)
               (make-directory staging)
               (let ((output (org-roam-blog--export-content-entry entry
                                                                  staging)))
                 (should (equal (nreverse observed)
                                (list (list 'content
                                            "Post"
                                            t)
                                      t)))
                 (with-temp-buffer
                   (insert-file-contents output)
                   (should (search-forward "NATIVE" nil t))
                   (should (search-forward "FIRST" nil t))
                   (should (search-forward "SECOND" nil t)))))
      (delete-directory root
                        t))))

(ert-deftest org-roam-blog-test-body-function-must-return-string ()
  (let ((org-roam-blog--body-context (list :kind 'content))
        (org-roam-blog--body-functions (list (lambda (_context)
                                               nil))))
    (should-error (org-roam-blog--body-filter "Body"
                                              'html
                                              nil)
                  :type 'error)))

(ert-deftest org-roam-blog-test-export-bindings-restore-after-error ()
  (let ((org-html-head "outside"))
    (should-error
     (org-roam-blog--call-with-export-bindings
      (list (cons 'org-html-head "inside"))
      (lambda ()
        (should (equal org-html-head
                       "inside"))
        (error "Export failed"))))
    (should (equal org-html-head
                   "outside"))))

(ert-deftest org-roam-blog-test-content-batch-promotes-and-cleans-staging ()
  (let* ((root (make-temp-file "org-roam-blog-batch-" t))
         (source (expand-file-name "post.org" root))
         (publish (expand-file-name "public" root))
         (temporary (expand-file-name "temporary" root))
         (target (expand-file-name "_org/post.html" publish))
         (org-roam-blog-temporary-directory temporary)
         (entry (list :source source
                      :store-relative "_org/post.html"
                      :store-output target
                      :template (list :with-author nil))))
    (unwind-protect
        (progn (make-directory temporary)
               (write-region "#+TITLE: Post\n\nBody\n"
                             nil
                             source
                             nil
                             'silent)
               (let ((result (org-roam-blog--publish-content-batch (list entry))))
                 (should (eq (plist-get result
                                        :status)
                             'success))
                 (should-not (plist-get result
                                        :staging))
                 (should (equal (plist-get result
                                           :promoted)
                                (list target)))
                 (should (file-regular-p target))
                 (should-not (directory-files temporary
                                              nil
                                              "\\`org-roam-blog-"
                                              t))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-content-batch-retains-failed-staging ()
  (let* ((root (make-temp-file "org-roam-blog-batch-" t))
         (temporary (expand-file-name "temporary" root))
         (target (expand-file-name "public/_org/post.html" root))
         (org-roam-blog-temporary-directory temporary)
         (entry (list :source (expand-file-name "missing.org" root)
                      :store-relative "_org/post.html"
                      :store-output target
                      :template nil)))
    (unwind-protect
        (progn (make-directory temporary)
               (let* ((result (org-roam-blog--publish-content-batch (list entry)))
                      (staging (plist-get result
                                          :staging)))
                 (should (eq (plist-get result
                                        :status)
                             'failure))
                 (should (file-directory-p staging))
                 (should-not (file-exists-p target))
                 (should (plist-get result
                                    :diagnostics))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-promote-file-rejects-symlink-target ()
  (let* ((root (make-temp-file "org-roam-blog-promote-" t))
         (staged (expand-file-name "staged.html" root))
         (actual (expand-file-name "actual.html" root))
         (target (expand-file-name "target.html" root)))
    (unwind-protect
        (progn (write-region "new"
                             nil
                             staged
                             nil
                             'silent)
               (write-region "old"
                             nil
                             actual
                             nil
                             'silent)
               (make-symbolic-link actual target)
               (should-error (org-roam-blog--promote-file staged
                                                          target))
               (with-temp-buffer
                 (insert-file-contents actual)
                 (should (equal (buffer-string) "old"))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-relative-url-preserves-layout ()
  (should (equal (org-roam-blog--relative-url "pages/index.html"
                                              "_org/permanent/a b.html")
                 "../_org/permanent/a%20b.html")))

(ert-deftest org-roam-blog-test-redirect-html-uses-relative-store-url ()
  (let ((html (org-roam-blog--redirect-html (list :title "Index"
                                                  :redirect-relative "pages/index.html"
                                                  :store-relative "_org/permanent/id/index.html"))))
    (should (string-match-p "<meta charset=\"utf-8\">"
                            html))
    (should (string-match-p "http-equiv=\"refresh\""
                            html))
    (should (string-match-p "location\\.replace(\"\\.\\./_org/permanent/id/index\\.html\")"
                            html))
    (should (string-match-p "rel=\"canonical\" href=\"\\.\\./_org/permanent/id/index\\.html\""
                            html))
    (should (string-match-p "<a href=\"\\.\\./_org/permanent/id/index\\.html\">Index</a>"
                            html))))

(ert-deftest org-roam-blog-test-sitemap-projects-tags ()
  (should (equal (org-roam-blog--sitemap-project-tags '("blog" "post" "emacs" "linux")
                                                      (list :visible-tags '("post" "emacs")))
                 '("post" "emacs")))
  (should-not (org-roam-blog--sitemap-project-tags '("blog" "post")
                                                   (list :visible-tags nil)))
  (should-not (org-roam-blog--sitemap-project-tags '("blog" "post")
                                                   nil)))

(ert-deftest org-roam-blog-test-sitemap-sorts-published-entries-first ()
  (let* ((config (list :sort 'anti-chronologically
                       :visible-tags nil))
         (undated (list :title "Undated"
                        :published-time nil
                        :tags nil
                        :sitemap t))
         (older (list :title "Older"
                      :published-time "2025-01-01"
                      :tags nil
                      :sitemap t))
         (newer (list :title "Newer"
                      :published-time "2026-01-01"
                      :tags nil
                      :sitemap t))
         (prepared (org-roam-blog--sitemap-prepare-entries (list undated
                                                                 older
                                                                 newer)
                                                           config)))
    (should (equal (mapcar (lambda (entry)
                             (plist-get entry
                                        :title))
                           prepared)
                   '("Newer" "Older" "Undated")))))

(ert-deftest org-roam-blog-test-sitemap-default-generator-uses-relative-urls ()
  (let* ((config (list :path "pages/sitemap.html"
                       :title "Posts"
                       :visible-tags '("emacs")))
         (entries (list (list :title "Post"
                              :source-relative "post.org"
                              :store-relative "_org/id/post.html"
                              :published-time "2026-07-30"
                              :modified-time "MODIFIED-MUST-NOT-BE-DISPLAYED"
                              :tags '("blog" "emacs")
                              :sitemap t)))
         (prepared (org-roam-blog--sitemap-prepare-entries entries
                                                           config))
         (content (org-roam-blog--sitemap-default-generator
                   (list :entries prepared
                         :config config))))
    (should (string-match-p "\\[\\[file:\\.\\./_org/id/post\\.html\\]\\[Post\\]\\]"
                            content))
    (should (string-match-p "2026-07-30"
                            content))
    (should-not (string-match-p "MODIFIED-MUST-NOT-BE-DISPLAYED"
                                content))
    (should (string-match-p "(emacs)" content))
    (should-not (string-match-p "blog" content))))

(ert-deftest org-roam-blog-test-sitemap-generator-receives-prepared ()
  (let* ((received nil)
         (org-roam-blog-sitemap (list :enable t
                                      :path "sitemap.html"
                                      :visible-tags '("emacs")
                                      :generator
                                      (lambda (context)
                                        (setq received context)
                                        "#+TITLE: Custom\n"))))
    (should (equal (org-roam-blog--sitemap-source (list (list :title "Post"
                                                              :store-relative "_org/post.html"
                                                              :tags '("blog" "emacs")
                                                              :sitemap t)))
                   "#+TITLE: Custom\n"))
    (should (equal (plist-get (car (plist-get received
                                              :entries))
                              :tags)
                   '("emacs")))))

(ert-deftest org-roam-blog-test-sitemap-generator-must-return-string ()
  (let ((org-roam-blog-sitemap
         (list :enable t
               :path "sitemap.html"
               :generator (lambda (_context)
                            nil))))
    (should-error (org-roam-blog--sitemap-source nil)
                  :type 'error)))

(ert-deftest org-roam-blog-test-generated-batch-promotes-entry-pages-last ()
  (let* ((root (make-temp-file "org-roam-blog-generated-" t))
         (source (expand-file-name "index.org" root))
         (publish (expand-file-name "public" root))
         (temporary (expand-file-name "temporary" root))
         (store-output (expand-file-name "_org/id/index.html"
                                         publish))
         (sitemap-context nil)
         (org-roam-blog-publish-directory publish)
         (org-roam-blog-temporary-directory temporary)
         (org-roam-blog-export-default
          (list :template (list :with-author nil)
                :bindings (list (cons 'org-html-head "default-head"))))
         (org-html-head "outside-head")
         (org-roam-blog-sitemap (list :enable t
                                      :path "sitemap.html"
                                      :title "Posts"
                                      :sort 'anti-chronologically
                                      :visible-tags nil
                                      :bindings (list (cons 'org-html-head
                                                            "<meta name=\"sitemap-binding\">"))
                                      :body
                                      (list (lambda (context)
                                              (setq sitemap-context context)
                                              (concat (plist-get context
                                                                 :body)
                                                      "\nSITEMAP-BODY")))))
         (org-roam-blog-theindex (list :enable nil))
         (entry (list :title "Index"
                      :source source
                      :source-relative "id/index.org"
                      :store-relative "_org/id/index.html"
                      :store-output store-output
                      :redirect-relative "index.html"
                      :tags '("blog" "index")
                      :sitemap t
                      :template (list :with-author nil))))
    (unwind-protect
        (progn (make-directory temporary)
               (write-region "#+TITLE: Index\n\nBody\n"
                             nil
                             source
                             nil
                             'silent)
               (let ((result (org-roam-blog--publish-generated-batch (list entry))))
                 (ert-info ((format "Batch result: %S" result))
                   (should (eq (plist-get result
                                          :status)
                               'success)))
                 (should (file-regular-p store-output))
                 (should (file-regular-p (expand-file-name "sitemap.html"
                                                           publish)))
                 (should (file-regular-p (expand-file-name "index.html"
                                                           publish)))
                 (with-temp-buffer
                   (insert-file-contents (expand-file-name "sitemap.html"
                                                           publish))
                   (should (search-forward "<meta name=\"sitemap-binding\">"
                                           nil
                                           t))
                   (should (search-forward "SITEMAP-BODY"
                                           nil
                                           t)))
                 (should (eq (plist-get sitemap-context
                                        :kind)
                             'sitemap))
                 (should-not (plist-get sitemap-context
                                        :entry))
                 (should (equal org-html-head
                                "outside-head"))
                 (should (equal (plist-get result
                                           :promoted)
                                (list store-output
                                      (expand-file-name "sitemap.html" publish)
                                      (expand-file-name "index.html" publish))))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-static-files-filter-and-preserve-layout ()
  (let* ((root (make-temp-file "org-roam-blog-static-" t))
         (source (expand-file-name "assets" root))
         (publish (expand-file-name "public" root))
         (org-roam-blog-publish-directory publish)
         (org-roam-blog-static (list (list :source source
                                           :directory "static"
                                           :extensions "css\\|svg"))))
    (unwind-protect
        (progn (make-directory (expand-file-name "icons"
                                                 source)
                               t)
               (write-region "body {}"
                             nil
                             (expand-file-name "site.css" source)
                             nil
                             'silent)
               (write-region "<svg/>"
                             nil
                             (expand-file-name "icons/logo.svg" source)
                             nil
                             'silent)
               (write-region "ignored"
                             nil
                             (expand-file-name "notes.txt" source)
                             nil
                             'silent)
               (let ((records (org-roam-blog--static-files)))
                 (should (equal (mapcar (lambda (record)
                                          (plist-get record
                                                     :target-relative))
                                        records)
                                '("static/icons/logo.svg" "static/site.css")))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-static-output-plan-detects-conflict ()
  (let* ((target "/tmp/public/site.css")
         (records (list (list :source "/tmp/assets/site.css"
                              :target target
                              :owner "static[0]")))
         (generated (list (org-roam-blog--plan-item 'sitemap
                                                    'manifest
                                                    target
                                                    'sitemap))))
    (should (org-roam-blog--output-conflicts (append generated
                                                     (org-roam-blog--static-output-plan records))))))

(ert-deftest org-roam-blog-test-publish-static-copies-without-global-project ()
  (let* ((root (make-temp-file "org-roam-blog-static-publish-" t))
         (source-directory (expand-file-name "assets" root))
         (source (expand-file-name "nested/site.css" source-directory))
         (target (expand-file-name "public/static/nested/site.css" root))
         (mapping (list :source source-directory
                        :directory "static"))
         (record (list :source source
                       :source-relative "nested/site.css"
                       :target target
                       :target-relative "static/nested/site.css"
                       :mapping mapping
                       :owner "org-roam-blog-static[0]"))
         (org-publish-project-alist '(("existing" :base-directory "/tmp"))))
    (unwind-protect
        (progn (make-directory (file-name-directory source)
                               t)
               (write-region "body {}"
                             nil
                             source
                             nil
                             'silent)
               (should (equal (org-roam-blog--publish-static (list record))
                              (list target)))
               (should (file-regular-p target))
               (with-temp-buffer
                 (insert-file-contents target)
                 (should (equal (buffer-string) "body {}")))
               (should (equal org-publish-project-alist
                              '(("existing" :base-directory "/tmp")))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-prepare-publication-stops-before-query ()
  (let ((org-roam-blog-directory "relative")
        queried)
    (cl-letf (((symbol-function 'org-roam-blog--build-manifest)
               (lambda ()
                 (setq queried t)
                 '(:entries nil :diagnostics nil))))
      (let ((result (org-roam-blog--prepare-publication)))
        (should (eq (plist-get result
                               :status)
                    'failure))
        (should-not queried)))))

(ert-deftest org-roam-blog-test-prepare-publication-allows-theindex ()
  (let ((org-roam-blog-theindex (list :enable t
                                      :path "theindex.html"))
        planned)
    (cl-letf (((symbol-function 'org-roam-blog--collect-diagnostics)
               (lambda () nil))
              ((symbol-function 'org-roam-blog--build-manifest)
               (lambda ()
                 '(:entries ((:source "/source/post.org"))
                   :diagnostics nil)))
              ((symbol-function 'org-roam-blog--static-files)
               (lambda () nil))
              ((symbol-function 'org-roam-blog--generated-output-plan)
               (lambda (entries)
                 (setq planned entries)
                 nil))
              ((symbol-function 'org-roam-blog--static-output-plan)
               (lambda (_records) nil))
              ((symbol-function 'org-roam-blog--output-conflicts)
               (lambda (_plan) nil))
              ((symbol-function 'org-roam-blog--output-target-diagnostics)
               (lambda (_plan) nil)))
      (let ((result (org-roam-blog--prepare-publication)))
        (should (eq (plist-get result
                               :status)
                    'success))
        (should (equal planned
                       '((:source "/source/post.org"))))
        (should-not (plist-get result
                               :diagnostics))))))

(ert-deftest org-roam-blog-test-prepare-publication-detects-static-conflict ()
  (let ((org-roam-blog-sitemap (list :enable t
                                     :path "index.html"))
        (org-roam-blog-theindex (list :enable nil)))
    (cl-letf (((symbol-function 'org-roam-blog--collect-diagnostics)
               (lambda () nil))
              ((symbol-function 'org-roam-blog--build-manifest)
               (lambda () '(:entries nil :diagnostics nil)))
              ((symbol-function 'org-roam-blog--static-files)
               (lambda ()
                 '((:source "/assets/index.html"
                            :target "/public/index.html"
                            :owner "static[0]"))))
              ((symbol-function 'org-roam-blog--generated-output-plan)
               (lambda (_entries)
                 (list (org-roam-blog--plan-item 'sitemap
                                                 'manifest
                                                 "/public/index.html"
                                                 'sitemap))))
              ((symbol-function 'org-roam-blog--output-target-diagnostics)
               (lambda (_plan) nil)))
      (let ((result (org-roam-blog--prepare-publication)))
        (should (eq (plist-get result
                               :status)
                    'failure))
        (should (string-match-p "Output conflict"
                                (plist-get (car (plist-get result
                                                           :diagnostics))
                                           :message)))))))

(ert-deftest org-roam-blog-test-publish-orders-stage-static-promote ()
  (let (events)
    (cl-letf (((symbol-function 'org-roam-blog--prepare-publication)
               (lambda ()
                 '(:status success :entries (entry)
                           :static (asset) :plan (plan)
                           :diagnostics nil)))
              ((symbol-function 'org-roam-blog--stage-generated-batch)
               (lambda (_entries)
                 (push 'stage events)
                 '(:status success :staging "/tmp/staging")))
              ((symbol-function 'org-roam-blog--publish-static-batch)
               (lambda (_records)
                 (push 'static events)
                 '(:status success :published ("/public/site.css"))))
              ((symbol-function 'org-roam-blog--promote-generated-batch)
               (lambda (_staged)
                 (push 'promote events)
                 '(:status success :staging nil
                           :promoted ("/public/index.html")))))
      (let ((result (org-roam-blog--publish)))
        (should (eq (plist-get result
                               :status)
                    'success))
        (should (equal (nreverse events) '(stage static promote)))
        (should (equal (plist-get result
                                  :static-published)
                       '("/public/site.css")))
        (should (equal (plist-get result
                                  :promoted)
                       '("/public/index.html")))))))

(ert-deftest org-roam-blog-test-publish-retains-staging-on-static-failure ()
  (cl-letf (((symbol-function 'org-roam-blog--prepare-publication)
             (lambda ()
               '(:status success :entries nil :static (asset)
                         :plan nil :diagnostics nil)))
            ((symbol-function 'org-roam-blog--stage-generated-batch)
             (lambda (_entries)
               '(:status success :staging "/tmp/staging")))
            ((symbol-function 'org-roam-blog--publish-static-batch)
             (lambda (_records)
               '(:status failure :published ("/public/a.css")
                         :diagnostics
                         ((:severity error :subject static
                                     :message "copy failed")))))
            ((symbol-function 'org-roam-blog--promote-generated-batch)
             (lambda (_staged)
               (ert-fail "Promotion must not run"))))
    (let ((result (org-roam-blog--publish)))
      (should (eq (plist-get result
                             :status)
                  'failure))
      (should (equal (plist-get result
                                :staging)
                     "/tmp/staging"))
      (should (equal (plist-get result
                                :static-published)
                     '("/public/a.css")))
      (should-not (plist-get result
                             :promoted)))))

(ert-deftest org-roam-blog-test-store-mirror-preserves-org-links ()
  (let* ((root (make-temp-file "org-roam-blog-links-" t))
         (source-root (expand-file-name "source" root))
         (source (expand-file-name "pages/index.org" source-root))
         (target (expand-file-name "posts/post.org" source-root))
         (staging (expand-file-name "staging" root))
         (output (expand-file-name "_org/pages/index.html" staging))
         (entry (list :source source
                      :store-relative "_org/pages/index.html"
                      :template (list :with-author nil))))
    (unwind-protect
        (progn (make-directory (file-name-directory source)
                               t)
               (make-directory (file-name-directory target)
                               t)
               (write-region (concat "#+TITLE: Index\n\n"
                                     "[[file:../posts/post.org][File link]]\n")
                             nil
                             source
                             nil
                             'silent)
               (org-roam-blog--export-content-entry entry
                                                    staging)
               (should (file-regular-p output))
               (with-temp-buffer
                 (insert-file-contents output)
                 (ert-info ((buffer-string))
                   (should (re-search-forward "href=\"\\.\\./posts/post\\.html\">File link"
                                              nil
                                              t)))))
      (delete-directory root t))))

(ert-deftest org-roam-blog-test-theindex-native-generation-and-state-isolation ()
  (let* ((root (make-temp-file "org-roam-blog-theindex-" t))
         (source-root (expand-file-name "source"
                                        root))
         (source-a (expand-file-name "posts/a b中.org"
                                     source-root))
         (source-b (expand-file-name "posts/a b中-extra.org"
                                     source-root))
         (publish (expand-file-name "public"
                                    root))
         (temporary (expand-file-name "temporary"
                                      root))
         (theindex-output (expand-file-name "indices/theindex.html"
                                            publish))
         (outside-cache (make-hash-table :test #'equal))
         (outside-id-locations (make-hash-table :test #'equal))
         (outside-id-locations-file (expand-file-name "outside-id-locations"
                                                      root))
         (outside-link-filter (lambda (output _backend _info)
                                output))
         (org-publish-cache outside-cache)
         (org-id-locations outside-id-locations)
         (org-id-locations-file outside-id-locations-file)
         (org-export-filter-link-functions (list outside-link-filter))
         (org-roam-blog-publish-directory publish)
         (org-roam-blog-temporary-directory temporary)
         (org-roam-blog-export-default (list :template
                                             (list :with-author nil)))
         (org-roam-blog-sitemap (list :enable nil))
         (theindex-context nil)
         (org-roam-blog-theindex
          (list :enable t
                :path "indices/theindex.html"
                :title "Native Index"
                :body
                (list (lambda (context)
                        (setq theindex-context context)
                        (plist-get context
                                   :body)))))
         (entry-a
          (list :title "Selected"
                :source source-a
                :source-truename source-a
                :source-relative "posts/a b中.org"
                :store-relative "_store/uuid-a/a b中.html"
                :store-output (expand-file-name "_store/uuid-a/a b中.html"
                                                publish)
                :theindex t
                :template (list :with-author nil)))
         (entry-b
          (list :title "Excluded"
                :source source-b
                :source-truename source-b
                :source-relative "posts/a b中-extra.org"
                :store-relative "_store/uuid-b/a b中-extra.html"
                :store-output (expand-file-name "_store/uuid-b/a b中-extra.html"
                                                publish)
                :theindex nil
                :template (list :with-author nil))))
    (unwind-protect
        (progn
          (make-directory (file-name-directory source-a)
                          t)
          (make-directory publish)
          (make-directory temporary)
          (write-region (concat "#+TITLE: Selected\n"
                                "#+INDEX: File Entry\n\n"
                                "* Custom Heading\n"
                                ":PROPERTIES:\n"
                                ":CUSTOM_ID: custom-heading\n"
                                ":END:\n"
                                "#+INDEX: Nested!Custom\n\n"
                                "* Identified Heading\n"
                                ":PROPERTIES:\n"
                                ":ID: probe-id\n"
                                ":END:\n"
                                "#+INDEX: Nested!Identified\n\n"
                                "* Ordinary Heading\n"
                                "#+INDEX: Nested!Ordinary\n")
                        nil
                        source-a
                        nil
                        'silent)
          (write-region (concat "#+TITLE: Excluded\n"
                                "#+INDEX: Must Not Appear\n")
                        nil
                        source-b
                        nil
                        'silent)
          (cl-letf (((symbol-function 'org-id-find)
                     (lambda (id &optional markerp)
                       (when (equal id
                                    "probe-id")
                         (org-id-find-id-in-file id
                                                 source-a
                                                 markerp)))))
            (let ((staged (org-roam-blog--stage-generated-batch
                           (list entry-a
                                 entry-b))))
              (ert-info ((format "Staging result: %S"
                                 staged))
                (should (eq (plist-get staged
                                       :status)
                            'success)))
              (should (eq org-publish-cache
                          outside-cache))
              (should (eq org-id-locations
                          outside-id-locations))
              (should (equal org-id-locations-file
                             outside-id-locations-file))
              (should (equal org-export-filter-link-functions
                             (list outside-link-filter)))
              (should (eq (plist-get theindex-context
                                     :kind)
                          'theindex))
              (let ((staged-theindex (cdr (plist-get staged
                                                     :theindex))))
                (should (file-regular-p staged-theindex))
                (with-temp-buffer
                  (insert-file-contents staged-theindex)
                  (ert-info ((buffer-string))
                    (should (search-forward "<title>Native Index</title>"
                                            nil
                                            t))
                    (should (search-forward "../_store/uuid-a/a%20b%E4%B8%AD.html"
                                            nil
                                            t))
                    (should (search-forward "#custom-heading"
                                            nil
                                            t))
                    (should (search-forward "#ID-probe-id"
                                            nil
                                            t))
                    (should (re-search-forward "#org[[:xdigit:]]+"
                                               nil
                                               t))
                    (should-not (search-forward "Must Not Appear"
                                                nil
                                                t))
                    (should-not (search-forward source-root
                                                nil
                                                t)))))
              (let ((promoted (org-roam-blog--promote-generated-batch staged)))
                (ert-info ((format "Promotion result: %S"
                                   promoted))
                  (should (eq (plist-get promoted
                                         :status)
                              'success)))
                (should (file-regular-p theindex-output))
                (should (member theindex-output
                                (plist-get promoted
                                           :promoted)))))))
      (delete-directory root
                        t))))

;;; org-roam-blog-test.el ends here
