;;; playground-gui-scenarios-tests.el --- GUI scenario contracts -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests keep the Research Shelf GUI action matrix aligned with the M0a
;; evidence claim without running a graphical Emacs session.

;;; Code:

(require 'cl-lib)
(require 'ert)
(add-to-list 'load-path (expand-file-name "../etaf/scripts" default-directory))
(add-to-list 'load-path (expand-file-name "../ebox-playground" default-directory))
(require 'playground-gui-scenarios)

(defvar etaf-research-shelf-database-file)
(defvar etaf-research-shelf-fixture-size)
(defvar etaf-research-shelf-page-size)

(defun etaf-playground-gui-test--action (scenario id)
  "Return SCENARIO action named ID."
  (cl-find id (etaf-gui-verifier-scenario-actions scenario)
           :key #'etaf-gui-verifier-action-id :test #'equal))

(ert-deftest etaf-playground-gui-research-covers-public-action-matrix ()
  "Research Shelf covers every required public M0a interaction in order."
  (let* ((scenario (etaf-playground-gui-scenarios-research))
         (actions (etaf-gui-verifier-scenario-actions scenario)))
    (should
     (equal
      (mapcar #'etaf-gui-verifier-action-id actions)
      '("mount" "leave-fullscreen" "resize-narrow" "resize-compact"
        "scroll-down" "reset-scroll" "resize-wide" "row-select"
        "data-mutation" "filter-reading" "theme-toggle" "pagination"
        "maximize-frame")))
    (should
     (funcall
      (etaf-gui-verifier-scenario-completion scenario)
      (etaf-gui-verifier--context-create
       :scenario scenario :action-count (length actions))))))

(ert-deftest etaf-playground-gui-research-names-product-assertions ()
  "Public filter and mutation actions publish specific passing assertions."
  (let ((database (make-temp-file "etaf-gui-research-" nil ".sqlite"))
        (buffer " *etaf-gui-research-test*"))
    (unwind-protect
        (let* ((etaf-research-shelf-database-file database)
               (etaf-research-shelf-fixture-size 32)
               (etaf-research-shelf-page-size 12)
               (scenario (etaf-playground-gui-scenarios-research))
               context)
          (ignore etaf-research-shelf-database-file
                  etaf-research-shelf-fixture-size
                  etaf-research-shelf-page-size)
          (etaf-playground-mount-example
           buffer "research-shelf" nil
           '(:viewport-width 1400 :viewport-height 80))
          (switch-to-buffer buffer)
          (setq context
                (etaf-gui-verifier--context-create
                 :scenario scenario :target-buffer (get-buffer buffer)))
          (dolist (entry '(("row-select")
                           ("data-mutation" . "progress-persisted")
                           ("filter-reading" . "reading-filter-applied")))
            (let ((id (car entry))
                  (assertion-name (cdr entry)))
              (let ((action
                     (etaf-playground-gui-test--action scenario id)))
                (should action)
                (funcall (etaf-gui-verifier-action-execute action) context)
                (should
                 (funcall
                  (etaf-gui-verifier-action-settled-p action) context))
                (when assertion-name
                  (let* ((assertions
                          (funcall
                           (etaf-gui-verifier-action-assertions action)
                           context))
                         (assertion
                          (cl-find
                           assertion-name assertions
                           :key (lambda (item) (alist-get 'name item))
                           :test #'equal)))
                    (should assertion)
                    (should (alist-get 'passed assertion))))))))
      (when (get-buffer buffer)
        (etaf-playground-close buffer))
      (when (file-exists-p database)
        (delete-file database)))))

(provide 'playground-gui-scenarios-tests)
;;; playground-gui-scenarios-tests.el ends here
