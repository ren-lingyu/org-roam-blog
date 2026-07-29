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

(require 'org)
(require 'ox)
(require 'ox-html)
(require 'ox-publish)
(require 'org-roam)

(provide 'org-roam-blog)

;;; org-roam-blog.el ends here
