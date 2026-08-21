;;; etaf-playground-tests.el --- operations-console pair contract -*- lexical-binding: t; -*-
;;; Code:
(require 'ert)
(require 'etaf-playground)
(defvar etaf-operations-console-cleanup-count)

(defun etaf-playground-test--text (buffer)
  "Return BUFFER plain text."
  (with-current-buffer buffer (substring-no-properties (buffer-string))))

(defun etaf-playground-test--close (buffer)
  "Close BUFFER when it exists."
  (when (get-buffer buffer) (etaf-playground-close buffer)))

(ert-deftest etaf-playground-manifest-has-one-reviewed-pair ()
  "Expose only the operations-console pair and keep old examples inactive."
  (should (equal '("operations-console") etaf-playground-example-names))
  (should (= 1 (length etaf-playground-scenario-manifest)))
  (let ((entry (car etaf-playground-scenario-manifest))
        (makefile (with-temp-buffer
                    (insert-file-contents "Makefile") (buffer-string))))
    (dolist (key '(:pair :root-component :capabilities :refs
                   :gui-checkpoints :performance))
      (should (plist-member entry key)))
    (should (string-match-p
             "EXAMPLE_EL := examples/operations-console.el" makefile))
    (should-not (string-match-p "wildcard examples" makefile))))

(ert-deftest etaf-playground-compile-builds-bytecode-dependencies ()
  "Integration builds must not silently fall back to interpreted dependencies."
  (let ((makefile (with-temp-buffer
                    (insert-file-contents "Makefile")
                    (buffer-string))))
    (dolist (dependency '("$(MAKE) -C ../ecss compile"
                          "$(MAKE) -C ../tp compile"
                          "$(MAKE) -C ../ebox compile"
                          "$(MAKE) -C ../etaf compile"
                          "$(MAKE) -C ../etaf-ui compile"))
      (should (string-match-p (regexp-quote dependency) makefile)))))

(ert-deftest etaf-playground-static-reader-is-inert-and-strict ()
  "Read static data without companion execution and reject unsafe AST nodes."
  (when (featurep 'etaf-operations-console)
    (unload-feature 'etaf-operations-console t))
  (let ((form (etaf-playground-read-static "operations-console")))
    (should (equal (car form) 'operations-console-shell))
    (should (equal (plist-get (cdr form) :title) "Operations Console"))
    (should (equal (mapcar #'car
                           (cl-remove-if-not #'consp (cdr form)))
                   '(header navigation main status))))
  (should-not (featurep 'etaf-operations-console))
  (dolist (form '((lambda () 1) (eval '(message "x"))
                  (etaf--private) (ebox--private) (shell-command "x")))
    (should-error (etaf-playground--validate-static-node form) :type 'error)))

(ert-deftest etaf-playground-pair-load-and-mount-is-repeatable ()
  "Load the same pair twice and mount/unmount it twice without stale state."
  (let ((buffer " *etaf-operations-console-pair-test*"))
    (unwind-protect
        (dotimes (_iteration 2)
          (let ((form (etaf-playground-read-static "operations-console")))
            (should (equal (car form) 'operations-console-shell))
            (should (equal (mapcar #'car
                                   (cl-remove-if-not #'consp (cdr form)))
                           '(header navigation main status))))
          (etaf-playground-mount-example buffer "operations-console")
          (should (etaf-runtime-p (etaf-runtime-for-buffer buffer)))
          (should (string-match-p "Operations Console"
                                  (etaf-playground-test--text buffer)))
          (etaf-unmount (etaf-runtime-for-buffer buffer))
          (when (get-buffer buffer) (kill-buffer buffer))
          (should-not (etaf-runtime-for-buffer buffer)))
      (etaf-playground-test--close buffer))
    (should-not (etaf-runtime-for-buffer buffer))))

(ert-deftest etaf-playground-operations-console-drives-public-refs ()
  "Drive representative app capabilities through public event/focus ports."
  (let ((buffer " *etaf-operations-console-actions-test*"))
    (unwind-protect
        (progn
          (dolist (entry
                   '((operations-console-alpha-increment)
                     (operations-console-alpha-reset)
                     (operations-console-beta-increment)
                     (operations-console-beta-reset)
                     (operations-console-local-callback)
                     (operations-console-named-action)
                     (operations-console-behavior-toggle)
                     (operations-console-theme-toggle)
                     (operations-console-nav-data)
                     (operations-console-clear-selection operations-console-nav-data)
                     (operations-console-row-1 operations-console-nav-data)
                     (operations-console-row-2 operations-console-nav-data)
                     (operations-console-row-3 operations-console-nav-data)
                     (operations-console-nav-resource)
                     (operations-console-fail-next operations-console-nav-resource)
                     (operations-console-resource-reload operations-console-nav-resource)
                     (operations-console-error-boundary operations-console-nav-resource)
                     (operations-console-nav-overview)))
            (etaf-playground-open buffer)
            (let* ((runtime (etaf-runtime-for-buffer buffer))
                   (ref (car entry))
                   (page-ref (cadr entry)))
              (when page-ref
                (etaf-dispatch-event runtime page-ref 'press))
              (etaf-focus runtime ref)
              (should (eq ref (etaf-focused-host-ref runtime)))
              (etaf-dispatch-event runtime ref 'press)
              (when (eq ref 'operations-console-theme-toggle)
                (should (string-match-p
                         "☑[[:space:]]+Theme"
                         (etaf-playground-test--text buffer))))
              (etaf-playground-close buffer))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-data-grid-row-selection-is-repeatable ()
  "Repeated row presses replace the single selected row without a bar."
  (let ((buffer " *etaf-operations-console-row-selection-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (etaf-dispatch-event runtime 'operations-console-nav-data 'press)
            (dolist (entry '((operations-console-row-1 . "Selected Ada")
                             (operations-console-row-2 . "Selected Grace")
                             (operations-console-row-3 . "Selected Lin")
                             (operations-console-row-1 . "Selected Ada")
                             (operations-console-row-2 . "Selected Grace")))
              (etaf-focus runtime (car entry))
              (etaf-dispatch-event runtime (car entry) 'press)
              (let ((text (etaf-playground-test--text buffer)))
                (should (string-match-p (regexp-quote (cdr entry)) text))
                (should-not (string-match-p "#DCEBDD" text))))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-behavior-toggle-uses-one-retained-publication ()
  "Behavior content and paint changes stay in two fixed owners per turn."
  (let ((buffer " *etaf-operations-console-behavior-retained-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (surface (with-current-buffer
                              buffer ebox-surface--buffer-surface))
                 (old-commit (symbol-function 'ebox-commit))
                 (root-id (plist-get
                           (plist-get (ebox--buffer-render-state buffer)
                                      :root-node)
                           :node-id)))
            (dotimes (index 4)
              (let ((commits 0)
                    (before (etaf-runtime-generation runtime)))
                (cl-letf (((symbol-function 'ebox-commit)
                           (lambda (&rest args)
                             (cl-incf commits)
                             (apply old-commit args))))
                  (etaf-dispatch-event runtime
                                       'operations-console-behavior-toggle
                                       'press))
                (let ((report (ebox-buffer-update-report buffer)))
                  (should (= commits 1))
                  (should (= 1 (- (etaf-runtime-generation runtime)
                                  before)))
                  (should (eq (plist-get report :projection-kind)
                              'owner-scoped))
                  (should-not (plist-get report :tp-full-root))
                  (should-not (plist-get report :tp-scope-fallback))
                  (should (= 2 (plist-get report :tp-scope-count)))
                  (should (= 2 (plist-get report :tp-scope-range-count)))
                  (should (= 2 (plist-get report :tp-text-operations)))
                  (should-not (member root-id (plist-get report :owner-ids)))
                  (should (< (plist-get report :reconciled-objects)
                             (plist-get (tp-surface-inspect surface)
                                        :object-count))))
                (should (string-match-p
                         (if (cl-evenp index)
                             "Behavior toggle: on"
                           "Behavior toggle: off")
                         (etaf-playground-test--text buffer)))))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-a-theme-toggle-uses-mixed-owner-publication ()
  "Theme paint plus fixed-slot label changes publish through one mixed owner."
  (let ((buffer " *etaf-operations-console-theme-mixed-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (before (etaf-runtime-generation runtime))
                 (commits 0)
                 (old-commit (symbol-function 'ebox-commit)))
            (cl-letf (((symbol-function 'ebox-commit)
                       (lambda (&rest args)
                         (cl-incf commits)
                         (apply old-commit args))))
              (etaf-dispatch-event runtime
                                   'operations-console-theme-toggle
                                   'press))
            (let ((report (ebox-buffer-update-report buffer)))
              (should (= commits 1))
              (should (= 1 (- (etaf-runtime-generation runtime) before)))
              (should (eq (plist-get report :projection-kind)
                          'mixed-owner-reflow))
              (should-not (plist-get report :tp-full-root))
              (should-not (plist-get report :tp-scope-fallback))
              (should-not
               (member (ebox--buffer-root-node-id buffer)
                       (plist-get report :owner-ids)))
              (should (string-match-p "☑[[:space:]]+Theme"
                                      (etaf-playground-test--text buffer)))
              (should (string-match-p "Theme: Dark"
                                      (etaf-playground-test--text buffer))))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-a-theme-toggle-after-navigation-retires-nested-range-effects ()
  "Theme changes after page navigation must not reuse removed Range anchors."
  (let ((buffer " *etaf-operations-console-theme-after-navigation-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (before (etaf-runtime-generation runtime)))
            (etaf-dispatch-event runtime 'operations-console-nav-data 'press)
            (dotimes (_ 4)
              (etaf-dispatch-event runtime
                                   'operations-console-theme-toggle 'press))
            (should (= 5 (- (etaf-runtime-generation runtime) before)))
            (should (string-match-p "Data desk"
                                    (etaf-playground-test--text buffer)))
            (should (string-match-p "Theme: Light"
                                    (etaf-playground-test--text buffer)))
            (should (plist-get (ebox-buffer-update-report buffer)
                               :strategy))
            (let* ((generation (etaf-runtime-current-generation runtime))
                   (nodes (etaf-generation-semantic-nodes generation))
                   (stale 0))
              (dotimes (effect-id (etaf-runtime-next-effect-id runtime))
                (when-let ((effect (etaf--generation-effect
                                    generation effect-id)))
                  (unless (etaf--pvec-get
                           nodes
                           (etaf--generation-effect-semantic-id effect))
                    (cl-incf stale))))
              (should (zerop stale)))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-repeated-counter-press-retains-handler ()
  "Recreated keyed counter Hosts keep their public handler across turns."
  (let ((buffer " *etaf-operations-console-repeat-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (let ((runtime (etaf-runtime-for-buffer buffer))
                (old-commit (symbol-function 'ebox-commit)))
            (dotimes (expected 3)
              (let ((commits 0)
                    (before (etaf-runtime-generation runtime)))
                (cl-letf (((symbol-function 'ebox-commit)
                           (lambda (&rest args)
                             (cl-incf commits)
                             (apply old-commit args))))
                  (etaf-dispatch-event runtime
                                       'operations-console-alpha-increment 'press))
                (should (= commits 1))
                (should (= 1 (- (etaf-runtime-generation runtime) before))))
              (should (etaf-runtime-handler-for
                       runtime 'operations-console-alpha-increment))
              (should (string-match-p
                       (format "Value: %d" (1+ expected))
                       (etaf-playground-test--text buffer))))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-reset-and-close-use-pair-boundary ()
  "Reset the sole pair and leave no mounted Runtime after close."
  (let ((buffer " *etaf-operations-console-reset-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (etaf-playground-reset buffer)
          (should (etaf-runtime-for-buffer buffer))
          (etaf-playground-close buffer)
          (should-not (get-buffer buffer)))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-navigation-swaps-one-page-subtree ()
  "Show exactly the selected Overview, Data, or Resource page."
  (let ((buffer " *etaf-operations-console-navigation-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (root-id
                  (plist-get
                   (plist-get (ebox--buffer-render-state buffer)
                              :root-node)
                   :node-id)))
            (should (string-match-p "Counter alpha"
                                    (etaf-playground-test--text buffer)))
            (etaf-dispatch-event runtime 'operations-console-nav-data 'press)
            (should (string-match-p "Data Controller"
                                    (etaf-playground-test--text buffer)))
            (let ((report (ebox-buffer-update-report buffer)))
              (should-not (plist-get report :tp-full-root))
              (should-not (plist-get report :tp-scope-fallback))
              (should (plist-get report :range-metrics))
              (should-not (member root-id (plist-get report :owner-ids)))
              (should (= 1 (plist-get report :tp-scope-range-count))))
            (should-not (string-match-p "Counter alpha"
                                        (etaf-playground-test--text buffer)))
            (etaf-dispatch-event runtime 'operations-console-nav-resource 'press)
            (should (string-match-p "Resource and Error Boundary"
                                    (etaf-playground-test--text buffer)))
            (should-not (string-match-p "Data Controller"
                                        (etaf-playground-test--text buffer)))
            (etaf-dispatch-event runtime 'operations-console-nav-overview 'press)
            (should (string-match-p "Counter alpha"
                                    (etaf-playground-test--text buffer)))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-controls-use-intrinsic-single-line-widths ()
  "Keep navigation and action controls on their owning row without clipping."
  (let ((buffer " *etaf-operations-console-control-width-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (let ((nav (etaf-host-ref-bounds runtime 'operations-console-nav))
                  (main (etaf-host-ref-bounds runtime 'operations-console-main))
                  (status (etaf-host-ref-bounds runtime
                                                'operations-console-status)))
              ;; These are vertical shell siblings.  If the navigation flex
              ;; group is accidentally left open, MAIN and STATUS become row
              ;; children and the whole application is laid out horizontally.
              (with-current-buffer buffer
                (should (< (line-number-at-pos (car nav))
                           (line-number-at-pos (car main))))
                (should (< (line-number-at-pos (car main))
                           (line-number-at-pos (car status))))))
            (dolist (refs '((operations-console-nav-overview
                             operations-console-nav-data
                             operations-console-nav-resource
                             operations-console-theme-toggle)
                            (operations-console-local-callback
                             operations-console-named-action
                             operations-console-behavior-toggle)))
              (let (lines)
                (dolist (ref refs)
                  (let ((bounds (etaf-host-ref-bounds runtime ref)))
                    (should bounds)
                    (with-current-buffer buffer
                      (push (line-number-at-pos (car bounds)) lines)
                      (should (<= (cdr bounds) (point-max))))))
                (should (= 1 (length (delete-dups lines))))
                ;; The navigation owner declares a pixel gap so adjacent
                ;; mouse-face ranges remain distinct controls.
                (should (equal
                         (plist-get
                          (gethash 'operations-console-nav
                                   (etaf-runtime-host-props runtime))
                          :gap)
                         '(0 (8))))))))
      (etaf-playground-test--close buffer))))

(ert-deftest etaf-playground-fixed-viewport-layout-does-not-double-width ()
  "Keep every rendered line inside the containing viewport after reflow."
  (let ((buffer " *etaf-operations-console-width-test*"))
    (unwind-protect
        (progn
          (etaf-playground-open buffer)
          (ebox-surface-update-buffer-viewport (get-buffer buffer) 1413 60)
          (with-current-buffer buffer
            (let (widths)
              (goto-char (point-min))
              (while (< (point) (point-max))
                (push (ebox--string-pixel-width
                       (buffer-substring (point) (line-end-position)))
                      widths)
                (forward-line 1))
              (setq widths (nreverse widths))
              (should (= 60 (length widths)))
              (should (<= (apply #'max widths) 1413)))))
      (etaf-playground-test--close buffer))))

(provide 'etaf-playground-tests)
;;; etaf-playground-tests.el ends here
