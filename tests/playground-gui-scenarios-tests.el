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

(ert-deftest etaf-playground-gui-viewport-noop-keeps-revision-contract ()
  "Unchanged geometry needs no new revision; an actual resize still does."
  (let ((context (etaf-gui-verifier--context-create)))
    (cl-letf (((symbol-function 'etaf-playground-gui-scenarios--report)
               (lambda (_context) '(:runtime-revision 7)))
              ((symbol-function 'ebox-surface-buffer-revision) (lambda (_) 7))
              ((symbol-function 'frame-parameter) (lambda (&rest _) nil))
              ((symbol-function 'frame-text-width) (lambda (&rest _) 1000))
              ((symbol-function 'frame-text-height) (lambda (&rest _) 700)))
      (etaf-playground-gui-scenarios--begin-viewport-change context nil)
      (should-not (etaf-gui-verifier-context-get context 'viewport-revision-before))
      (etaf-playground-gui-scenarios--begin-viewport-change context nil 1000 700)
      (should-not (etaf-gui-verifier-context-get context 'viewport-revision-before))
      (etaf-playground-gui-scenarios--begin-viewport-change context nil 700 500)
      (should (= (etaf-gui-verifier-context-get context 'viewport-revision-before) 7))
      (etaf-playground-gui-scenarios--begin-viewport-change context 'fullboth)
      (should (= (etaf-gui-verifier-context-get context 'viewport-revision-before) 7)))))

(ert-deftest etaf-playground-gui-viewport-noop-settles-after-scroll-report ()
  "A no-op proves unchanged geometry and revision without a viewport report."
  (with-temp-buffer
    (let ((context (etaf-gui-verifier--context-create
                    :target-buffer (current-buffer)))
          (window (selected-window)) (revision 7)
          (width 1000) (height 40) (frame-width 1000) (frame-height 700))
      (cl-letf (((symbol-function 'etaf-playground-gui-scenarios--report)
                 (lambda (_) '(:constraint-source scroll :runtime-revision 6)))
                ((symbol-function 'ebox-surface-buffer-mounted-p) (lambda (_) t))
                ((symbol-function 'ebox-surface-buffer-revision) (lambda (_) revision))
                ((symbol-function 'selected-window) (lambda () window))
                ((symbol-function 'ebox-viewport-window-width) (lambda (_) width))
                ((symbol-function 'window-body-height) (lambda (&rest _) height))
                ((symbol-function 'frame-parameter) (lambda (&rest _) nil))
                ((symbol-function 'frame-text-width) (lambda (&rest _) frame-width))
                ((symbol-function 'frame-text-height) (lambda (&rest _) frame-height))
                ((symbol-function 'etaf-playground-gui-scenarios--visible-window-content-p)
                 (lambda (_) t)))
        (etaf-playground-gui-scenarios--begin-viewport-change context nil)
        (should (etaf-playground-gui-scenarios--viewport-settled-p context))
        (let ((assertions (etaf-playground-gui-scenarios--resize-assertions context)))
          (should (equal "viewport-unchanged" (alist-get 'name (car assertions))))
          (should (cl-every (lambda (entry) (alist-get 'passed entry)) assertions)))
        (dolist (change (list (lambda () (setq window 'different-window))
                             (lambda () (cl-incf width))
                             (lambda () (cl-incf height))
                             (lambda () (cl-incf frame-width))
                             (lambda () (cl-incf frame-height))
                             (lambda () (cl-incf revision))))
          (let ((original-window window))
            (unwind-protect
                (progn
                  (funcall change)
                  (should-not (etaf-playground-gui-scenarios--viewport-settled-p context)))
              (setq window original-window width 1000 height 40
                    frame-width 1000 frame-height 700 revision 7)))
          (should (etaf-playground-gui-scenarios--viewport-settled-p context)))))))

(ert-deftest etaf-playground-gui-real-resize-requires-matching-publication ()
  "An actual resize cannot reuse a stale, absent, or mismatched report."
  (with-temp-buffer
    (let ((context (etaf-gui-verifier--context-create
                    :target-buffer (current-buffer)))
          (frame-width 1000)
          (revision 37)
          (report '(:runtime-revision 36 :surface-revision 37)))
      (cl-letf (((symbol-function 'etaf-playground-gui-scenarios--report)
                 (lambda (_) report))
                ((symbol-function 'ebox-surface-buffer-mounted-p) (lambda (_) t))
                ((symbol-function 'ebox-surface-buffer-revision) (lambda (_) revision))
                ((symbol-function 'frame-parameter) (lambda (&rest _) nil))
                ((symbol-function 'frame-text-width) (lambda (&rest _) frame-width))
                ((symbol-function 'frame-text-height) (lambda (&rest _) 700))
                ((symbol-function 'ebox-viewport-window-width) (lambda (_) 700))
                ((symbol-function 'window-body-height) (lambda (&rest _) 40))
                ((symbol-function 'etaf-playground-gui-scenarios--visible-window-content-p)
                 (lambda (_) t)))
        (etaf-playground-gui-scenarios--begin-viewport-change context nil 700 700)
        (setq frame-width 700 revision 38)
        (dolist (invalid '((:runtime-revision 37 :surface-revision 38 :runtime-published t)
                           (:runtime-revision 37 :surface-revision 38
                            :runtime-published t :viewport-width 800)
                           (:runtime-revision 37 :surface-revision 38 :viewport-width 700)
                           (:runtime-revision 37 :surface-revision 38 :runtime-published t
                            :viewport-width 700 :tp-scope-fallback t)
                           ;; Neither a stale nor a future report belongs to
                           ;; the currently committed surface, regardless of
                           ;; its unrelated runtime revision or matching width.
                           (:runtime-revision 99 :surface-revision 37
                            :runtime-published t :viewport-width 700)
                           (:runtime-revision 99 :surface-revision 39
                            :runtime-published t :viewport-width 700)
                           (:runtime-revision 99 :runtime-published t :viewport-width 700)))
          (setq report (append invalid '(:target-viewport-height 40)))
          (should-not (etaf-playground-gui-scenarios--viewport-settled-p context)))
        (setq report '(:runtime-revision 37 :surface-revision 38
                       :runtime-published t :target-viewport-width 700
                       :target-viewport-height 40))
        (should (etaf-playground-gui-scenarios--viewport-settled-p context))
        (setq revision 39)
        (should-not (etaf-playground-gui-scenarios--viewport-settled-p context))
        (should-not
         (alist-get 'passed
                    (car (etaf-playground-gui-scenarios--resize-assertions context))))))))

(ert-deftest etaf-playground-gui-resize-compares-surface-revisions-only ()
  "GUI runtime37/surface38 succeeds against public before37/after38."
  (with-temp-buffer
    (let ((context (etaf-gui-verifier--context-create
                    :target-buffer (current-buffer))))
      (etaf-gui-verifier-context-put context 'viewport-revision-before 37)
      (cl-letf (((symbol-function 'etaf-playground-gui-scenarios--report)
                 (lambda (_) '(:runtime-revision 37 :surface-revision 38
                               :runtime-published t :target-viewport-width 686
                               :target-viewport-height 40)))
                ((symbol-function 'ebox-surface-buffer-mounted-p) (lambda (_) t))
                ((symbol-function 'ebox-surface-buffer-revision) (lambda (_) 38))
                ((symbol-function 'ebox-viewport-window-width) (lambda (_) 686))
                ((symbol-function 'window-body-height) (lambda (&rest _) 40))
                ((symbol-function 'etaf-playground-gui-scenarios--frame-target-settled-p)
                 (lambda (_) t))
                ((symbol-function 'etaf-playground-gui-scenarios--visible-window-content-p)
                 (lambda (_) t)))
        (should (etaf-playground-gui-scenarios--viewport-settled-p context))))))

(ert-deftest etaf-playground-gui-height-only-resize-requires-current-height ()
  "A 40-to-25-row resize rejects stale, missing, and nonnumeric target heights."
  (with-temp-buffer
    (let ((context (etaf-gui-verifier--context-create
                    :target-buffer (current-buffer)))
          (height 40) (frame-height 700) (revision 37) report)
      (cl-letf (((symbol-function 'etaf-playground-gui-scenarios--report)
                 (lambda (_) report))
                ((symbol-function 'ebox-surface-buffer-mounted-p) (lambda (_) t))
                ((symbol-function 'ebox-surface-buffer-revision) (lambda (_) revision))
                ((symbol-function 'frame-parameter) (lambda (&rest _) nil))
                ((symbol-function 'frame-text-width) (lambda (&rest _) 1000))
                ((symbol-function 'frame-text-height) (lambda (&rest _) frame-height))
                ((symbol-function 'ebox-viewport-window-width) (lambda (_) 1000))
                ((symbol-function 'window-body-height) (lambda (&rest _) height))
                ((symbol-function 'etaf-playground-gui-scenarios--visible-window-content-p)
                 (lambda (_) t)))
        (etaf-playground-gui-scenarios--begin-viewport-change context nil 1000 500)
        (should (= 37 (etaf-gui-verifier-context-get context 'viewport-revision-before)))
        (should-not (etaf-gui-verifier-context-get context 'viewport-noop-before))
        (setq height 25 frame-height 500 revision 38
              report '(:runtime-published t :surface-revision 38
                       :target-viewport-width 1000 :target-viewport-height 25))
        (should (etaf-playground-gui-scenarios--viewport-settled-p context))
        (dolist (height-report '((:target-viewport-height 40)
                                  nil (:target-viewport-height "25")
                                  (:viewport-height 25)))
          (setq report (append '(:runtime-published t :surface-revision 38
                                 :target-viewport-width 1000)
                               height-report))
          (should-not (etaf-playground-gui-scenarios--viewport-settled-p context)))))))

(provide 'playground-gui-scenarios-tests)
;;; playground-gui-scenarios-tests.el ends here
