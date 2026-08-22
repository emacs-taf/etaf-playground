;;; etaf-playground-catalog.el --- Reviewed Playground pair catalog -*- lexical-binding: t; -*-

;;; Commentary:
;; Deployment configuration lives outside the generic loader.  Adding or
;; replacing an application changes this catalog and its pair, not framework
;; loading, validation, mounting, or lifecycle semantics.

;;; Code:

(defconst etaf-playground-catalog
  '((:pair "research-shelf"
     :root-component etaf-research-shelf-root
     :companion-feature etaf-research-shelf
     :static-tags (research-shelf-shell header filters filter main library
                                         detail footer)
     :category "SQLite-backed research library"
     :capabilities (view component reactivity context theme events data sqlite
                    pagination mutation lifecycle etaf-ui)
     :refs (research-shelf-filter-all research-shelf-filter-reading
            research-shelf-filter-unread research-shelf-filter-finished
            research-shelf-filter-starred research-shelf-theme-toggle
            research-shelf-reload research-shelf-add research-shelf-progress
            research-shelf-finish research-shelf-star research-shelf-archive
            research-shelf-page-previous research-shelf-page-next)
     :gui-checkpoints (compact fullscreen all reading unread detail theme)
     :performance (:warm-runs 8 :publication-per-event 1)))
  "Reviewed same-basename pair specifications available to the Playground.")

(provide 'etaf-playground-catalog)
;;; etaf-playground-catalog.el ends here
